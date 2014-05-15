#!/usr/bin/python  
# honeyport-0.1.py
# Python (v2.6-3.4) Honeyport with OSX/Linux/Windows and Dome9 support
# By Sebastien Jeanquier (@securitygen)
# Security Generation - http://www.securitygeneration.com
#
# Contributions: Dean @sysop_host (testing)
#
# Description: This script listens on a port and blacklists any IP that connects to it using IPtables, IPFW, Windows Firewall or the Dome9 service.
#
# ChangeLog -
# 0.1: Initial release (2014-05-15)
#
# TODO: Whitelist file, Blacklist timeout for system firewall rules, Multiple ports?, Unix support
# ----CONFIG START----------------------------------------------
# Configuration
# Set your port number
port = 31337
# Blacklist using Dome9 (set to False to use local system firewall: iptables/ifpw/Windows Firewall)
dome9 = False
# Your Dome9 username (eg. user@email.com)
domeuser = ''
# Your Dome9 API key (https://secure.dome9.com/settings under API Key)
domeapi = ''
# Optional parameter to allow Dome9 Blacklist items to auto-expire after a certain amount of time (in seconds). Set to 0 for permanent blacklisting.
dome9ttl = 86400 # eg. 86400 = 24h
# Whitelisted IPs eg: ["123.123.123.123", "1.2.3.4"]
whitelist = [""]
# Logfile location (leave blank for no file logging)
logfile = "honeyport.log"
# Response string that is sent to the connecting client (ie "Go Away!")
response = "Go Away!"
# Path to response script that gets run upon client connection and returns a string to be sent back
# This script will be executed by Python and will be passed the client IP as a parameter
# If this is set, it will override the response string set above.
response_script = ""
# ----CONFIG END-------------------------------------------------

# Imports
import socket				# Import socket module
import platform				# Import platform module to determine the os
import sys, getopt			# Import sys and getopt to grab some cmd options like port number
import os					# Import os because on Linux to run commands I had to use popen
import requests				# Import requests to perform HTTP requests to Dome9
import datetime				# For logging with timestamps
import logging				# To write logs
import ctypes				# For Windows Admin check
from subprocess import CalledProcessError, check_output # Import module for making OS commands (os.system is deprecated)

platform = platform.system() # Get the current platform (Linux, Darwin, Windows)

if not dome9: # Check for root
	if platform == "Unix" or platform == "Darwin": # If Unix or Darwin
		if not os.geteuid()==0:
			sys.exit("\n[!] Root privileges are required to modify firewall rules.\n")
	elif platform == "Windows":
		if not ctypes.windll.shell32.IsUserAnAdmin():
			sys.exit("\n[!] Admin privileges are required to modify firewall rules.\n")
	else:
		sys.exit("\n[!] \"{0}\" is not a supported platform.\n".format(platform))
		
# If using Dome9, check API username/key are set - or die.
# TODO validate they work
if dome9 and (domeuser == "" or domeapi == ""):
        sys.exit("\n[!] Configured to use Dome9 but Dome9 username or API key are not set.\n")

# Check port number is valid and can be bound - or die.
if port >= 1 and port <= 65535:
	try:
		s_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		s_socket.bind(("0.0.0.0", port))
	except socket.error as e:
		sys.exit("[!] Unable to bind to port with error: {0} -- {1} ".format(e[0], e[1]))
else:
	print("[!] Please specify a valid port range (1-65535) in the configuration.")
	sys.exit(2)

# Initiate logger
logger = logging.getLogger('hp')
formatter = logging.Formatter("%(message)s - %(asctime)s","%c")
shdlr = logging.StreamHandler()
logger.addHandler(shdlr)
shdlr.setFormatter(formatter)
if logfile != "": # If a logfile name is set, add it to the logger
	try:
		fhdlr = logging.FileHandler(logfile)
		fhdlr.setFormatter(formatter)
		logger.addHandler(fhdlr)
	except IOError as e:
		sys.exit("[!] Unable to create/append logfile: {0} -- {1} ".format(e[0], e[1]))
logger.setLevel(logging.INFO)
logger.propagate = True

# Start listening
s_socket.listen(5)
host_ip = s_socket.getsockname()[0]
logger.info("[*] Starting Honeyport listener on port {0}. Waiting for the bees...".format(port))

while True:
	c, addr = s_socket.accept() # Accept connection
	client_ip = str(addr[0]) # Get client IP
	if client_ip in (whitelist, "127.0.0.1"):
		logger.info("[!] Hit from whitelisted IP: {0}".format(client_ip))
		c.shutdown(socket.SHUT_RDWR)
		c.close()
	else:
		# Send response to client
		if response_script == "":
			if sys.version_info < (3,0):
				c.sendall(response)
			else:
				c.sendall(bytes(response, 'UTF-8'))
		else:
			res = check_output(["python", response_script, client_ip])
			if sys.version_info < (3,0):
				c.sendall(res)
			else:
				c.sendall(bytes(res, 'UTF-8'))
		
		# Close the client connection, don't need it any more.
		c.shutdown(socket.SHUT_RDWR)
		c.close()

		# If Dome9 is enabled, use it.
		if dome9:
			payload = {'IP': client_ip, 'Comment':'Honeyport ' + str(port) + ' - ' + datetime.datetime.now().strftime("%c")} # Build request payload
			if dome9ttl > 0:
				payload['TTL'] = dome9ttl # If a TTL is set in config, add it to the request payload
			else:
				dome9ttl = "Permanent" # For logging
			
			# Send blacklist request to Dome9	
			resp = requests.post('https://api.dome9.com/v1/blacklist/Items/', auth=(domeuser,domeapi), params=payload)
			
			# Check it was successful
			if resp.status_code == 200:
				logger.info("[+] Blacklisting: {0} with Dome9 (TTL: {1})".format(client_ip, dome9ttl))
			
			elif resp.status_code == 403:	
				logger.error("[!] Failed to blacklist {0} with Dome9. HTTP response code {1}, check the Dome9 username and API key in the config.".format(client_ip, resp.status_code))
			else:
				logger.error("[!] Failed to blacklist {0} with Dome9. HTTP response code {1}.".format(client_ip, resp.status_code))
		
		else: # Determine local system (OSX, Linux, Windows) and use local firewall
			if platform == "Linux": # use Linux IPtables
				try:
					result = check_output(["/sbin/iptables", "-A", "INPUT", "-s", "{0}".format(client_ip), "-j", "DROP"])
					logger.info("[+] Blacklisting: {0} with IPTABLES (TTL: {1})".format(client_ip, "Permanent"))
				except (OSError,CalledProcessError) as e:
					logger.error("[!] Failed to blacklist {0} with IPTABLES ({1}), is iptables on the PATH?".format(client_ip, e))
					
			elif platform == "Darwin": # use OSX IPFW
				try:
					result = check_output(["ipfw", "-q add deny src-ip {0}".format(client_ip)])
					logger.info("[+] Blacklisting: {0} with IPFW (TTL: {1})".format(client_ip, "Permanent"))
				except (OSError,CalledProcessError) as e:
					logger.error("[!] Failed to blacklist {0} with IPFW ({1})".format(client_ip, e))
					
			elif platform == "Windows": # use Windows Firewall
				try:
					result = check_output(["netsh", "advfirewall", "firewall", "add", "rule", "name=Honeyport Blacklist", "dir=in", "remoteip={}".format(client_ip), "protocol=any", "action=block"], shell=True)
					logger.info("[+] Blacklisting: {0} with Windows Firewall (TTL: {1})".format(client_ip, "Permanent"))
				except (OSError,CalledProcessError) as e:
					logger.error("[!] Failed to blacklist {0} with Windows Firewall ({1})".format(client_ip, e.output))
			else:
				logger.error("[!] {0} is not a supported platform".format(platform))
# END

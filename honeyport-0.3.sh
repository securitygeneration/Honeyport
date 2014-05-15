#!/bin/bash
# honeyport-0.3.sh
# Linux Bash Ncat Honeyport with IPTables and Dome9 support
# By Sebastien Jeanquier (@securitygen)
# Security Generation - http://www.securitygeneration.com
#
# ChangeLog -
# 0.1: Initial release with whitelisting (2013-08-21)
# 0.2: Added Dome9 IP Blacklist TTL option (2013-11-27)
# 0.3: Added logfile location config (2014-04-09)
#
# TODO: Whitelist file, Blacklist timeout for IPtables
# ----CONFIG START----------------------------------------------
# Configuration
# Set your port number
PORT=31337;
# Blacklist using IPTABLES (requires root) or DOME9
METHOD='DOME9';
# Your Dome9 username (eg. user@email.com)
DOMEUSER='';
# Your Dome9 API key (https://secure.dome9.com/settings under API Key)
DOMEAPI='';
# Optional parameter to allow Dome9 Blacklist items to auto-expire after a certain amount of time (in seconds). Leave blank for permanent blacklisting.
DOME9TTL=86400; # 21600 seconds = 6 hours, 86400 = 24h
# Whitelisted IPs eg: ( "1.1.1.1" "123.2.3.4" );
WHITELIST=( "1.1.1.1" );
# Logfile location
LOGFILE="honeyport.log"
# ---CONFIG END-------------------------------------------------

# Ensure a valid METHOD is set
if [ "${METHOD}" != "IPTABLES" ] && [ "${METHOD}" != "DOME9" ]; then
        echo "[-] Invalid METHOD. Enter IPTABLES or DOME9.";
# Ensure we are root if IPtables is chosen
elif [ "${METHOD}" == "IPTABLES" ] && [[ $EUID -ne 0 ]]; then
        echo "[-] Using method IPtables requires root."
else
        # Check PORT is not in use
        RUNNING=`/usr/sbin/lsof -i :${PORT}`;
        if [ -n "$RUNNING" ]; then
                echo "Port $PORT is already in use. Aborting.";
                #echo $RUNNING; # Optional for debugging
                exit;
        else
                echo "[*] Starting Honeyport listener on port $PORT. Waiting for the bees... - `date`" | tee -a $LOGFILE;
                while [ -z "$RUNNING" ]
                        do
                                # Run Ncat listener on $PORT. Run response.sh when a client connects. Grep client's IP.
								# Note: to listen on a specific interface, insert its IP after the -l flag.
                                IP=`/usr/local/bin/ncat -v -l -p ${PORT} -e ./response.sh 2>&1 1> /dev/null | grep from | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:' | awk {'print $4'} | cut -d: -f1`;

                                # Check IP isn't whitelisted
                                WHITELISTED=false;
                                for i in "${WHITELIST[@]}"
                                do
                                        if [ "${IP}" == $i ]; then
                                                echo "[!] Hit from whitelisted IP: ${i} - `date`" | tee -a $LOGFILE;
                                                WHITELISTED=true;
                                        fi
                                done

                                # If IP is not blank or localhost or whitelisted, blacklist the IP using iptables or Dome9 and log.
                                if [ "${IP}" != "" ] && [ "${IP}" != "127.0.0.1" ] && [ "${WHITELISTED}" != true ]; then
                                        if [ "${METHOD}" == "IPTABLES" ]; then
                                                /sbin/iptables -A INPUT -p all -s ${IP} -j DROP;
                                                echo "[+] Blacklisting: ${IP} with IPtables - `date`" | tee -a $LOGFILE;
                                        elif [ "${METHOD}" == "DOME9" ]; then
                                                # Add TTL value if needed
                                                if [ -n "$DOME9TTL" ]; then
                                                        TTL="&TTL=$DOME9TTL";
                                                else
                                                        TTL="";
                                                fi;
                                                # Make Dome9 API request
                                                /usr/bin/curl -k -v -H "Accept: application/json" -u ${DOMEUSER}:${DOMEAPI} -X "POST" -d "IP=$IP&Comment=Honeyport $PORT - `date`$TTL" https://api.dome9.com/v1/blacklist/Items/ > /dev/null 2>&1;
                                                echo "[+] Blacklisting: ${IP} with Dome9 (TTL: ${DOME9TTL}) - `date`" | tee -a $LOGFILE;
                                        fi;
                                fi;
                                RUNNING=`/usr/sbin/lsof -i :${PORT}`;
                        done;
        fi;
fi;

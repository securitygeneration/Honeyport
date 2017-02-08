#!/bin/bash
# honeystats.sh
# Print out some stats and connection chart from local honeyport.log (default) or supplied filename.
# By Sebastien Jeanquier (@securitygen)
#
# Changelog -
# 0.1: Initial release. Currently only supports/tested with logs created by honeyport.sh script.
#
# Acknowledgements: Bar chart code 
# https://blog.sleeplessbeastie.eu/2014/11/25/how-to-create-simple-bar-charts-in-terminal-using-awk
#
# TODO: Test with logs created by honeyport.py
# --------------------------------------------------------- 

function usage {
	echo "Description: Output statistics on logfile created by honeyport.sh."
	echo "Usage: $0 {logfile}"
	echo " 	Logfile parameter is optional."
	echo "	Script will default to local honeyport.log file."
}

if [ "$1" == "-h" ]; then
	usage "$0";
	exit
fi

# Use supplied filename or default to local honeyport.log
if [ -z "$1" ]; then
	logfile="honeyport.log"
else
	if [ -e "$1" ]; then
		logfile="$1"
	else
		echo -e "Failed to open input file $1 for reading\nQUITTING!"
		exit 1
	fi
fi

# Output log statistics
echo "--- Honeyport Statistics ---"
echo "[+] General info:"
echo -ne "\tFirst connection:" & grep "Blacklisting" "$logfile" | head -n1 | cut -d- -f2 
echo -ne "\tLatest connection:" & grep "Blacklisting" "$logfile" | tail -n1 | cut -d- -f2 
echo -ne "\tTotal number of connections: " & grep "Blacklisting" $logfile | wc -l
echo ""

# Print top 10 IPs
echo "[+] Top 10 connecting IPs and number of connections:"
awk {'print $3'} "$logfile" | grep -v "Honeyport" | sort | uniq -c | sort -r | head -n 10
echo ""

# Print number of connections per day w/ chart
echo "[+] Number of connections per day:"
dates=$(grep "Blacklisting:" "$logfile" | cut -d- -f2 | awk {'print $2" "$3" "$6'} | uniq -c)

# Character used to print bar chart
barchr="*"

# Current min, max values [from 'ps' output]
vmin=1
vmax=$(echo "$dates" | awk 'BEGIN {max=0} {if($1>max) max=$1} END {print max}')

# Range of the bar graph
dmin=1
dmax=60

# Color steps
cstep1="\033[32m"
cstep2="\033[33m"
cstep3="\033[31m"
cstepc="\033[0m"

# Generate output
echo "$dates" | awk --assign dmin="$dmin" --assign dmax="$dmax" \
                             --assign vmin="$vmin" --assign vmax="$vmax" \
                             --assign cstep1="$cstep1" --assign cstep2="$cstep2" --assign cstep3="$cstep3" --assign cstepc="$cstepc"\
                             --assign barchr="$barchr" \
                             'BEGIN {printf("%6s %12s %2s%60s\n","Date","# Conn","|<", "bar chart >|")}
                              {
                                x=int(dmin+($1-vmin)*(dmax-dmin)/(vmax-vmin));
				printf("%3s %2s %4s %7s ",$2,$3,$4,$1);
                                for(i=1;i<=x;i++)
                                {
                                    if (i >= 1 && i <= int(dmax/3))
                                      {printf(cstep1 barchr cstepc);}
				    else if (i > int(dmax/3) && i <= int(2*dmax/3))
                                      {printf(cstep2 barchr cstepc);}
                                    else
                                      {printf(cstep3 barchr cstepc);}
                                };
                                print ""
                              }'
#end

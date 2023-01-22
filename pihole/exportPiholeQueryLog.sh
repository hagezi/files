#!/bin/bash

# Script to export parts of the PiHole query log to a text file.
#
# The following is exported:
# blocked.gravity.txt - domains blocked by gravity
# blocked.blacklist.txt - domains blocked by blacklist entries
# blocked.upstream.txt - domains blocked by the used upstream DNS.
#
# Note:
# The files are not overwritten, the exported domains are appended to
# the existing files.
# A unique sort ensures that the lists do not contain duplicate entries.
#
# The script requires the following package installed:
# sudo apt install sqlite3
#
# Usage:
# ./exportPiholeQueryLog.sh OUPTPUTDIR (e.g. /git/dns-data-collection/userdata) DBPATH (optional! e.g. /etc/pihole/pihole-FTL.db)

if [ "$(id -u)" != "0" ]; then
  echo "The script must be executed with root rights!"
  exit 1
fi

output=$1
if [ -z "$1" ]; then
  echo "No output directory was specified!"
  exit 1
fi

piholedb=$2
if [ -z "$2" ]; then
  piholedb=/etc/pihole/pihole-FTL.db
  echo "No pihole-FTL.db file was specified! Using default of $piholedb"
fi

blockedgrav=$output/blocked.gravity.txt
blockedblack=$output/blocked.blacklist.txt
blockedupst=$output/blocked.upstream.txt

sqlite3 "$piholedb" "SELECT DISTINCT domain FROM queries WHERE type IN (1,2) AND status IN(1,9) ORDER BY domain;" >>"$blockedgrav"
sqlite3 "$piholedb" "SELECT DISTINCT additional_info FROM queries WHERE type IN (1,2) AND status IN(9,10,11) ORDER BY additional_info;" >>"$blockedgrav"
sort -u "$blockedgrav" >"$blockedgrav".tmp
mv "$blockedgrav".tmp "$blockedgrav"

sqlite3 "$piholedb" "SELECT DISTINCT domain FROM queries WHERE type IN (1,2) AND status IN(4,5,10,11) ORDER BY domain;" >>"$blockedblack"
sqlite3 "$piholedb" "SELECT DISTINCT additional_info FROM queries WHERE type IN (1,2) AND status IN(10,11) ORDER BY additional_info;" >>"$blockedblack"
sort -u "$blockedblack" >"$blockedblack".tmp
mv "$blockedblack".tmp "$blockedblack"

sqlite3 "$piholedb" "SELECT DISTINCT domain FROM queries WHERE type IN (1,2) AND status IN(6,7,8) ORDER BY domain;" >>"$blockedupst"
sort -u "$blockedupst" >"$blockedupst".tmp
mv "$blockedupst".tmp "$blockedupst"

#!/bin/bash

# ---
# Script to gather some informations about the blockrate per client/IP from PiHole FTL-Database.
#
# The script requires the following package installed:
# sudo apt install sqlite3
#
# Usage:
# ./piholeBlockratePerClient.sh DBPATH (optional! e.g. /etc/pihole/pihole-FTL.db)
# ---

if [ -z "$1" ]; then
  echo "No pi-hole FTL database specified! e.g. /etc/pihole/pihole-FTL.db"
  exit 1
fi
piholedb=$1

# second parameter: for which column do we want our result be sorted?
if [ -n "$2" ]; then
  case "$2" in
    clientname)
      orderby="client_by_id.name" ;;
    ip)
      orderby="client_by_id.$2" ;;
    blocked)
      orderby="$2" ;;
    allowed)
      orderby="$2" ;;
    rate)
      orderby="$2" ;;
    *)
      echo "Invalid column '$2' for ORDER BY specified!"
      echo "Valid colums are: ip, clientname, blocked, allowed, rate."
      exit 1
  esac
  echo "Column '$2' for ORDER BY specified."
else
  echo "No column for ORDER BY specified (e.g. IP, CLIENTNAME, BLOCKED, ALLOWED, RATE)"
  echo "Using 'clientname' as default."
  orderby="client_by_id.name"
fi

sql="SELECT \
 client AS ip, client_by_id.name AS clientname,
 SUM(count) FILTER (WHERE flag = 'B') AS blocked,
 SUM(count) FILTER (WHERE flag = 'A') AS allowed,
 ROUND(
 (1.0 * SUM(count) FILTER (WHERE flag = 'B') * 100)
 /
 (1.0 * SUM(count) FILTER (WHERE flag = 'A') + 1.0 * SUM(count) FILTER (WHERE flag = 'B'))
 ,2) AS rate
FROM
(
 SELECT * FROM
 (
  SELECT client, count(id) as count, 'B' as flag FROM queries WHERE type IN (1,2) AND status IN(1,4,5,6,7,8,9,10,11) GROUP BY client \
  UNION ALL
  SELECT client, count(id) as count, 'A' as flag FROM queries WHERE type IN (1,2) AND status IN(2,3,14) GROUP BY client \
 )
)
JOIN client_by_id on client = client_by_id.ip
GROUP BY client
ORDER BY $orderby;"
#ORDER BY client_by_id.name

echo ""
sqlite3 "$piholedb" "$sql" -header -column
echo ""

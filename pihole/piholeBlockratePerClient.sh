#!/bin/bash

piholedb=$1
if [ -z "$1" ]; then
    echo "No pi-hole FTL database specified! e.g. /etc/pihole/pihole-FTL.db"
    exit 1
fi

sql="SELECT \
 client AS ip, client_by_id.name AS clientname, 
 SUM(count) FILTER (WHERE flag = 'B') AS blocked, 
 SUM(count) FILTER (WHERE flag = 'A') AS allowed, 
 ((SUM(count) FILTER (WHERE flag = 'B')*100)/SUM(count) FILTER (WHERE flag = 'A')) AS rate 
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
ORDER BY client_by_id.name;"

echo ""
sqlite3 "$piholedb" "$sql" -header -column
echo ""

#!/usr/bin/env bash
#
# pihole-blockrate - block rate per client from the Pi-hole FTL database
#
# Shows for every client the number of queries, how many were blocked or
# passed (not blocked), and the block rate in percent, plus a total over all
# clients.
# The database is opened read-only, so the script is safe to run on a live system.
#
# Author:       HaGeZi
# License:      GNU General Public License v3.0 or later (GPL-3.0-or-later)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Requirements: Pi-hole v6 (pihole-FTL with built-in sqlite3), bash 4+, GNU date
#
# Installation:
#   sudo install -m 755 pihole-blockrate.sh /usr/local/bin/pihole-blockrate
#
# Usage:
#   sudo pihole-blockrate [options]      (run with -h for all options and examples)

VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DB="/etc/pihole/pihole-FTL.db"
DAYS=0
FROM=""
TO=""
SORT="name"
REVERSE=0
MIN=100
LIMIT=0
NOTOTAL=0
QTYPES=()
EXCLUDES=()
CLIENTS=()

usage() {
  local me
  me=$(basename "$0")
  cat <<EOF
$me $VERSION - block rate per client from the Pi-hole FTL database

Usage: $me [options]

Without options: all data in the database, A and AAAA queries, clients with
at least $MIN queries, sorted by client name. The database is opened read-only.

Time range (default: all data in the database):
  -d, --days N            Number of days, counted from today 00:00
                          (1 = today, 2 = today + yesterday, ...)
      --from TIME         Start of the time range. Overrides -d.
      --to TIME           End of the time range (requires --from).
                          Default: now
                          TIME is anything GNU date understands, e.g.
                          "03:00" (today), "2026-10-28 03:00", "yesterday 17:50"

Filters:
  -q, --qtype TYPE        Query type to include, e.g. A, AAAA, HTTPS, or ALL.
                          Repeatable. Default: A and AAAA
  -c, --client CLIENT     Only this client, given as IP address or client name
                          (case-insensitive). Repeatable.
  -x, --exclude DOMAIN    Ignore queries for a domain incl. all its subdomains.
                          Repeatable. A leading dot is ignored.
  -m, --min N             Only clients with at least N queries. Default: $MIN

Output:
  -s, --sort COLUMN       Sort by name, ip, total, blocked, passed or rate.
                          name and ip sort ascending, the number columns
                          descending (largest value first). Default: $SORT
  -r, --reverse           Reverse the sort order
  -l, --limit N           Show only the first N clients (0 = all). Default: $LIMIT
      --no-total          Do not show the total over all clients

Other:
  -f, --db FILE           Path to the FTL database.
                          Default: $DB
  -h, --help              Show this help and exit
  -V, --version           Show the version and exit

Output columns:
  IP, Name, Total, Blocked, Passed, Rate (blocked in percent of total)
  Name comes from the FTL client table, or the network table if empty.

Counted as blocked:  gravity, denylist (exact/regex), deep CNAME inspection,
                     upstream blocking, special domains, database busy
Counted as passed:   forwarded, cache, stale cache, retried, already forwarded
                     (Pi-hole calls these "allowed"; they are not necessarily
                     on the allowlist)
Queries with unknown status are not counted.

Query types:
  A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS ALL

Examples:
  # All data, sorted by name
  $me
  # Highest block rate first
  $me -s rate
  # Today, lowest block rate first
  $me -d 1 -s rate -r
  # Top 10 clients by number of blocked queries in the last 7 days
  $me -d 7 -s blocked -l 10
  # All query types, all clients, sorted by IP address
  $me -q ALL -m 0 -s ip
  # Two clients, without a noisy domain
  $me -c laptop -c phone -x example.com
  # A time window of yesterday
  $me --from "yesterday 18:00" --to "yesterday 23:59"
  # Use a copy of the database
  sudo cp $DB /tmp/ftl-copy.db
  $me -f /tmp/ftl-copy.db

Notes:
  - Needs read access to the database, so usually run with sudo.
  - The total row covers all clients that match the filters, including
    clients hidden by --min or --limit.

Exit status:
  0  success (also if there are no results)
  1  invalid option, unreadable database or database error

Author: HaGeZi. License: GPL-3.0-or-later.
EOF
}

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--days)    DAYS="${2:?Number of days missing}"; shift 2 ;;
    --from)       FROM="${2:?Start time missing}"; shift 2 ;;
    --to)         TO="${2:?End time missing}"; shift 2 ;;
    -q|--qtype)   QTYPES+=("${2:?Query type missing}"); shift 2 ;;
    -c|--client)  CLIENTS+=("${2:?Client missing}"); shift 2 ;;
    -x|--exclude) EXCLUDES+=("${2:?Domain missing}"); shift 2 ;;
    -m|--min)     MIN="${2:?Number of queries missing}"; shift 2 ;;
    -s|--sort)    SORT="${2:?Column missing}"; shift 2 ;;
    -r|--reverse) REVERSE=1; shift ;;
    -l|--limit)   LIMIT="${2:?Number of clients missing}"; shift 2 ;;
    --no-total)   NOTOTAL=1; shift ;;
    -f|--db)      DB="${2:?Database path missing}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    -V|--version) echo "$(basename "$0") $VERSION"
                  echo "Copyright (C) HaGeZi. License GPLv3+: GNU GPL version 3 or later"
                  echo "<https://www.gnu.org/licenses/gpl-3.0.html>"
                  exit 0 ;;
    *)            die "unknown option: $1 (help: -h)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate input and environment
# ---------------------------------------------------------------------------
[[ "$DAYS" =~ ^[0-9]+$ ]]        || die "invalid number of days: $DAYS"
[[ "$MIN" =~ ^[0-9]+$ ]]         || die "invalid minimum: $MIN"
[[ "$LIMIT" =~ ^[0-9]+$ ]]       || die "invalid limit: $LIMIT"
command -v pihole-FTL >/dev/null  || die "pihole-FTL not found (Pi-hole v6 required)"
[ -r "$DB" ]                     || die "database not readable: $DB (try sudo)"

# Sort column. Text columns (name, ip) sort ascending, number columns
# (total, blocked, passed, rate) descending, i.e. the largest value first.
# -r reverses the primary key; the client name stays the ascending tiebreaker.
# IPv4 addresses are sorted numerically, IPv6 after IPv4.
case "${SORT,,}" in
  name)    KEYS=("lower(r.Name)" "r.ipkey");    DIR=ASC ;;
  ip)      KEYS=("r.ipv6" "r.ipkey" "r.IP");    DIR=ASC ;;
  total)   KEYS=("r.Total");                     DIR=DESC ;;
  blocked) KEYS=("r.Blocked");                   DIR=DESC ;;
  passed)  KEYS=("r.Passed");                    DIR=DESC ;;
  rate)    KEYS=("r.Rate" "r.Blocked");          DIR=DESC ;;
  *)       die "invalid sort column: $SORT (name, ip, total, blocked, passed, rate)" ;;
esac
if [ "$REVERSE" -eq 1 ]; then
  [ "$DIR" = ASC ] && DIR=DESC || DIR=ASC
fi
ORDER=""
for k in "${KEYS[@]}"; do ORDER+="${ORDER:+, }$k $DIR"; done
ORDER+=", lower(r.Name) ASC"

# Query types as stored by FTL v6 in queries.type
declare -A QTYPE_ID=(
  [A]=1 [AAAA]=2 [ANY]=3 [SRV]=4 [SOA]=5 [PTR]=6 [TXT]=7 [NAPTR]=8
  [MX]=9 [DS]=10 [RRSIG]=11 [DNSKEY]=12 [NS]=13 [OTHER]=14 [SVCB]=15 [HTTPS]=16
)
[ ${#QTYPES[@]} -eq 0 ] && QTYPES=(A AAAA)
QTYPE_FILTER=""
ids=""
for t in "${QTYPES[@]}"; do
  t="${t^^}"
  if [ "$t" = "ALL" ]; then ids=""; break; fi
  [ -n "${QTYPE_ID[$t]:-}" ] || die "unknown query type: $t (help: -h)"
  ids+="${ids:+,}${QTYPE_ID[$t]}"
done
[ -n "$ids" ] && QTYPE_FILTER="AND q.type IN ($ids)"

# Escape single quotes for use inside SQL string literals
sql_quote() { printf '%s' "${1//\'/\'\'}"; }

# Escape LIKE wildcards (% _) and the escape character itself
like_quote() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//%/\\%}"; s="${s//_/\\_}"
  sql_quote "$s"
}

# ---------------------------------------------------------------------------
# Time range
# ---------------------------------------------------------------------------
TIME_FILTER=""
RANGE="all data"
if [ -n "$FROM" ]; then
  FROM_TS=$(date -d "$FROM" +%s 2>/dev/null) || die "invalid start time: $FROM"
  if [ -n "$TO" ]; then
    TO_TS=$(date -d "$TO" +%s 2>/dev/null) || die "invalid end time: $TO"
  else
    TO_TS=$(date +%s)
  fi
  [ "$FROM_TS" -lt "$TO_TS" ] || die "start time must be before end time"
  TIME_FILTER="AND q.timestamp >= $FROM_TS AND q.timestamp < $TO_TS"
  RANGE="$(date -d "@$FROM_TS" '+%Y-%m-%d %H:%M:%S') to $(date -d "@$TO_TS" '+%Y-%m-%d %H:%M:%S')"
elif [ -n "$TO" ]; then
  die "--to requires --from"
elif [ "$DAYS" -gt 0 ]; then
  # "<date> N days ago" form, because GNU date would read "-N days" as a timezone
  SINCE=$(date -d "$(date +%F) $((DAYS - 1)) days ago" +%s)
  TIME_FILTER="AND q.timestamp >= $SINCE"
  RANGE="last $DAYS day(s)"
fi

# ---------------------------------------------------------------------------
# Client and domain filters
# ---------------------------------------------------------------------------
CLIENT_FILTER=""
if [ ${#CLIENTS[@]} -gt 0 ]; then
  ips=""; names=""
  for c in "${CLIENTS[@]}"; do
    ips+="${ips:+,}'$(sql_quote "$c")'"
    names+="${names:+,}lower('$(sql_quote "$c")')"
  done
  CLIENT_FILTER="AND (q.client IN ($ips)
                      OR q.client IN (SELECT na.ip FROM network_addresses na
                                      WHERE lower(na.name) IN ($names))
                      OR q.client IN (SELECT cb.ip FROM client_by_id cb
                                      WHERE lower(cb.name) IN ($names)))"
fi

EXCLUDE=""
for x in "${EXCLUDES[@]}"; do
  x="${x#.}"
  EXCLUDE+=" AND NOT (q.domain = '$(sql_quote "$x")'
                      OR q.domain LIKE '%.$(like_quote "$x")' ESCAPE '\\')"
done

# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------
# Status as stored by FTL v6 in queries.status
BLOCKED="1,4,5,6,7,8,9,10,11,15,16,18"
PASSED="2,3,12,13,14,17"

# ev:   matching queries with blocked flag (1 = blocked, 0 = passed)
# per:  counts per client
# rows: per client with name and sort keys
EV="SELECT q.client AS client,
           CASE WHEN q.status IN ($BLOCKED) THEN 1 ELSE 0 END AS b
    FROM queries q
    WHERE q.status IN ($BLOCKED,$PASSED)
      $QTYPE_FILTER
      $TIME_FILTER
      $CLIENT_FILTER
      $EXCLUDE"

LIMIT_SQL=""
[ "$LIMIT" -gt 0 ] && LIMIT_SQL="LIMIT $LIMIT"

SQL_CLIENTS="WITH ev AS ($EV),
     per AS (
       SELECT client, count(*) AS total, sum(b) AS blocked
       FROM ev GROUP BY client HAVING count(*) >= $MIN
     ),
     rows AS (
       SELECT p.client AS IP,
              COALESCE(NULLIF((SELECT cb.name FROM client_by_id cb WHERE cb.ip = p.client
                               AND cb.name IS NOT NULL AND cb.name <> '' LIMIT 1), ''),
                       (SELECT na.name FROM network_addresses na WHERE na.ip = p.client
                        AND na.name IS NOT NULL AND na.name <> ''
                        ORDER BY na.lastSeen DESC LIMIT 1),
                       '') AS Name,
              p.total AS Total,
              p.blocked AS Blocked,
              p.total - p.blocked AS Passed,
              round(100.0 * p.blocked / p.total, 2) AS Rate,
              (p.client LIKE '%:%') AS ipv6,
              -- numeric key for IPv4 (a.b.c.d), 0 for IPv6
              CASE WHEN p.client LIKE '%:%' THEN 0 ELSE
                CAST(p.client AS INTEGER) * 16777216
                + CAST(substr(p.client, instr(p.client, '.') + 1) AS INTEGER) * 65536
                + CAST(substr(substr(p.client, instr(p.client, '.') + 1),
                              instr(substr(p.client, instr(p.client, '.') + 1), '.') + 1) AS INTEGER) * 256
                + CAST(replace(p.client, rtrim(p.client, '0123456789'), '') AS INTEGER)
              END AS ipkey
       FROM per p
     )
     SELECT r.IP, r.Name, r.Total, r.Blocked, r.Passed, printf('%6.2f', r.Rate) AS Rate
     FROM rows r
     ORDER BY $ORDER
     $LIMIT_SQL;"

SQL_TOTAL="WITH ev AS ($EV)
     SELECT count(DISTINCT client) AS Clients,
            count(*) AS Total,
            sum(b) AS Blocked,
            count(*) - sum(b) AS Passed,
            printf('%6.2f', 100.0 * sum(b) / count(*)) AS Rate
     FROM ev
     HAVING count(*) > 0;"

echo "Block rate per client ($RANGE, query types: ${QTYPES[*]^^}, min. $MIN queries)"
out=$(pihole-FTL sqlite3 -readonly -box "$DB" "$SQL_CLIENTS") || exit 1
if [ -z "$out" ]; then
  echo "No clients match the filters."
  exit 0
fi
echo "$out"

if [ "$NOTOTAL" -eq 0 ]; then
  echo
  echo "Total"
  pihole-FTL sqlite3 -readonly -box "$DB" "$SQL_TOTAL" || exit 1
fi


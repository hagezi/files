#!/usr/bin/env bash
#
# pihole-replycheck - analyze DNS replies from the Pi-hole FTL database
#
# Shows queries with a given reply type (e.g. SERVFAIL) or queries that got
# no reply at all, either as a summary per day and domain or as single events.
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
#   sudo install -m 755 pihole-replycheck.sh /usr/local/bin/pihole-replycheck
#
# Usage:
#   sudo pihole-replycheck [options]      (run with -h for all options and examples)

VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DB="/etc/pihole/pihole-FTL.db"
DAYS=1
WINDOW=10
VERBOSE=0
NAMES=0
MAX_CLIENTS=0
FROM=""
TO=""
TYPES=()
EXCLUDES=()
CLIENTS=()

usage() {
  local me
  me=$(basename "$0")
  cat <<EOF
$me $VERSION - analyze DNS replies from the Pi-hole FTL database

Usage: $me [options]

Without options: today, types SERVFAIL and NOREPLY, summary per day and domain.
The database is opened read-only.

Time range (use -d or --from/--to):
  -d, --days N            Number of days, counted from today 00:00
                          (1 = today, 2 = today + yesterday, ...). Default: $DAYS
      --from TIME         Start of the time range. Overrides -d.
      --to TIME           End of the time range (requires --from).
                          Default: now
                          TIME is anything GNU date understands, e.g.
                          "03:00" (today), "2026-10-28 03:00", "yesterday 17:50"

Filters:
  -t, --type TYPE         Reply type to show, see "Types" below. Repeatable.
                          Default: SERVFAIL and NOREPLY
  -c, --client CLIENT     Only queries from this client, given as IP address or
                          client name (case-insensitive). Repeatable.
  -x, --exclude DOMAIN    Exclude a domain incl. all its subdomains. Repeatable.
                          A leading dot is ignored (.example.com = example.com).

Output:
  -n, --names             Show client names instead of IP addresses
  -v, --verbose           List every single event instead of a summary
  -m, --max-clients N     Summary only: show at most N clients per row,
                          the rest as "… (+X)". 0 = show all. Default: $MAX_CLIENTS

Other:
  -w, --window SEC        Duplicate window for NOREPLY in seconds. Default: $WINDOW
  -f, --db FILE           Path to the FTL database.
                          Default: $DB
  -h, --help              Show this help and exit
  -V, --version           Show the version and exit

Types:
  NOREPLY   No reply. Queries that dnsmasq merged into another in-flight query
            (same domain and type, any client) which was answered within the
            duplicate window are filtered out, so only real failures remain.
  UNKNOWN   No reply, unfiltered. Includes the merged duplicates that the
            Pi-hole query log shows as "No reply received".
  SERVFAIL  Server failure (e.g. DNSSEC validation error, broken delegation,
            upstream not reachable)
  REFUSED   Query refused
  NXDOMAIN  Domain does not exist
  NODATA    Domain exists, but has no record of the requested type
  NOTIMP    Query type not implemented
  NONE      Empty reply

Output columns:
  Summary:  Day, Count, First, Last, Domain, Clients, Upstreams
  Verbose:  Time, Domain, Client, Upstream
  Upstream is the server FTL stored for the query (e.g. 127.0.0.1#5335).
  It is empty if Pi-hole answered the query itself. With the dnsmasq option
  all-servers, FTL stores only one of the queried upstreams.

Examples:
  # Today, SERVFAIL + NOREPLY
  $me
  # Today and yesterday, with client names
  $me -d 2 -n
  # SERVFAIL of the last 7 days, at most 3 clients per row
  $me -d 7 -t SERVFAIL -m 3
  # Two other reply types
  $me -t REFUSED -t NXDOMAIN
  # Every single event of today
  $me -v
  # One client by IP address, two clients by name
  $me -c 192.168.1.10
  $me -c laptop -c phone
  # A time window of today, single events
  $me --from 03:00 --to 03:45 -v
  # A time window of yesterday
  $me --from "yesterday 17:50" --to "yesterday 18:00"
  # Hide DNSSEC test domains and another domain
  $me -x dnscheck.tools -x example.com
  # NOREPLY with a wider duplicate window
  $me -t NOREPLY -w 30
  # Analyze a copy of the database
  sudo cp $DB /tmp/ftl-copy.db
  $me -f /tmp/ftl-copy.db -d 30

Notes:
  - Needs read access to the database, so usually run with sudo.
  - FTL writes to the database only once per minute. Queries of the last
    2 minutes are ignored because their reply may not be stored yet.
  - Client names come from the FTL network table (network_addresses).
  - NOREPLY over many days (e.g. -d 30) can take a while on a Raspberry Pi.

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
    -d|--days)        DAYS="${2:?Number of days missing}"; shift 2 ;;
    --from)           FROM="${2:?Start time missing}"; shift 2 ;;
    --to)             TO="${2:?End time missing}"; shift 2 ;;
    -t|--type)        TYPES+=("${2:?Type missing}"); shift 2 ;;
    -c|--client)      CLIENTS+=("${2:?Client missing}"); shift 2 ;;
    -x|--exclude)     EXCLUDES+=("${2:?Domain missing}"); shift 2 ;;
    -n|--names)       NAMES=1; shift ;;
    -v|--verbose)     VERBOSE=1; shift ;;
    -m|--max-clients) MAX_CLIENTS="${2:?Number of clients missing}"; shift 2 ;;
    -w|--window)      WINDOW="${2:?Seconds missing}"; shift 2 ;;
    -f|--db)          DB="${2:?Database path missing}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    -V|--version)     echo "$(basename "$0") $VERSION"
                      echo "Copyright (C) HaGeZi. License GPLv3+: GNU GPL version 3 or later"
                      echo "<https://www.gnu.org/licenses/gpl-3.0.html>"
                      exit 0 ;;
    *)                die "unknown option: $1 (help: -h)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate input and environment
# ---------------------------------------------------------------------------
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]]   || die "invalid number of days: $DAYS"
[[ "$WINDOW" =~ ^[0-9]+$ ]]      || die "invalid window: $WINDOW"
[[ "$MAX_CLIENTS" =~ ^[0-9]+$ ]] || die "invalid number of clients: $MAX_CLIENTS"
command -v pihole-FTL >/dev/null  || die "pihole-FTL not found (Pi-hole v6 required)"
[ -r "$DB" ]                     || die "database not readable: $DB (try sudo)"

[ ${#TYPES[@]} -eq 0 ] && TYPES=(SERVFAIL NOREPLY)

# Validate all types before running any query
for t in "${TYPES[@]}"; do
  case "${t^^}" in
    NOREPLY|UNKNOWN|NODATA|NXDOMAIN|SERVFAIL|REFUSED|NOTIMP|NONE) ;;
    *) die "unknown type: $t (help: -h)" ;;
  esac
done

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
# Upper limit: now minus 2 minutes (the reply may not be stored yet)
LIMIT_TS=$(( $(date +%s) - 120 ))

if [ -n "$FROM" ]; then
  FROM_TS=$(date -d "$FROM" +%s 2>/dev/null) || die "invalid start time: $FROM"
  if [ -n "$TO" ]; then
    TO_TS=$(date -d "$TO" +%s 2>/dev/null) || die "invalid end time: $TO"
  else
    TO_TS=$LIMIT_TS
  fi
  [ "$TO_TS" -gt "$LIMIT_TS" ] && TO_TS=$LIMIT_TS
  [ "$FROM_TS" -lt "$TO_TS" ] || die "start time must be before end time"
  SINCE=$FROM_TS
  UNTIL=$TO_TS
  RANGE="$(date -d "@$FROM_TS" '+%Y-%m-%d %H:%M:%S') to $(date -d "@$TO_TS" '+%Y-%m-%d %H:%M:%S')"
else
  [ -n "$TO" ] && die "--to requires --from"
  # Today 00:00 local time minus (DAYS-1) days. The "<date> N days ago" form
  # is used because GNU date would read "-N days" after a time as a timezone.
  SINCE=$(date -d "$(date +%F) $((DAYS - 1)) days ago" +%s)
  UNTIL=$LIMIT_TS
  RANGE="last $DAYS day(s)"
fi

# ---------------------------------------------------------------------------
# Building blocks for the SQL queries
# ---------------------------------------------------------------------------
# Client shown as IP address or as name from the network table
if [ "$NAMES" -eq 1 ]; then
  CLIENT="COALESCE((SELECT na.name FROM network_addresses na
                    WHERE na.ip = q.client AND na.name IS NOT NULL AND na.name <> ''
                    ORDER BY na.lastSeen DESC LIMIT 1), q.client)"
else
  CLIENT="q.client"
fi

# Client filter: match by IP address or by name from the network table
CLIENT_FILTER=""
if [ ${#CLIENTS[@]} -gt 0 ]; then
  ips=""; names=""
  for c in "${CLIENTS[@]}"; do
    ips+="${ips:+,}'$(sql_quote "$c")'"
    names+="${names:+,}lower('$(sql_quote "$c")')"
  done
  CLIENT_FILTER="AND (q.client IN ($ips)
                      OR q.client IN (SELECT na.ip FROM network_addresses na
                                      WHERE lower(na.name) IN ($names)))"
fi

# Excluded domains: exact match or any subdomain
EXCLUDE=""
for x in "${EXCLUDES[@]}"; do
  x="${x#.}"
  EXCLUDE+=" AND NOT (q.domain = '$(sql_quote "$x")'
                      OR q.domain LIKE '%.$(like_quote "$x")' ESCAPE '\\')"
done

# Upstream as stored by FTL (NULL if Pi-hole answered the query itself)
UPSTREAM="NULLIF(q.forward, '')"

# ---------------------------------------------------------------------------
# Run one query per reply type
# ---------------------------------------------------------------------------
query() {
  local type="${1^^}" where

  # Numeric reply types as stored by FTL v6 in queries.reply_type
  case "$type" in
    NOREPLY)
      # No reply, but skip queries that dnsmasq merged into another in-flight
      # query with the same domain and type (from any client) that got an
      # answer within +/- WINDOW seconds. A real failure leaves all merged
      # queries unanswered.
      where="q.reply_type = 0
             AND NOT EXISTS (
               SELECT 1 FROM queries q2
               WHERE q2.domain = q.domain
                 AND q2.type = q.type
                 AND q2.reply_type <> 0
                 AND q2.timestamp BETWEEN q.timestamp - $WINDOW AND q.timestamp + $WINDOW)" ;;
    UNKNOWN)  where="q.reply_type = 0" ;;
    NODATA)   where="q.reply_type = 1" ;;
    NXDOMAIN) where="q.reply_type = 2" ;;
    SERVFAIL) where="q.reply_type = 7" ;;
    REFUSED)  where="q.reply_type = 8" ;;
    NOTIMP)   where="q.reply_type = 9" ;;
    NONE)     where="q.reply_type = 12" ;;
  esac

  local base="FROM queries q
              WHERE $where
                AND q.timestamp >= $SINCE
                AND q.timestamp <  $UNTIL
                $CLIENT_FILTER
                $EXCLUDE"

  local sql
  if [ "$VERBOSE" -eq 1 ]; then
    sql="SELECT datetime(q.timestamp,'unixepoch','localtime') AS Time,
                q.domain AS Domain,
                $CLIENT AS Client,
                $UPSTREAM AS Upstream
         $base
         ORDER BY q.timestamp;"
  else
    # ev:  matching events
    # cl:  distinct clients per day and domain, numbered (rn) and counted (n)
    # cla: client list per day and domain, cut after MAX_CLIENTS entries (0 = all)
    sql="WITH ev AS (
           SELECT date(q.timestamp,'unixepoch','localtime') AS day,
                  q.timestamp AS ts,
                  q.domain AS domain,
                  $CLIENT AS client,
                  $UPSTREAM AS upstream
           $base
         ),
         cl AS (
           SELECT day, domain, client,
                  row_number() OVER (PARTITION BY day, domain ORDER BY client) AS rn,
                  count(*)     OVER (PARTITION BY day, domain) AS n
           FROM (SELECT DISTINCT day, domain, client FROM ev)
         ),
         cla AS (
           SELECT day, domain,
                  group_concat(CASE WHEN $MAX_CLIENTS = 0 OR rn <= $MAX_CLIENTS THEN client END, ',')
                    || CASE WHEN $MAX_CLIENTS > 0 AND max(n) > $MAX_CLIENTS
                            THEN ',… (+' || (max(n) - $MAX_CLIENTS) || ')' ELSE '' END AS clients
           FROM (SELECT * FROM cl ORDER BY day, domain, rn)
           GROUP BY day, domain
         )
         SELECT e.day AS Day,
                count(*) AS Count,
                time(min(e.ts),'unixepoch','localtime') AS First,
                time(max(e.ts),'unixepoch','localtime') AS Last,
                e.domain AS Domain,
                c.clients AS Clients,
                group_concat(DISTINCT e.upstream) AS Upstreams
         FROM ev e
         JOIN cla c ON c.day = e.day AND c.domain = e.domain
         GROUP BY e.day, e.domain
         ORDER BY e.day, Count DESC, e.domain;"
  fi

  local out
  out=$(pihole-FTL sqlite3 -readonly -box "$DB" "$sql") || return 1

  if [ -z "$out" ]; then
    echo "$type: no results ($RANGE)."
  else
    echo "$type – $RANGE"
    echo "$out"
  fi
  echo
}

rc=0
for t in "${TYPES[@]}"; do
  query "$t" || rc=1
done
exit $rc


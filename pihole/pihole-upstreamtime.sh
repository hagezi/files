#!/usr/bin/env bash
#
# pihole-upstreamtime - reply times per upstream DNS server from the Pi-hole FTL database
#
# Shows for every upstream server the number of forwarded queries and the
# reply time in milliseconds (average, median, 95th percentile, maximum),
# optionally per day or per hour, plus a total over all upstreams.
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
#   sudo install -m 755 pihole-upstreamtime.sh /usr/local/bin/pihole-upstreamtime
#
# Usage:
#   sudo pihole-upstreamtime [options]      (run with -h for all options and examples)

VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DB="/etc/pihole/pihole-FTL.db"
DAYS=1
HOURS=0
FROM=""
TO=""
GROUP="none"
SORT="avg"
NOTOTAL=0
WITHERR=0
QTYPES=()
EXCLUDES=()
CLIENTS=()
UPSTREAMS=()

usage() {
  local me
  me=$(basename "$0")
  cat <<EOF
$me $VERSION - reply times per upstream from the FTL database

Usage: $me [options]

Without options: today, all query types, one row per upstream, sorted by
average reply time. Only forwarded queries are counted, answers from the
Pi-hole cache are not. The database is opened read-only.

Time range (use only one of -d, -H, --from):
  -d, --days N            Number of days, counted from today 00:00
                          (1 = today, 2 = today + yesterday, ...). Default: $DAYS
  -H, --hours N           The last N full hours, ending at the start of the
                          current hour (e.g. 1 at 10:05 = 09:00 to 10:00)
      --from TIME         Start of the time range.
      --to TIME           End of the time range (requires --from).
                          Default: now
                          TIME is anything GNU date understands, e.g.
                          "03:00" (today), "2026-10-28 03:00", "yesterday 17:50"

Filters:
  -u, --upstream SERVER   Only this upstream, e.g. 127.0.0.1#5335. Repeatable.
  -q, --qtype TYPE        Query type to include, e.g. A, AAAA, HTTPS.
                          Repeatable. Default: all query types
  -c, --client CLIENT     Only queries from this client, given as IP address or
                          client name (case-insensitive). Repeatable.
  -x, --exclude DOMAIN    Ignore queries for a domain incl. all its subdomains.
                          Repeatable. A leading dot is ignored.
  -e, --errors            Also count replies with errors (SERVFAIL, REFUSED,
                          NOTIMP). Default: only answers without error and
                          NXDOMAIN, so timeouts do not distort the times.

Output:
  -g, --group PERIOD      none, day or hour: one row per upstream and period,
                          e.g. to compare times before and after a change.
                          Default: $GROUP
  -s, --sort COLUMN       Sort by upstream, queries, avg, median, p95 or max.
                          Upstream sorts ascending, the others descending,
                          except avg (fastest first). Default: $SORT
      --no-total          Do not show the total over all upstreams

Other:
  -f, --db FILE           Path to the FTL database.
                          Default: $DB
  -h, --help              Show this help and exit
  -V, --version           Show the version and exit

Output columns:
  Period (with -g), Upstream, Queries, Avg, Median, P95, Max (all in ms)
  P95: 95 % of the queries were answered at least this fast.

Query types:
  A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS

Examples:
  # Today, one row per upstream
  $me
  # Last 7 days, one row per upstream and day
  $me -d 7 -g day
  # Last 24 full hours per hour, only one upstream
  $me -H 24 -g hour -u 127.0.0.1#5335
  # Compare two time windows, e.g. before and after a change
  $me --from "yesterday 18:00" --to "yesterday 22:00"
  $me --from "today 18:00" --to "today 22:00"
  # Only A and AAAA queries of one client
  $me -q A -q AAAA -c laptop
  # Use a copy of the database
  sudo cp $DB /tmp/ftl-copy.db
  $me -f /tmp/ftl-copy.db -d 30

Notes:
  - Needs read access to the database, so usually run with sudo.
  - The times are measured by Pi-hole: from forwarding a query to the
    upstream until its reply. If the upstream is a local resolver (e.g.
    Unbound), its own cache hits pull the average down; the median and P95
    are then more meaningful. Times of the servers behind a local resolver
    are only known to that resolver (Unbound: unbound-control dump_infra).
  - FTL writes to the database once per minute, the last minute may be
    missing.

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
DAYS_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--days)     DAYS="${2:?Number of days missing}"; DAYS_SET=1; shift 2 ;;
    -H|--hours)    HOURS="${2:?Number of hours missing}"; shift 2 ;;
    --from)        FROM="${2:?Start time missing}"; shift 2 ;;
    --to)          TO="${2:?End time missing}"; shift 2 ;;
    -u|--upstream) UPSTREAMS+=("${2:?Upstream missing}"); shift 2 ;;
    -q|--qtype)    QTYPES+=("${2:?Query type missing}"); shift 2 ;;
    -c|--client)   CLIENTS+=("${2:?Client missing}"); shift 2 ;;
    -x|--exclude)  EXCLUDES+=("${2:?Domain missing}"); shift 2 ;;
    -e|--errors)   WITHERR=1; shift ;;
    -g|--group)    GROUP="${2:?Period missing}"; shift 2 ;;
    -s|--sort)     SORT="${2:?Column missing}"; shift 2 ;;
    --no-total)    NOTOTAL=1; shift ;;
    -f|--db)       DB="${2:?Database path missing}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    -V|--version)  echo "$(basename "$0") $VERSION"
                   echo "Copyright (C) HaGeZi. License GPLv3+: GNU GPL version 3 or later"
                   echo "<https://www.gnu.org/licenses/gpl-3.0.html>"
                   exit 0 ;;
    *)             die "unknown option: $1 (help: -h)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate input and environment
# ---------------------------------------------------------------------------
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]]   || die "invalid number of days: $DAYS"
[[ "$HOURS" =~ ^[0-9]+$ ]]       || die "invalid number of hours: $HOURS"
n=0
[ "$DAYS_SET" -eq 1 ] && n=$((n + 1))
[ "$HOURS" -gt 0 ] && n=$((n + 1))
[ -n "$FROM" ] && n=$((n + 1))
[ "$n" -le 1 ] || die "use only one of -d, -H and --from"
command -v pihole-FTL >/dev/null  || die "pihole-FTL not found (Pi-hole v6 required)"
[ -r "$DB" ]                     || die "database not readable: $DB (try sudo)"

case "${GROUP,,}" in
  none) PERIOD="''" ;;
  day)  PERIOD="date(q.timestamp,'unixepoch','localtime')" ;;
  hour) PERIOD="strftime('%Y-%m-%d %H:00',q.timestamp,'unixepoch','localtime')" ;;
  *)    die "invalid period: $GROUP (none, day, hour)" ;;
esac
GROUP="${GROUP,,}"

# Sort: upstream ascending, avg ascending (fastest first), others descending
case "${SORT,,}" in
  upstream) SORTKEY="upstream ASC" ;;
  queries)  SORTKEY="queries DESC" ;;
  avg)      SORTKEY="avg_ms ASC" ;;
  median)   SORTKEY="median_ms DESC" ;;
  p95)      SORTKEY="p95_ms DESC" ;;
  max)      SORTKEY="max_ms DESC" ;;
  *)        die "invalid sort column: $SORT (upstream, queries, avg, median, p95, max)" ;;
esac
ORDER="period ASC, $SORTKEY, upstream ASC"

# Query types as stored by FTL v6 in queries.type
declare -A QTYPE_ID=(
  [A]=1 [AAAA]=2 [ANY]=3 [SRV]=4 [SOA]=5 [PTR]=6 [TXT]=7 [NAPTR]=8
  [MX]=9 [DS]=10 [RRSIG]=11 [DNSKEY]=12 [NS]=13 [OTHER]=14 [SVCB]=15 [HTTPS]=16
)
QTYPE_FILTER=""
if [ ${#QTYPES[@]} -gt 0 ]; then
  ids=""
  for t in "${QTYPES[@]}"; do
    t="${t^^}"
    [ -n "${QTYPE_ID[$t]:-}" ] || die "unknown query type: $t (help: -h)"
    ids+="${ids:+,}${QTYPE_ID[$t]}"
  done
  QTYPE_FILTER="AND q.type IN ($ids)"
fi

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
if [ -n "$FROM" ]; then
  FROM_TS=$(date -d "$FROM" +%s 2>/dev/null) || die "invalid start time: $FROM"
  if [ -n "$TO" ]; then
    TO_TS=$(date -d "$TO" +%s 2>/dev/null) || die "invalid end time: $TO"
  else
    TO_TS=$(date +%s)
  fi
  [ "$FROM_TS" -lt "$TO_TS" ] || die "start time must be before end time"
elif [ -n "$TO" ]; then
  die "--to requires --from"
elif [ "$HOURS" -gt 0 ]; then
  # End: start of the current hour, start: N hours earlier
  TO_TS=$(date -d "$(date '+%F %H:00:00')" +%s)
  FROM_TS=$(( TO_TS - HOURS * 3600 ))
else
  # "<date> N days ago" form, because GNU date would read "-N days" as a timezone
  FROM_TS=$(date -d "$(date +%F) $((DAYS - 1)) days ago" +%s)
  TO_TS=$(date +%s)
fi
TIME_FILTER="AND q.timestamp >= $FROM_TS AND q.timestamp < $TO_TS"
RANGE="$(date -d "@$FROM_TS" '+%Y-%m-%d %H:%M') to $(date -d "@$TO_TS" '+%Y-%m-%d %H:%M')"

# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------
UPSTREAM_FILTER=""
if [ ${#UPSTREAMS[@]} -gt 0 ]; then
  list=""
  for u in "${UPSTREAMS[@]}"; do list+="${list:+,}'$(sql_quote "$u")'"; done
  UPSTREAM_FILTER="AND q.forward IN ($list)"
fi

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

# Reply types as stored by FTL v6 in queries.reply_type:
# without -e: answers without error (NOERROR) and NXDOMAIN;
# with -e:    additionally SERVFAIL (7), REFUSED (8) and NOTIMP (9).
# Queries without reply (0) and dropped queries (NONE, 12) never have a
# meaningful reply time and are always excluded.
if [ "$WITHERR" -eq 1 ]; then
  REPLY_FILTER="AND q.reply_type IN (1,2,3,4,5,6,7,8,9,10,11,13)"
else
  REPLY_FILTER="AND q.reply_type IN (1,2,3,4,5,6,10,11,13)"
fi

# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------
# ev:  forwarded queries (status 2) with reply time in ms
# rk:  rank of every reply time per period and upstream (for median and P95)
# agg: statistics per period and upstream
EV="SELECT $PERIOD AS period,
           q.forward AS upstream,
           q.reply_time * 1000.0 AS ms
    FROM queries q
    WHERE q.status = 2
      AND q.forward IS NOT NULL AND q.forward <> ''
      AND q.reply_time IS NOT NULL
      $REPLY_FILTER
      $TIME_FILTER
      $UPSTREAM_FILTER
      $QTYPE_FILTER
      $CLIENT_FILTER
      $EXCLUDE"

# Statistics over the CTE "$1", partitioned by the columns in "$2"
stats() {
  local src="$1" part="$2"
  echo "rk AS (
          SELECT *,
                 row_number() OVER (PARTITION BY $part ORDER BY ms) AS rn,
                 count(*)     OVER (PARTITION BY $part) AS n
          FROM $src
        ),
        agg AS (
          SELECT $part,
                 max(n) AS queries,
                 avg(ms) AS avg_ms,
                 max(CASE WHEN rn = (n + 1) / 2 THEN ms END) AS median_ms,
                 max(CASE WHEN rn = max(1, CAST(n * 0.95 AS INT)) THEN ms END) AS p95_ms,
                 max(ms) AS max_ms
          FROM rk
          GROUP BY $part
        )"
}

if [ "$GROUP" = "none" ]; then PERIOD_COL=""; else PERIOD_COL="period AS Period,"; fi

SQL_ROWS="WITH ev AS ($EV),
     $(stats ev "period, upstream")
     SELECT $PERIOD_COL
            upstream AS Upstream,
            queries AS Queries,
            printf('%8.1f', avg_ms) AS Avg,
            printf('%8.1f', median_ms) AS Median,
            printf('%8.1f', p95_ms) AS P95,
            printf('%8.1f', max_ms) AS Max
     FROM agg
     ORDER BY $ORDER;"

SQL_TOTAL="WITH ev AS ($EV),
     ev2 AS (SELECT 'all' AS grp, ms FROM ev),
     $(stats ev2 "grp")
     SELECT (SELECT count(DISTINCT upstream) FROM ev) AS Upstreams,
            queries AS Queries,
            printf('%8.1f', avg_ms) AS Avg,
            printf('%8.1f', median_ms) AS Median,
            printf('%8.1f', p95_ms) AS P95,
            printf('%8.1f', max_ms) AS Max
     FROM agg;"

info="$RANGE"
[ "$GROUP" != "none" ] && info+=", per $GROUP"
[ ${#QTYPES[@]} -gt 0 ] && info+=", query types: ${QTYPES[*]^^}"
[ "$WITHERR" -eq 1 ] && info+=", incl. errors"
echo "Reply time per upstream in ms ($info)"

out=$(pihole-FTL sqlite3 -readonly -box "$DB" "$SQL_ROWS") || exit 1
if [ -z "$out" ]; then
  echo "No forwarded queries match the filters."
  exit 0
fi
echo "$out"

if [ "$NOTOTAL" -eq 0 ]; then
  echo
  echo "Total"
  pihole-FTL sqlite3 -readonly -box "$DB" "$SQL_TOTAL" || exit 1
fi

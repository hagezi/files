#!/usr/bin/env bash
#
# pihole-upstreamtime - DNS performance indicators from the Pi-hole FTL database
#
# Shows an overview (cache hit rate, stale answers, retries, errors, latency
# seen by the clients), the reply times per upstream DNS server (average,
# median, 95th percentile, maximum, error rate) and optionally a reply time
# histogram and the slowest domains, for the whole time range or per day or
# hour. The database is opened read-only, so the script is safe to run on a
# live system.
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

VERSION="1.1.0"

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
WINDOW=10
TOPN=0
MINQ=5
HIST=0
NOSUMMARY=0
NOUPSTREAMS=0
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
$me $VERSION - DNS performance indicators from the FTL database

Usage: $me [options]

Without options: today, all query types, the overview and one row per
upstream, sorted by average reply time. The database is opened read-only.

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
                          Applies to all views except the overview.
  -q, --qtype TYPE        Query type to include, e.g. A, AAAA, HTTPS.
                          Repeatable. Default: all query types
  -c, --client CLIENT     Only queries from this client, given as IP address or
                          client name (case-insensitive). Repeatable.
  -x, --exclude DOMAIN    Ignore queries for a domain incl. all its subdomains.
                          Repeatable. A leading dot is ignored.
  -e, --errors            Include replies with errors (SERVFAIL, REFUSED,
                          NOTIMP) in the reply times. Default: times only of
                          answers without error and NXDOMAIN, so timeouts do
                          not distort them. Error rates are always shown.

Views:
  -b, --histogram         Also show the distribution of the reply times per
                          upstream: < 10, 10-50, 50-100, 100-500, >= 500 ms
  -t, --top N             Also show the N slowest domains by median reply time
  -m, --min-queries N     With -t: only domains with at least N forwarded
                          queries. Default: $MINQ
      --no-summary        Do not show the overview
      --no-upstreams      Do not show the reply times per upstream
      --no-total          Do not show the total row below the upstreams

Output:
  -g, --group PERIOD      none, day or hour: one row per period (and upstream),
                          e.g. to compare before and after a change.
                          Default: $GROUP
  -s, --sort COLUMN       Sort the upstreams by upstream, queries, share, avg,
                          median, p95, max or errors. upstream sorts ascending,
                          avg fastest first, the others largest first.
                          Default: $SORT

Other:
  -w, --window SEC        Duplicate window for unanswered queries in seconds,
                          see "Errors" below. Default: $WINDOW
  -f, --db FILE           Path to the FTL database.
                          Default: $DB
  -h, --help              Show this help and exit
  -V, --version           Show the version and exit

Overview (all queries, incl. cache and blocked):
  Queries      All queries in the time range
  Blocked %    Blocked queries of all queries
  Cache %      Answered from the Pi-hole cache, incl. stale (of not blocked)
  Stale %      Answered with an expired cache entry (of not blocked). Rising
               values mean the upstream does not keep up with refreshing.
  Fwd %        Forwarded to an upstream (of not blocked)
  Retries %    Retried or already forwarded queries (of not blocked). Rising
               values mean clients repeat queries, an early sign of a slow
               upstream.
  Errors %     Error replies of the forwarded queries, see "Errors" below
  Client avg / Client median
               Reply time in ms seen by the clients, over all answered
               queries incl. cache and blocked: the latency users experience

Upstreams (forwarded queries):
  Queries      Forwarded queries, incl. errors
  Share %      Share of all forwarded queries
  Avg, Median, P95, Max
               Reply time in ms. P95: 95 % were answered at least this fast.
  Errors %     Error replies of the forwarded queries

Errors:
  SERVFAIL, REFUSED, NOTIMP and queries without any reply. A query without
  reply is not counted if dnsmasq merged it into another in-flight query
  for the same domain and type that was answered within the duplicate window
  (these are shown as "No reply received" in the Pi-hole query log).

Query types:
  A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS

Examples:
  # Today: overview and upstreams
  $me
  # Last 7 days per day, e.g. to see trends
  $me -d 7 -g day
  # Last 24 full hours per hour, with histogram
  $me -H 24 -g hour -b
  # The 20 slowest domains of the last 7 days (at least 10 queries)
  $me -d 7 -t 20 -m 10 --no-summary --no-upstreams
  # Compare two time windows, e.g. before and after a change
  $me --from "yesterday 18:00" --to "yesterday 22:00"
  $me --from "today 18:00" --to "today 22:00"
  # Only A and AAAA queries of one client, one upstream
  $me -q A -q AAAA -c laptop -u 127.0.0.1#5335
  # Use a copy of the database
  sudo cp $DB /tmp/ftl-copy.db
  $me -f /tmp/ftl-copy.db -d 30

Notes:
  - Needs read access to the database, so usually run with sudo.
  - Reply times are measured by Pi-hole: from forwarding a query until its
    reply. If the upstream is a local resolver (e.g. Unbound), its own cache
    hits pull the average down; the median and P95 are more meaningful then.
    Times of the servers behind a local resolver are only known to that
    resolver (Unbound: unbound-control dump_infra).
  - FTL writes to the database once per minute, the last minute may be
    missing. Long time ranges can take a while on a Raspberry Pi.

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
    -d|--days)        DAYS="${2:?Number of days missing}"; DAYS_SET=1; shift 2 ;;
    -H|--hours)       HOURS="${2:?Number of hours missing}"; shift 2 ;;
    --from)           FROM="${2:?Start time missing}"; shift 2 ;;
    --to)             TO="${2:?End time missing}"; shift 2 ;;
    -u|--upstream)    UPSTREAMS+=("${2:?Upstream missing}"); shift 2 ;;
    -q|--qtype)       QTYPES+=("${2:?Query type missing}"); shift 2 ;;
    -c|--client)      CLIENTS+=("${2:?Client missing}"); shift 2 ;;
    -x|--exclude)     EXCLUDES+=("${2:?Domain missing}"); shift 2 ;;
    -e|--errors)      WITHERR=1; shift ;;
    -b|--histogram)   HIST=1; shift ;;
    -t|--top)         TOPN="${2:?Number of domains missing}"; shift 2 ;;
    -m|--min-queries) MINQ="${2:?Number of queries missing}"; shift 2 ;;
    --no-summary)     NOSUMMARY=1; shift ;;
    --no-upstreams)   NOUPSTREAMS=1; shift ;;
    --no-total)       NOTOTAL=1; shift ;;
    -g|--group)       GROUP="${2:?Period missing}"; shift 2 ;;
    -s|--sort)        SORT="${2:?Column missing}"; shift 2 ;;
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
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]] || die "invalid number of days: $DAYS"
[[ "$HOURS" =~ ^[0-9]+$ ]]     || die "invalid number of hours: $HOURS"
[[ "$TOPN" =~ ^[0-9]+$ ]]      || die "invalid number of domains: $TOPN"
[[ "$MINQ" =~ ^[0-9]+$ ]]      || die "invalid minimum number of queries: $MINQ"
[[ "$WINDOW" =~ ^[0-9]+$ ]]    || die "invalid window: $WINDOW"
n=0
[ "$DAYS_SET" -eq 1 ] && n=$((n + 1))
[ "$HOURS" -gt 0 ] && n=$((n + 1))
[ -n "$FROM" ] && n=$((n + 1))
[ "$n" -le 1 ] || die "use only one of -d, -H and --from"
command -v pihole-FTL >/dev/null || die "pihole-FTL not found (Pi-hole v6 required)"
[ -r "$DB" ]                    || die "database not readable: $DB (try sudo)"

case "${GROUP,,}" in
  none) PERIOD="''" ;;
  day)  PERIOD="date(q.timestamp,'unixepoch','localtime')" ;;
  hour) PERIOD="strftime('%Y-%m-%d %H:00',q.timestamp,'unixepoch','localtime')" ;;
  *)    die "invalid period: $GROUP (none, day, hour)" ;;
esac
GROUP="${GROUP,,}"

# Sort: upstream ascending, avg ascending (fastest first), others descending
case "${SORT,,}" in
  upstream) SORTKEY="s.upstream ASC" ;;
  queries)  SORTKEY="s.queries DESC" ;;
  share)    SORTKEY="s.queries DESC" ;;
  avg)      SORTKEY="t.avg_ms ASC" ;;
  median)   SORTKEY="t.median_ms DESC" ;;
  p95)      SORTKEY="t.p95_ms DESC" ;;
  max)      SORTKEY="t.max_ms DESC" ;;
  errors)   SORTKEY="1.0 * s.errors / s.queries DESC" ;;
  *)        die "invalid sort column: $SORT (upstream, queries, share, avg, median, p95, max, errors)" ;;
esac

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

# SQL: percentage of $1 in $2, formatted, "-" if $2 is 0
pct() { echo "CASE WHEN ($2) > 0 THEN printf('%6.2f', 100.0 * ($1) / ($2)) ELSE '     -' END"; }

# SQL: milliseconds, formatted
fmt_ms() { echo "printf('%8.1f', $1)"; }

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
RANGE="$(date -d "@$FROM_TS" '+%Y-%m-%d %H:%M') to $(date -d "@$TO_TS" '+%Y-%m-%d %H:%M')"

# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------
# Common filters for all views
COMMON="AND q.timestamp >= $FROM_TS AND q.timestamp < $TO_TS $QTYPE_FILTER"

if [ ${#CLIENTS[@]} -gt 0 ]; then
  ips=""; names=""
  for c in "${CLIENTS[@]}"; do
    ips+="${ips:+,}'$(sql_quote "$c")'"
    names+="${names:+,}lower('$(sql_quote "$c")')"
  done
  COMMON+=" AND (q.client IN ($ips)
                OR q.client IN (SELECT na.ip FROM network_addresses na
                                WHERE lower(na.name) IN ($names))
                OR q.client IN (SELECT cb.ip FROM client_by_id cb
                                WHERE lower(cb.name) IN ($names)))"
fi

for x in "${EXCLUDES[@]}"; do
  x="${x#.}"
  COMMON+=" AND NOT (q.domain = '$(sql_quote "$x")'
                     OR q.domain LIKE '%.$(like_quote "$x")' ESCAPE '\\')"
done

# Upstream filter (all views except the overview)
UPSTREAM_FILTER=""
if [ ${#UPSTREAMS[@]} -gt 0 ]; then
  list=""
  for u in "${UPSTREAMS[@]}"; do list+="${list:+,}'$(sql_quote "$u")'"; done
  UPSTREAM_FILTER="AND q.forward IN ($list)"
fi

# Status as stored by FTL v6 in queries.status
BLOCKED="1,4,5,6,7,8,9,10,11,15,16,18"
PASSED="2,3,12,13,14,17"

# Error flag of a forwarded query (reply types as stored in queries.reply_type):
# SERVFAIL (7), REFUSED (8), NOTIMP (9), or no reply (0) unless dnsmasq merged
# the query into another in-flight query for the same domain and type that
# was answered within +/- WINDOW seconds.
ERR="(q.reply_type IN (7,8,9)
      OR (q.reply_type = 0 AND NOT EXISTS (
            SELECT 1 FROM queries q2
            WHERE q2.domain = q.domain AND q2.type = q.type
              AND q2.reply_type <> 0
              AND q2.timestamp BETWEEN q.timestamp - $WINDOW AND q.timestamp + $WINDOW)))"

# Replies whose time is used: answers without error and NXDOMAIN (with -e
# also SERVFAIL, REFUSED, NOTIMP). Never: no reply (0) and dropped (NONE, 12).
if [ "$WITHERR" -eq 1 ]; then
  TIMED="q.reply_type IN (1,2,3,4,5,6,7,8,9,10,11,13)"
else
  TIMED="q.reply_type IN (1,2,3,4,5,6,10,11,13)"
fi

# Forwarded queries with period, upstream, error flag and reply time
FWD="SELECT $PERIOD AS period,
            q.forward AS upstream,
            q.domain AS domain,
            CASE WHEN $ERR THEN 1 ELSE 0 END AS err,
            CASE WHEN $TIMED AND q.reply_time IS NOT NULL
                 THEN q.reply_time * 1000.0 END AS ms
     FROM queries q
     WHERE q.status = 2
       AND q.forward IS NOT NULL AND q.forward <> ''
       $COMMON
       $UPSTREAM_FILTER"

# Statistics of the column ms over the CTE $1, per the columns in $2.
# Produces the CTEs rk_$3 and $3 with: <columns>, n_ms, avg_ms, median_ms,
# p95_ms, max_ms
stats() {
  local src="$1" part="$2" name="$3"
  echo "rk_$name AS (
          SELECT $part, ms,
                 row_number() OVER (PARTITION BY $part ORDER BY ms) AS rn,
                 count(*)     OVER (PARTITION BY $part) AS n
          FROM $src WHERE ms IS NOT NULL
        ),
        $name AS (
          SELECT $part,
                 max(n) AS n_ms,
                 avg(ms) AS avg_ms,
                 max(CASE WHEN rn = (n + 1) / 2 THEN ms END) AS median_ms,
                 max(CASE WHEN rn = max(1, CAST(n * 0.95 AS INT)) THEN ms END) AS p95_ms,
                 max(ms) AS max_ms
          FROM rk_$name
          GROUP BY $part
        )"
}

if [ "$GROUP" = "none" ]; then PCOL=""; else PCOL="period AS Period,"; fi

run() { pihole-FTL sqlite3 -readonly -box "$DB" "$1"; }

# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------
show_summary() {
  local sql="WITH a AS (
      SELECT $PERIOD AS period, q.status AS status,
             CASE WHEN q.status = 2 AND $ERR THEN 1 ELSE 0 END AS err,
             CASE WHEN q.reply_time IS NOT NULL AND q.reply_type NOT IN (0,12)
                  THEN q.reply_time * 1000.0 END AS ms
      FROM queries q
      WHERE 1 = 1 $COMMON
    ),
    c AS (
      SELECT period,
             count(*) AS total,
             sum(status IN ($BLOCKED)) AS blocked,
             sum(status IN ($PASSED)) AS passed,
             sum(status IN (3,17)) AS cache,
             sum(status = 17) AS stale,
             sum(status = 2) AS fwd,
             sum(status IN (12,13,14)) AS retries,
             sum(err) AS errors
      FROM a GROUP BY period
    ),
    $(stats a period lat)
    SELECT ${PCOL//period/c.period}
           c.total AS Queries,
           $(pct c.blocked c.total) AS 'Blocked %',
           $(pct c.cache c.passed) AS 'Cache %',
           $(pct c.stale c.passed) AS 'Stale %',
           $(pct c.fwd c.passed) AS 'Fwd %',
           $(pct c.retries c.passed) AS 'Retries %',
           $(pct c.errors c.fwd) AS 'Errors %',
           $(fmt_ms l.avg_ms) AS 'Client avg',
           $(fmt_ms l.median_ms) AS 'Client median'
    FROM c LEFT JOIN lat l ON l.period = c.period
    ORDER BY c.period;"
  local out
  out=$(run "$sql") || return 1
  echo "Overview"
  [ -n "$out" ] && echo "$out" || echo "No queries match the filters."
  echo
}

show_upstreams() {
  local sql="WITH f AS ($FWD),
    s AS (
      SELECT period, upstream, count(*) AS queries, sum(err) AS errors
      FROM f GROUP BY period, upstream
    ),
    p AS (SELECT period, sum(queries) AS fwd FROM s GROUP BY period),
    $(stats f "period, upstream" t)
    SELECT ${PCOL//period/s.period}
           s.upstream AS Upstream,
           s.queries AS Queries,
           $(pct s.queries p.fwd) AS 'Share %',
           $(fmt_ms t.avg_ms) AS Avg,
           $(fmt_ms t.median_ms) AS Median,
           $(fmt_ms t.p95_ms) AS P95,
           $(fmt_ms t.max_ms) AS Max,
           $(pct s.errors s.queries) AS 'Errors %'
    FROM s
    JOIN p ON p.period = s.period
    LEFT JOIN t ON t.period = s.period AND t.upstream = s.upstream
    ORDER BY s.period, $SORTKEY, s.upstream;"
  local out
  out=$(run "$sql") || return 1
  echo "Reply time per upstream in ms"
  if [ -z "$out" ]; then
    echo "No forwarded queries match the filters."
    echo
    return 0
  fi
  echo "$out"

  if [ "$NOTOTAL" -eq 0 ]; then
    sql="WITH f AS ($FWD),
      f2 AS (SELECT 'all' AS grp, ms FROM f),
      $(stats f2 grp t)
      SELECT (SELECT count(DISTINCT upstream) FROM f) AS Upstreams,
             (SELECT count(*) FROM f) AS Queries,
             $(fmt_ms t.avg_ms) AS Avg,
             $(fmt_ms t.median_ms) AS Median,
             $(fmt_ms t.p95_ms) AS P95,
             $(fmt_ms t.max_ms) AS Max,
             $(pct "(SELECT sum(err) FROM f)" "(SELECT count(*) FROM f)") AS 'Errors %'
      FROM t;"
    echo "Total"
    run "$sql" || return 1
  fi
  echo
}

show_histogram() {
  local sql="WITH f AS ($FWD),
    h AS (
      SELECT period, upstream,
             count(*) AS n,
             sum(ms < 10) AS b1,
             sum(ms >= 10 AND ms < 50) AS b2,
             sum(ms >= 50 AND ms < 100) AS b3,
             sum(ms >= 100 AND ms < 500) AS b4,
             sum(ms >= 500) AS b5
      FROM f WHERE ms IS NOT NULL
      GROUP BY period, upstream
    )
    SELECT $PCOL
           upstream AS Upstream,
           n AS Queries,
           $(pct b1 n) AS '< 10 ms %',
           $(pct b2 n) AS '10-50 %',
           $(pct b3 n) AS '50-100 %',
           $(pct b4 n) AS '100-500 %',
           $(pct b5 n) AS '>= 500 %'
    FROM h
    ORDER BY period, upstream;"
  local out
  out=$(run "$sql") || return 1
  echo "Reply time distribution per upstream"
  [ -n "$out" ] && echo "$out" || echo "No forwarded queries match the filters."
  echo
}

show_top() {
  local sql="WITH f AS ($FWD),
    d AS (
      SELECT domain, count(*) AS queries,
             group_concat(DISTINCT upstream) AS upstreams
      FROM f GROUP BY domain
      HAVING count(*) >= $MINQ
    ),
    f2 AS (SELECT f.domain, f.ms FROM f JOIN d ON d.domain = f.domain),
    $(stats f2 domain t)
    SELECT d.domain AS Domain,
           d.queries AS Queries,
           $(fmt_ms t.median_ms) AS Median,
           $(fmt_ms t.p95_ms) AS P95,
           $(fmt_ms t.max_ms) AS Max,
           d.upstreams AS Upstreams
    FROM d JOIN t ON t.domain = d.domain
    ORDER BY t.median_ms DESC, d.queries DESC, d.domain
    LIMIT $TOPN;"
  local out
  out=$(run "$sql") || return 1
  echo "Slowest $TOPN domains by median reply time in ms (min. $MINQ queries)"
  [ -n "$out" ] && echo "$out" || echo "No domain has enough forwarded queries."
  echo
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
info="$RANGE"
[ "$GROUP" != "none" ] && info+=", per $GROUP"
[ ${#QTYPES[@]} -gt 0 ] && info+=", query types: ${QTYPES[*]^^}"
[ "$WITHERR" -eq 1 ] && info+=", times incl. errors"
echo "DNS performance ($info)"
echo

rc=0
[ "$NOSUMMARY" -eq 0 ]   && { show_summary   || rc=1; }
[ "$NOUPSTREAMS" -eq 0 ] && { show_upstreams || rc=1; }
[ "$HIST" -eq 1 ]        && { show_histogram || rc=1; }
[ "$TOPN" -gt 0 ]        && { show_top       || rc=1; }
exit $rc

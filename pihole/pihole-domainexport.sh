#!/usr/bin/env bash
#
# pihole-domainexport - export blocked and passed domains from the Pi-hole FTL database
#
# Writes the domains of the selected categories (blocked by gravity, by the
# denylist or by the upstream DNS server, or passed) into one text file each
# (one domain per line, sorted, unique). By default new domains are merged into
# existing files, so the files grow into a collection over time.
# The database is opened read-only.
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
#   sudo install -m 755 pihole-domainexport.sh /usr/local/bin/pihole-domainexport
#
# Usage:
#   sudo pihole-domainexport -o DIR [options]   (run with -h for all options and examples)

VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DB="/etc/pihole/pihole-FTL.db"
OUTDIR=""
DAYS=0
HOURS=0
FROM=""
TO=""
OVERWRITE=0
QUIET=0
KEEPLOCAL=0
QTYPES=()
CATEGORIES=()
REPLIES=()
EXCLUDES=()
CLIENTS=()

# Output file per category
declare -A FILE=(
  [gravity]="blocked.gravity.txt"
  [denylist]="blocked.blacklist.txt"
  [upstream]="blocked.upstream.txt"
  [passed]="passed.txt"
)

# Status as stored by FTL v6 in queries.status
declare -A STATUS=(
  [gravity]="1,9"            # gravity, gravity during deep CNAME inspection
  [denylist]="4,5,10,11"     # regex/exact denylist, incl. deep CNAME inspection
  [upstream]="6,7,8,18"      # blocking IP, 0.0.0.0/::, NXDOMAIN without RA, EDE 15
  [passed]="2,3,12,13,14,17"  # forwarded, cache, retried, already forwarded, stale cache
)

# Reply types as stored by FTL v6 in queries.reply_type, plus the groups
# OK (answered without error, NOERROR) and ERROR (error or no answer)
declare -A REPLY_ID=(
  [NODATA]=1 [NXDOMAIN]=2 [CNAME]=3 [IP]=4 [DOMAIN]=5 [RRNAME]=6 [SERVFAIL]=7
  [REFUSED]=8 [NOTIMP]=9 [OTHER]=10 [DNSSEC]=11 [NONE]=12 [BLOB]=13
  [OK]="1,3,4,5,6,10,11,13" [ERROR]="0,2,7,8,9,12"
)
REPLIES_DEFAULT=(OK)

# Query types as stored by FTL v6 in queries.type
declare -A QTYPE_ID=(
  [A]=1 [AAAA]=2 [ANY]=3 [SRV]=4 [SOA]=5 [PTR]=6 [TXT]=7 [NAPTR]=8
  [MX]=9 [DS]=10 [RRSIG]=11 [DNSKEY]=12 [NS]=13 [OTHER]=14 [SVCB]=15 [HTTPS]=16
)

usage() {
  local me
  me=$(basename "$0")
  cat <<EOF
$me $VERSION - export domains from the FTL database

Usage: $me -o DIR [options]

Exports blocked and/or passed domains into one file per category (one domain
per line, sorted, unique). New domains are merged into existing files by
default. Without -k only blocked domains are exported. The database is opened
read-only.

Required:
  -o, --output DIR        Output directory (created if missing)

Time range (default: all data in the database; use only one of -d, -H, --from):
  -d, --days N            Number of days, counted from today 00:00
                          (1 = today, 2 = today + yesterday, ...)
  -H, --hours N           The last N full hours, ending at the start of the
                          current hour (e.g. 1 at 10:05 = 09:00 to 10:00).
                          Waits briefly if started right after the full hour,
                          until FTL has stored the last queries of that hour.
      --from TIME         Start of the time range.
      --to TIME           End of the time range (requires --from).
                          Default: now
                          TIME is anything GNU date understands, e.g.
                          "03:00" (today), "2026-10-28 03:00", "yesterday 17:50"

Filters:
  -k, --category CAT      Category to export, see "Categories" below.
                          Repeatable. Default: blocked
  -q, --qtype TYPE        Query type to include, e.g. A, AAAA, HTTPS, or ALL.
                          Repeatable. Default: A and AAAA
  -r, --reply TYPE        Category passed only: export only domains whose
                          reply had this type or group, e.g. OK, IP, NXDOMAIN
                          or ANY. Repeatable. Default: OK (no errors)
  -c, --client CLIENT     Only queries from this client, given as IP address or
                          client name (case-insensitive). Repeatable.
  -x, --exclude DOMAIN    Exclude a domain incl. all its subdomains. Repeatable.
                          A leading dot is ignored (.example.com = example.com).
      --keep-local        Keep local names, see "Local names" below

Output:
      --overwrite         Replace the files instead of merging into them
  -s, --quiet             No summary, only errors

Other:
  -f, --db FILE           Path to the FTL database.
                          Default: $DB
  -h, --help              Show this help and exit
  -V, --version           Show the version and exit

Categories and files:
  gravity   ${FILE[gravity]}
            Blocked by the gravity database (adlists)
  denylist  ${FILE[denylist]}
            Blocked by the exact or regex denylist
  upstream  ${FILE[upstream]}
            Blocked by the upstream DNS server (blocking IP, 0.0.0.0/::,
            NXDOMAIN without RA bit, EDE 15)
  passed    ${FILE[passed]}
            Not blocked: forwarded, answered from cache or stale cache,
            retried or already forwarded. Pi-hole calls these "allowed";
            they are not necessarily on the allowlist. Allowlisted domains
            are included, FTL does not store them separately.
            By default only domains answered without error (-r OK).
  blocked   Shortcut for gravity, denylist and upstream
  all       Shortcut for all categories

  For queries blocked during deep CNAME inspection, the domain in the CNAME
  chain that caused the block is exported, not the queried domain.

Reply types (for -r, category passed only):
  OK        Group: answered without error (NOERROR), i.e. IP CNAME DOMAIN
            RRNAME NODATA OTHER DNSSEC BLOB. This is the default.
  ERROR     Group: error or no answer, i.e. NXDOMAIN SERVFAIL REFUSED NOTIMP
            NONE and queries without a stored reply
  ANY       All reply types, no filter
  Single:   IP NXDOMAIN NODATA CNAME DOMAIN RRNAME SERVFAIL REFUSED NOTIMP
            OTHER DNSSEC NONE BLOB
  A domain is exported if at least one of its queries matches. NODATA counts
  as OK: the domain exists, it only has no record of the requested type.

Query types (for -q):
  A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS ALL

Local names:
  Unless --keep-local is given, these names are never exported:
  names without a dot, localhost, pi.hole, fritz.box and names ending in
  .local .lan .localdomain .home .home.arpa .internal .in-addr.arpa .ip6.arpa

Examples:
  # Export all blocked domains (merge with existing files)
  $me -o /srv/dns-data/userdata
  # Only today, replace existing files
  $me -o /tmp/domains -d 1 --overwrite
  # Only gravity, last 7 days, incl. HTTPS queries
  $me -o /tmp/domains -k gravity -d 7 -q A -q AAAA -q HTTPS
  # Passed domains answered without error (default -r OK)
  $me -o /tmp/domains -k passed
  # Passed domains that really resolved to an IP address
  $me -o /tmp/domains -k passed -r IP
  # Passed domains with errors (candidates for list cleanup)
  $me -o /tmp/domains -k passed -r ERROR --overwrite
  # All passed domains, regardless of the reply
  $me -o /tmp/domains -k passed -r ANY
  # Blocked and passed domains of one client, without test domains
  $me -o /tmp/domains -k all -c laptop -x example.com
  # The last full hour, no output (e.g. for an hourly cron job)
  $me -o /tmp/domains -s -H 1
  # Yesterday only, no output (e.g. for a daily cron job)
  $me -o /tmp/domains -s --from "yesterday 00:00" \\
      --to "today 00:00"
  # Use a copy of the database
  sudo cp $DB /tmp/ftl-copy.db
  $me -o /tmp/domains -f /tmp/ftl-copy.db

Privacy:
  Passed domains are in effect the browsing history of all clients (banks,
  doctors, employer, local services). Do not publish ${FILE[passed]}, e.g. in a
  public git repository, without reviewing it. This is why the category
  passed is not part of the default.

Notes:
  - Needs read access to the database, so usually run with sudo.
  - Files are written atomically: a crash never leaves a half-written file.
  - Hourly cron job: with -H 1 every query is exported exactly once, as each
    run covers the hour before it, e.g. "5 * * * *". -H 2 adds one hour of
    overlap, so a single failed or skipped run does not lose any queries;
    the overlap is harmless because files are merged (do not combine it with
    --overwrite). FTL writes to the database every database.DBinterval
    seconds (default 60); -H waits until this interval plus 60 seconds has
    passed after the full hour.
  - The file names of the blocked categories are compatible with the former
    script exportPiholeQueryLog.sh.

Exit status:
  0  success
  1  invalid option, unreadable database, write or database error

Author: HaGeZi. License: GPL-3.0-or-later.
EOF
}

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)   OUTDIR="${2:?Output directory missing}"; shift 2 ;;
    -d|--days)     DAYS="${2:?Number of days missing}"; shift 2 ;;
    -H|--hours)    HOURS="${2:?Number of hours missing}"; shift 2 ;;
    --from)        FROM="${2:?Start time missing}"; shift 2 ;;
    --to)          TO="${2:?End time missing}"; shift 2 ;;
    -k|--category) CATEGORIES+=("${2:?Category missing}"); shift 2 ;;
    -q|--qtype)    QTYPES+=("${2:?Query type missing}"); shift 2 ;;
    -r|--reply)    REPLIES+=("${2:?Reply type missing}"); shift 2 ;;
    -c|--client)   CLIENTS+=("${2:?Client missing}"); shift 2 ;;
    -x|--exclude)  EXCLUDES+=("${2:?Domain missing}"); shift 2 ;;
    --keep-local)  KEEPLOCAL=1; shift ;;
    --overwrite)   OVERWRITE=1; shift ;;
    -s|--quiet)    QUIET=1; shift ;;
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
[ -n "$OUTDIR" ]                 || die "no output directory given (-o DIR, help: -h)"
[[ "$DAYS" =~ ^[0-9]+$ ]]        || die "invalid number of days: $DAYS"
[[ "$HOURS" =~ ^[0-9]+$ ]]       || die "invalid number of hours: $HOURS"
n=0
[ "$DAYS" -gt 0 ] && n=$((n + 1))
[ "$HOURS" -gt 0 ] && n=$((n + 1))
[ -n "$FROM" ] && n=$((n + 1))
[ "$n" -le 1 ] || die "use only one of -d, -H and --from"
command -v pihole-FTL >/dev/null  || die "pihole-FTL not found (Pi-hole v6 required)"
[ -r "$DB" ]                     || die "database not readable: $DB (try sudo)"

# Categories: expand shortcuts, remove duplicates, keep a fixed order
[ ${#CATEGORIES[@]} -eq 0 ] && CATEGORIES=(blocked)
declare -A WANT=()
for k in "${CATEGORIES[@]}"; do
  case "${k,,}" in
    blocked) WANT[gravity]=1; WANT[denylist]=1; WANT[upstream]=1 ;;
    all)     WANT[gravity]=1; WANT[denylist]=1; WANT[upstream]=1; WANT[passed]=1 ;;
    gravity|denylist|upstream|passed) WANT[${k,,}]=1 ;;
    *)       die "unknown category: $k (help: -h)" ;;
  esac
done
SELECTED=()
for k in gravity denylist upstream passed; do
  [ -n "${WANT[$k]:-}" ] && SELECTED+=("$k")
done

# Query type filter
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

# Reply type filter (category passed only; blocked replies come from Pi-hole)
if [ ${#REPLIES[@]} -gt 0 ]; then
  [ -n "${WANT[passed]:-}" ] || die "-r/--reply requires the category passed (-k passed or -k all)"
else
  REPLIES=("${REPLIES_DEFAULT[@]}")
fi
REPLY_FILTER=""
ids=""
for r in "${REPLIES[@]}"; do
  r="${r^^}"
  if [ "$r" = "ANY" ]; then ids=""; break; fi
  [ -n "${REPLY_ID[$r]:-}" ] || die "unknown reply type: $r (help: -h)"
  ids+="${ids:+,}${REPLY_ID[$r]}"
done
[ -n "$ids" ] && REPLY_FILTER="AND q.reply_type IN ($ids)"

mkdir -p "$OUTDIR" 2>/dev/null || die "cannot create output directory: $OUTDIR"
[ -w "$OUTDIR" ]               || die "output directory not writable: $OUTDIR"

# Escape single quotes for use inside SQL string literals
sql_quote() { printf '%s' "${1//\'/\'\'}"; }

# Escape LIKE wildcards (% _) and the escape character itself
like_quote() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//%/\\%}"; s="${s//_/\\_}"
  sql_quote "$s"
}

# SQL condition: domain column $1 is DOMAIN $2 or a subdomain of it
domain_match() {
  printf "(%s = '%s' OR %s LIKE '%%.%s' ESCAPE '\\\\')" \
    "$1" "$(sql_quote "$2")" "$1" "$(like_quote "$2")"
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
elif [ "$HOURS" -gt 0 ]; then
  # End: start of the current hour, start: N hours earlier (epoch arithmetic,
  # so DST changes do not shift the window)
  TO_TS=$(date -d "$(date '+%F %H:00:00')" +%s)
  FROM_TS=$(( TO_TS - HOURS * 3600 ))

  # FTL stores queries only every database.DBinterval seconds. Wait until the
  # queries up to TO_TS are certainly in the database, so none is lost.
  interval=$(pihole-FTL --config database.DBinterval 2>/dev/null | tr -dc '0-9')
  [ -n "$interval" ] || interval=60
  ready=$(( TO_TS + interval + 60 ))
  now=$(date +%s)
  if [ "$now" -lt "$ready" ]; then
    [ "$QUIET" -eq 0 ] && echo "Waiting $(( ready - now ))s until FTL has stored all queries before $(date -d "@$TO_TS" '+%H:%M') ..."
    sleep $(( ready - now ))
  fi

  TIME_FILTER="AND q.timestamp >= $FROM_TS AND q.timestamp < $TO_TS"
  RANGE="$(date -d "@$FROM_TS" '+%Y-%m-%d %H:%M:%S') to $(date -d "@$TO_TS" '+%Y-%m-%d %H:%M:%S')"
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

# Domain filters are applied to the exported domain (after the CNAME selection)
DOMAIN_FILTER=""
for x in "${EXCLUDES[@]}"; do
  DOMAIN_FILTER+=" AND NOT $(domain_match d "${x#.}")"
done

if [ "$KEEPLOCAL" -eq 0 ]; then
  DOMAIN_FILTER+=" AND instr(d, '.') > 0"
  for x in localhost pi.hole fritz.box local lan localdomain home home.arpa \
           internal in-addr.arpa ip6.arpa; do
    DOMAIN_FILTER+=" AND NOT $(domain_match d "$x")"
  done
fi

# Domain to export: for deep CNAME blocks (status 9, 10, 11) the domain that
# caused the block is stored in additional_info, otherwise it is the queried one.
DOMAIN_EXPR="lower(CASE WHEN q.status IN (9,10,11) THEN q.additional_info ELSE q.domain END)"

# Count the unique, non-empty lines of a file
count_lines() { sort -u "$1" | grep -c .; }

# ---------------------------------------------------------------------------
# Export one category
# ---------------------------------------------------------------------------
export_category() {
  local cat="$1"
  local extra=""
  [ "$cat" = "passed" ] && extra="$REPLY_FILTER"

  local sql="SELECT DISTINCT d FROM (
               SELECT $DOMAIN_EXPR AS d
               FROM queries q
               WHERE q.status IN (${STATUS[$cat]})
                 $QTYPE_FILTER
                 $TIME_FILTER
                 $CLIENT_FILTER
                 $extra
             )
             WHERE d IS NOT NULL AND d <> ''
               $DOMAIN_FILTER;"

  local target="$OUTDIR/${FILE[$cat]}"
  local new tmp
  new=$(mktemp) || return 1
  tmp=$(mktemp "$OUTDIR/.${FILE[$cat]}.XXXXXX") || { rm -f "$new"; return 1; }

  if ! pihole-FTL sqlite3 -readonly -list "$DB" "$sql" > "$new"; then
    rm -f "$new" "$tmp"
    return 1
  fi

  local before=0 found total added
  found=$(count_lines "$new")
  if [ "$OVERWRITE" -eq 0 ] && [ -f "$target" ]; then
    before=$(count_lines "$target")
    sort -u "$target" "$new" | grep . > "$tmp"
  else
    sort -u "$new" | grep . > "$tmp"
  fi
  total=$(count_lines "$tmp")
  if [ "$OVERWRITE" -eq 1 ]; then added=$found; else added=$(( total - before )); fi

  # Keep the permissions of an existing file, otherwise world-readable
  if [ -f "$target" ]; then chmod --reference="$target" "$tmp"; else chmod 644 "$tmp"; fi
  mv -f "$tmp" "$target" || { rm -f "$new" "$tmp"; return 1; }
  rm -f "$new"

  [ "$QUIET" -eq 0 ] && printf '  %-9s %7d found  %7d new  %7d total  %s\n' \
    "$cat" "$found" "$added" "$total" "$target"
  return 0
}

if [ "$QUIET" -eq 0 ]; then
  info="query types: ${QTYPES[*]^^}"
  [ -n "${WANT[passed]:-}" ] && info+=", reply types (passed): ${REPLIES[*]^^}"
  echo "Export of domains ($RANGE, $info)"
fi

rc=0
for k in "${SELECTED[@]}"; do
  export_category "$k" || { echo "$(basename "$0"): export of $k failed" >&2; rc=1; }
done
exit $rc


# pihole-upstreamtime

DNS performance indicators from the Pi-hole v6 query database (`pihole-FTL.db`).

Shows an overview (cache hit rate, stale answers, retries, errors, latency
seen by the clients), the reply times per upstream DNS server (average,
median, 95th percentile, maximum, error rate) and optionally a reply time
histogram and the slowest domains, for the whole time range or per day or hour.
The database is opened **read-only**, so the script is safe to run on a live system.

## Requirements

- Pi-hole v6 (uses the `sqlite3` built into `pihole-FTL`, no extra package needed)
- bash 4+, GNU date
- Read access to the database, so usually run with `sudo`

## Installation

```bash
sudo wget -qO /usr/local/bin/pihole-upstreamtime \
  https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole/pihole-upstreamtime.sh
sudo chmod 755 /usr/local/bin/pihole-upstreamtime
```

To update, run the same commands again. Check the installed version with `-V`.

## Usage

```
sudo pihole-upstreamtime [options]
```

Without options: today, all query types, the overview and one row per
upstream, sorted by average reply time.

## Options

### Time range

Use only one of `-d`, `-H`, `--from`.

| Option | Meaning |
|---|---|
| `-d, --days N` | Number of days, counted from today 00:00 (1 = today, 2 = today + yesterday, ...). Default: 1 |
| `-H, --hours N` | The last N full hours, ending at the start of the current hour (e.g. 1 at 10:05 = 09:00 to 10:00) |
| `--from TIME` | Start of the time range |
| `--to TIME` | End of the time range (requires `--from`). Default: now |

`TIME` is anything GNU date understands, e.g. `03:00` (today),
`2026-10-28 03:00`, `yesterday 17:50`.

### Filters

| Option | Meaning |
|---|---|
| `-u, --upstream SERVER` | Only this upstream, e.g. `127.0.0.1#5335`. Repeatable. Applies to all views except the overview. |
| `-q, --qtype TYPE` | Query type to include, e.g. `A`, `AAAA`, `HTTPS`. Repeatable. Default: all query types |
| `-c, --client CLIENT` | Only queries from this client, given as IP address or client name (case-insensitive). Repeatable. |
| `-x, --exclude DOMAIN` | Ignore queries for a domain incl. all its subdomains. Repeatable. A leading dot is ignored. |
| `-e, --errors` | Include replies with errors (SERVFAIL, REFUSED, NOTIMP) in the reply times. Default: times only of answers without error and NXDOMAIN, so timeouts do not distort them. Error rates are always shown. |

### Views

| Option | Meaning |
|---|---|
| `-b, --histogram` | Also show the distribution of the reply times per upstream: < 10, 10-50, 50-100, 100-500, >= 500 ms |
| `-t, --top N` | Also show the N slowest domains by median reply time |
| `-m, --min-queries N` | With `-t`: only domains with at least N forwarded queries. Default: 5 |
| `--no-summary` | Do not show the overview |
| `--no-upstreams` | Do not show the reply times per upstream |
| `--no-total` | Do not show the total row below the upstreams |

### Output

| Option | Meaning |
|---|---|
| `-g, --group PERIOD` | `none`, `day` or `hour`: one row per period (and upstream), e.g. to compare before and after a change. Default: `none` |
| `-s, --sort COLUMN` | Sort the upstreams by `upstream`, `queries`, `share`, `avg`, `median`, `p95`, `max` or `errors`. `upstream` sorts ascending, `avg` fastest first, the others largest first. Default: `avg` |
| `-F, --format FORMAT` | `box` (table), `csv` or `json`, see [Formats](#formats). Default: `box` |

### Other

| Option | Meaning |
|---|---|
| `-w, --window SEC` | Duplicate window for unanswered queries in seconds, see [Errors](#errors). Default: 10 |
| `-f, --db FILE` | Path to the FTL database. Default: `/etc/pihole/pihole-FTL.db` |
| `-h, --help` | Show the help and exit |
| `-V, --version` | Show the version and exit |

Query types: `A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS`

## Output

### Overview

All queries, incl. cache and blocked.

| Column | Meaning |
|---|---|
| Queries | All queries in the time range |
| Blocked % | Blocked queries of all queries |
| Cache % | Answered from the Pi-hole cache, incl. stale (of not blocked) |
| Stale % | Answered with an expired cache entry (of not blocked). Rising values mean the upstream does not keep up with refreshing. |
| Fwd % | Forwarded to an upstream (of not blocked) |
| Retries % | Retried or already forwarded queries (of not blocked). Rising values mean clients repeat queries, an early sign of a slow upstream. |
| Errors % | Error replies of the forwarded queries, see [Errors](#errors) |
| Client avg / Client median | Reply time in ms seen by the clients, over all answered queries incl. cache and blocked: the latency users experience |

### Reply time per upstream

Forwarded queries only, followed by a total row (hide with `--no-total`).

| Column | Meaning |
|---|---|
| Upstream | Upstream server, e.g. `127.0.0.1#5335` |
| Queries | Forwarded queries, incl. errors |
| Share % | Share of all forwarded queries |
| Avg, Median, P95, Max | Reply time in ms. P95 (nearest rank): at least 95 % were answered this fast or faster. |
| Errors % | Error replies of the forwarded queries |

### Histogram (`-b`)

Share of the reply times per upstream in the ranges < 10 ms, 10-50 ms,
50-100 ms, 100-500 ms and >= 500 ms.

### Slowest domains (`-t N`)

The N domains with the highest median reply time and at least `-m` forwarded
queries: Domain, Queries, Median, P95, Max, Upstreams (sorted).

## Formats

| Format | Output |
|---|---|
| `box` | Tables for reading, one per view, with a title line (default) |
| `csv` | Exactly one view with a header line, without the total. Select the view with `--no-summary`, `--no-upstreams`, `-b` or `-t`, e.g. `--no-summary` for the upstreams. |
| `json` | One object with the time range and the selected views: `overview`, `upstreams`, `total`, `histogram`, `top` |

```json
{"from":"2026-11-16 00:00:00","to":"2026-11-16 19:29:09",
 "overview":[{"Queries":796,"Blocked %":35.43,"Cache %":35.02,"Stale %":9.34,"Fwd %":39.88,
              "Retries %":25.1,"Errors %":38.54,"Client avg":145.0,"Client median":144.0}],
 "upstreams":[{"Upstream":"127.0.0.1#5335","Queries":70,"Share %":34.15,"Avg":140.7,"Median":136.3,
               "P95":294.0,"Max":296.4,"Errors %":37.14}],
 "total":{"Upstreams":1,"Queries":70,"Avg":140.7,"Median":136.3,"P95":294.0,"Max":296.4,"Errors %":37.14}}
```

In csv and json the numbers are plain, without padding; a percentage that
cannot be calculated is `null` (box: `-`). The keys are the column names of
the tables, with `-g day` or `-g hour` plus `Period`.

## Errors

SERVFAIL, REFUSED, NOTIMP and queries without any reply. A query without
reply is not counted if dnsmasq merged it into another in-flight query
for the same domain and type that was answered within the duplicate window
(these are shown as "No reply received" in the Pi-hole query log).

## Examples

```bash
# Today: overview and upstreams
sudo pihole-upstreamtime
# Last 7 days per day, e.g. to see trends
sudo pihole-upstreamtime -d 7 -g day
# Last 24 full hours per hour, with histogram
sudo pihole-upstreamtime -H 24 -g hour -b
# The 20 slowest domains of the last 7 days (at least 10 queries)
sudo pihole-upstreamtime -d 7 -t 20 -m 10 --no-summary --no-upstreams
# Compare two time windows, e.g. before and after a change
sudo pihole-upstreamtime --from "yesterday 18:00" --to "yesterday 22:00"
sudo pihole-upstreamtime --from "today 18:00" --to "today 22:00"
# Only A and AAAA queries of one client, one upstream
sudo pihole-upstreamtime -q A -q AAAA -c laptop -u 127.0.0.1#5335
# Upstreams of the last hour as CSV, everything as JSON
sudo pihole-upstreamtime -H 1 --no-summary -F csv > upstreams.csv
sudo pihole-upstreamtime -H 1 -b -t 10 -F json > dns-performance.json
# Use a copy of the database
sudo cp /etc/pihole/pihole-FTL.db /tmp/ftl-copy.db
sudo pihole-upstreamtime -f /tmp/ftl-copy.db -d 30
```

## Notes

- Reply times are measured by Pi-hole: from forwarding a query until its
  reply. If the upstream is a local resolver (e.g. Unbound), its own cache
  hits pull the average down; the median and P95 are more meaningful then.
  Times of the servers behind a local resolver are only known to that
  resolver (Unbound: `unbound-control dump_infra`).
- FTL writes to the database only once per minute. Queries of the last
  2 minutes are ignored because their reply may not be stored yet (they
  would be counted as errors without reply).
- Long time ranges can take a while on a Raspberry Pi.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Success (also if there are no results) |
| 1 | Invalid option, unreadable database or database error |

## License

GPL-3.0-or-later. Author: HaGeZi.

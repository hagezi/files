# pihole-blockrate

Block rate per client from the Pi-hole v6 query database (`pihole-FTL.db`).

Shows for every client the number of queries, how many were blocked or passed
(not blocked) and the block rate in percent, plus a total over all clients.
The database is opened **read-only**, so the script is safe to run on a live system.

## Requirements

- Pi-hole v6 (uses the `sqlite3` built into `pihole-FTL`, no extra package needed)
- bash 4+, GNU date
- Read access to the database, so usually run with `sudo`

## Installation

```bash
sudo wget -qO /usr/local/bin/pihole-blockrate \
  https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole/pihole-blockrate.sh
sudo chmod 755 /usr/local/bin/pihole-blockrate
```

To update, run the same commands again. Check the installed version with `-V`.

## Usage

```
sudo pihole-blockrate [options]
```

Without options: all data in the database, A and AAAA queries, clients with
at least 100 queries, sorted by client name.

## Options

### Time range

Default: all data in the database. `-H` and `--from` override `-d`; use only one of `-H` and `--from`.

| Option | Meaning |
|---|---|
| `-d, --days N` | Number of days, counted from today 00:00 (1 = today, 2 = today + yesterday, ...) |
| `-H, --hours N` | The last N full hours, ending at the start of the current hour (e.g. 1 at 10:05 = 09:00 to 10:00) |
| `--from TIME` | Start of the time range |
| `--to TIME` | End of the time range (requires `--from`). Default: now |

`TIME` is anything GNU date understands, e.g. `03:00` (today),
`2026-10-28 03:00`, `yesterday 17:50`.

### Filters

| Option | Meaning |
|---|---|
| `-q, --qtype TYPE` | Query type to include, e.g. `A`, `AAAA`, `HTTPS`, or `ALL`. Repeatable. Default: `A` and `AAAA` |
| `-c, --client CLIENT` | Only this client, given as IP address or client name (case-insensitive). Repeatable. |
| `-x, --exclude DOMAIN` | Ignore queries for a domain incl. all its subdomains. Repeatable. A leading dot is ignored. |
| `-m, --min N` | Only clients with at least N queries. Default: 100 |

### Output

| Option | Meaning |
|---|---|
| `-s, --sort COLUMN` | Sort by `name`, `ip`, `total`, `blocked`, `passed` or `rate`. `name` and `ip` sort ascending, the number columns descending (largest value first). Default: `name` |
| `-r, --reverse` | Reverse the sort order |
| `-l, --limit N` | Show only the first N clients (0 = all). Default: 0 |
| `--no-total` | Do not show the total over all clients |
| `-F, --format FORMAT` | `box` (table), `csv` or `json`, see [Formats](#formats). Default: `box` |

IPv4 addresses are sorted numerically, IPv6 addresses after IPv4.
With `-s name`, clients without a name always come last.

### Other

| Option | Meaning |
|---|---|
| `-f, --db FILE` | Path to the FTL database. Default: `/etc/pihole/pihole-FTL.db` |
| `-h, --help` | Show the help and exit |
| `-V, --version` | Show the version and exit |

Query types: `A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS ALL`

## Output

Per client:

| Column | Meaning |
|---|---|
| IP | Client IP address |
| Name | Name from the FTL client table, or the network table if empty |
| Total | All counted queries |
| Blocked | Blocked queries |
| Passed | Not blocked queries |
| Rate | Blocked in percent of total |

The total row shows the number of clients, Total, Blocked, Passed and Rate
over all clients that match the filters, including clients hidden by
`--min` or `--limit`. It is shown even if `--min` hides every client.

### What counts as blocked or passed

| Counted as | Pi-hole status |
|---|---|
| Blocked | gravity, denylist (exact/regex), deep CNAME inspection, upstream blocking, special domains, database busy |
| Passed | forwarded, cache, stale cache, retried, already forwarded |

Pi-hole calls passed queries "allowed"; they are not necessarily on the
allowlist. Queries with unknown status are not counted.

## Formats

| Format | Output |
|---|---|
| `box` | Table for reading with a title line and the total (default) |
| `csv` | Only the client rows with a header line, without the total |
| `json` | One object with the time range, the clients and the total |

```json
{"from":"2026-11-16 00:00:00","to":"2026-11-16 19:28:29",
 "clients":[{"IP":"192.168.178.110","Name":"laptop","Total":136,"Blocked":49,"Passed":87,"Rate":36.03}],
 "total":{"Clients":4,"Total":529,"Blocked":192,"Passed":337,"Rate":36.29}}
```

`from` is `null` without a time range (all data), `total` is `null` if no
query matches and missing with `--no-total`. Rate is a plain number in csv and json.

## Examples

```bash
# All data, sorted by name
sudo pihole-blockrate
# Highest block rate first
sudo pihole-blockrate -s rate
# Today, lowest block rate first
sudo pihole-blockrate -d 1 -s rate -r
# Top 10 clients by number of blocked queries in the last 7 days
sudo pihole-blockrate -d 7 -s blocked -l 10
# All query types, all clients, sorted by IP address
sudo pihole-blockrate -q ALL -m 0 -s ip
# Two clients, without a noisy domain
sudo pihole-blockrate -c laptop -c phone -x example.com
# The last 24 full hours
sudo pihole-blockrate -H 24 -s rate
# A time window of yesterday
sudo pihole-blockrate --from "yesterday 18:00" --to "yesterday 23:59"
# Export as CSV or JSON
sudo pihole-blockrate -d 7 -F csv > blockrate.csv
sudo pihole-blockrate -d 7 -F json > blockrate.json
# Use a copy of the database
sudo cp /etc/pihole/pihole-FTL.db /tmp/ftl-copy.db
sudo pihole-blockrate -f /tmp/ftl-copy.db
```

## Notes

- FTL writes to the database only once per minute. Queries of the last
  2 minutes are ignored because their status may not be stored yet.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Success (also if there are no results) |
| 1 | Invalid option, unreadable database or database error |

## License

GPL-3.0-or-later. Author: HaGeZi.

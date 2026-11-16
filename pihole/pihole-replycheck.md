# pihole-replycheck

Analyze DNS replies from the Pi-hole v6 query database (`pihole-FTL.db`).

Shows queries with a given reply type (e.g. `SERVFAIL`) or queries that got no
reply at all, either as a summary per day and domain or as single events.
The database is opened **read-only**, so the script is safe to run on a live system.

The type `NOREPLY` filters out queries that dnsmasq merged into another
in-flight query, so only real failures remain, unlike "No reply received"
in the Pi-hole query log.

## Requirements

- Pi-hole v6 (uses the `sqlite3` built into `pihole-FTL`, no extra package needed)
- bash 4+, GNU date
- Read access to the database, so usually run with `sudo`

## Installation

```bash
sudo wget -qO /usr/local/bin/pihole-replycheck \
  https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole/pihole-replycheck.sh
sudo chmod 755 /usr/local/bin/pihole-replycheck
```

To update, run the same commands again. Check the installed version with `-V`.

## Usage

```
sudo pihole-replycheck [options]
```

Without options: today, types `SERVFAIL` and `NOREPLY`, summary per day and domain.

## Options

### Time range

Default: `-d 1`. `-H` and `--from` override `-d`; use only one of `-H` and `--from`.

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
| `-t, --type TYPE` | Reply type to show, see [Reply types](#reply-types). Repeatable. Default: `SERVFAIL` and `NOREPLY` |
| `-c, --client CLIENT` | Only queries from this client, given as IP address or client name (case-insensitive). Repeatable. |
| `-x, --exclude DOMAIN` | Exclude a domain incl. all its subdomains. Repeatable. A leading dot is ignored. |

### Output

| Option | Meaning |
|---|---|
| `-n, --names` | Show client names instead of IP addresses |
| `-v, --verbose` | List every single event instead of a summary |
| `-m, --max-items N` | Summary only: show at most N clients and N upstreams per row, the rest as `… (+X)`. 0 = show all. Default: 0. The old name `--max-clients` still works. |
| `-F, --format FORMAT` | `box` (table), `csv` or `json`, see [Formats](#formats). Default: `box` |
| `--fail-on-results` | Exit with status 2 if any query was found, e.g. for cron jobs or monitoring, see [Monitoring](#monitoring) |

### Other

| Option | Meaning |
|---|---|
| `-w, --window SEC` | Duplicate window for `NOREPLY` in seconds. Default: 10 |
| `-f, --db FILE` | Path to the FTL database. Default: `/etc/pihole/pihole-FTL.db` |
| `-h, --help` | Show the help and exit |
| `-V, --version` | Show the version and exit |

## Reply types

| Type | Meaning |
|---|---|
| `NOREPLY` | No reply. Queries that dnsmasq merged into another in-flight query (same domain and type, any client) which was answered within the duplicate window are filtered out, so only real failures remain. |
| `UNKNOWN` | No reply, unfiltered. Includes the merged duplicates that the Pi-hole query log shows as "No reply received". |
| `SERVFAIL` | Server failure (e.g. DNSSEC validation error, broken delegation, upstream not reachable) |
| `REFUSED` | Query refused |
| `NXDOMAIN` | Domain does not exist |
| `NODATA` | Domain exists, but has no record of the requested type |
| `NOTIMP` | Query type not implemented |
| `NONE` | Empty reply |

## Output

Summary (default), one row per day and domain:

| Column | Meaning |
|---|---|
| Day | Date |
| Count | Number of matching queries |
| First, Last | Time of the first and last matching query |
| Domain | Queried domain |
| Clients | Clients that sent the query, sorted (limit with `-m`) |
| Upstreams | Upstreams that FTL stored for the queries, sorted (limit with `-m`) |

Verbose (`-v`), one row per query: Time, Domain, Client, Upstream.

Upstream is the server FTL stored for the query (e.g. `127.0.0.1#5335`).
It is empty if Pi-hole answered the query itself. With the dnsmasq option
`all-servers`, FTL stores only one of the queried upstreams.

Example:

```
$ sudo pihole-replycheck -d 7 -t SERVFAIL -m 3
SERVFAIL – last 7 day(s)
╭────────────┬───────┬──────────┬──────────┬─────────────┬─────────────────┬─────────────────────────────────────────────────────────╮
│    Day     │ Count │  First   │   Last   │    Domain   │     Clients     │                        Upstreams                        │
╞════════════╪═══════╪══════════╪══════════╪═════════════╪═════════════════╪═════════════════════════════════════════════════════════╡
│ 2026-11-11 │   200 │ 07:57:05 │ 17:26:49 │ example.com │ 192.168.178.110 │ 127.0.0.1#5335,149.112.112.112#53,2620:fe::11#53,… (+5) │
│ 2026-11-12 │    43 │ 09:45:00 │ 10:47:08 │ example.com │ 192.168.178.110 │ 127.0.0.1#5335                                          │
╰────────────┴───────┴──────────┴──────────┴─────────────┴─────────────────┴─────────────────────────────────────────────────────────╯
```

## Formats

| Format | Output |
|---|---|
| `box` | Tables for reading, one per type, with a title line (default) |
| `csv` | One table for all types with a header line and `Type` as first column |
| `json` | One object with the time range and one array of row objects per type (empty: `[]`) |

```json
{"from":"2026-11-15 00:00:00","to":"2026-11-16 19:27:59","results":{
  "SERVFAIL":[{"Type":"SERVFAIL","Day":"2026-11-15","Count":24,"First":"02:15:39","Last":"23:48:25",
               "Domain":"example.com","Clients":"192.168.178.110","Upstreams":"127.0.0.1#5335"}],
  "NOREPLY":[]}}
```

Clients and Upstreams stay comma-separated strings; with `-m` they are cut
like in the table, so leave `-m` at 0 for further processing.

## Monitoring

With `--fail-on-results` the exit status tells whether there were matching
queries: 0 = none, 2 = found, 1 = error. Example cron job that mails the
SERVFAIL of the last full hour, if there are any:

```
5 * * * * out=$(/usr/local/bin/pihole-replycheck -H 1 -t SERVFAIL --fail-on-results) || echo "$out" | mail -s "Pi-hole SERVFAIL" root
```

The same works in monitoring tools that run a command and check its exit status.

## Examples

```bash
# Today, SERVFAIL + NOREPLY
sudo pihole-replycheck
# Today and yesterday, with client names
sudo pihole-replycheck -d 2 -n
# SERVFAIL of the last 7 days, at most 3 clients and upstreams per row
sudo pihole-replycheck -d 7 -t SERVFAIL -m 3
# The last 6 full hours
sudo pihole-replycheck -H 6
# Two other reply types
sudo pihole-replycheck -t REFUSED -t NXDOMAIN
# Every single event of today
sudo pihole-replycheck -v
# One client by IP address, two clients by name
sudo pihole-replycheck -c 192.168.1.10
sudo pihole-replycheck -c laptop -c phone
# A time window of today, single events
sudo pihole-replycheck --from 03:00 --to 03:45 -v
# A time window of yesterday
sudo pihole-replycheck --from "yesterday 17:50" --to "yesterday 18:00"
# Hide DNSSEC test domains and another domain
sudo pihole-replycheck -x dnscheck.tools -x example.com
# NOREPLY with a wider duplicate window
sudo pihole-replycheck -t NOREPLY -w 30
# Export as CSV or JSON
sudo pihole-replycheck -d 7 -F csv > replies.csv
sudo pihole-replycheck -d 7 -F json > replies.json
# Analyze a copy of the database
sudo cp /etc/pihole/pihole-FTL.db /tmp/ftl-copy.db
sudo pihole-replycheck -f /tmp/ftl-copy.db -d 30
```

## Notes

- FTL writes to the database only once per minute. Queries of the last
  2 minutes are ignored because their reply may not be stored yet.
- Client names come from the FTL client table (`client_by_id`), or the
  network table (`network_addresses`) if empty. `-c` matches names from both.
- `NOREPLY` over many days (e.g. `-d 30`) can take a while on a Raspberry Pi.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Success, also if there are no results |
| 1 | Invalid option, unreadable database or database error |
| 2 | Results found (only with `--fail-on-results`) |

## License

GPL-3.0-or-later. Author: HaGeZi.

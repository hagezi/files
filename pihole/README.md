# Pi-hole FTL database scripts

Small shell scripts to analyze the Pi-hole v6 query database (`pihole-FTL.db`).
The database is always opened **read-only**, so they are safe to run on a live system.

| Script | Purpose |
|---|---|
| `pihole-replycheck.sh` | Find failed replies: SERVFAIL, real "no reply" failures, REFUSED, NXDOMAIN, ... |
| `pihole-blockrate.sh` | Block rate per client, with a total over all clients |
| `pihole-domainexport.sh` | Export blocked and/or passed domains to text files |
| `pihole-upstreamtime.sh` | Reply times per upstream DNS server (avg, median, P95, max) |

## Requirements

- Pi-hole v6 (uses the `sqlite3` built into `pihole-FTL`, no extra package needed)
- bash 4+, GNU date
- Read access to the database, so usually run with `sudo`

## Installation

Download and install all scripts to `/usr/local/bin`:

```bash
URL=https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole
for s in pihole-replycheck pihole-blockrate pihole-domainexport pihole-upstreamtime; do
  sudo curl -fsSL "$URL/$s.sh" -o "/usr/local/bin/$s" && sudo chmod 755 "/usr/local/bin/$s"
done
```

Or a single script, e.g. with `wget`:

```bash
sudo wget -qO /usr/local/bin/pihole-replycheck \
  https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole/pihole-replycheck.sh
sudo chmod 755 /usr/local/bin/pihole-replycheck
```

To update, run the same commands again. Check the installed version with `-V`.

Every script has a full help with all options and examples: `-h`.

## pihole-replycheck

Shows queries with a given reply type, as a summary per day and domain or as single events.
`NOREPLY` filters out queries that dnsmasq merged into another in-flight query, so only
real failures remain (unlike "No reply received" in the query log).

```bash
sudo pihole-replycheck                          # today, SERVFAIL + NOREPLY
sudo pihole-replycheck -d 7 -n -m 3             # last 7 days, client names, max. 3 per row
sudo pihole-replycheck --from 03:00 --to 03:45 -v
sudo pihole-replycheck -t REFUSED -x dnscheck.tools
```

## pihole-blockrate

Total, blocked and passed queries plus block rate per client.

```bash
sudo pihole-blockrate                           # all data, sorted by name
sudo pihole-blockrate -s rate                   # highest block rate first
sudo pihole-blockrate -d 7 -s blocked -l 10     # top 10 by blocked queries
```

## pihole-domainexport

Exports domains into one file per category, merged into existing files by default
(sorted, unique, written atomically).

| Category | File |
|---|---|
| `gravity` | `blocked.gravity.txt` |
| `denylist` | `blocked.blacklist.txt` |
| `upstream` | `blocked.upstream.txt` |
| `passed` | `passed.txt` (by default only domains answered without error) |

Shortcuts: `blocked` (default) and `all`.

```bash
sudo pihole-domainexport -o ./data                       # all blocked domains
sudo pihole-domainexport -o ./data -k all                # blocked + passed
sudo pihole-domainexport -o ./data -k passed -r ERROR    # passed domains with errors
```

Hourly cron job, one hour of overlap so a failed run loses nothing:

```
5 * * * * /usr/local/bin/pihole-domainexport -o /path/to/data -s -H 2
```

> **Privacy:** `passed.txt` is in effect the browsing history of all clients.
> Review it before publishing it anywhere, e.g. in a public repository.

## pihole-upstreamtime

Reply time in ms per upstream server, measured by Pi-hole for forwarded queries
(cache answers are not counted). Error replies are excluded unless `-e` is given.

```bash
sudo pihole-upstreamtime                        # today, one row per upstream
sudo pihole-upstreamtime -d 7 -g day            # last 7 days, per day
sudo pihole-upstreamtime -H 24 -g hour          # last 24 full hours, per hour
```

## Common options

| Option | Meaning |
|---|---|
| `-d N` / `--from`, `--to` | Time range: last N days or a custom window |
| `-H N` | Last N full hours (export and upstream times) |
| `-c CLIENT` | Only this client (IP or name), repeatable |
| `-x DOMAIN` | Exclude a domain incl. subdomains, repeatable |
| `-q TYPE` | Query types (export, block rate, upstream times) |
| `-f FILE` | Other database, e.g. a copy |
| `-h` / `-V` | Help / version |

## License

GPL-3.0-or-later. Author: HaGeZi.

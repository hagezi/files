# pihole-domainexport

Export blocked and passed domains from the Pi-hole v6 query database (`pihole-FTL.db`).

Writes the domains of the selected categories (blocked by gravity, by the
denylist or by the upstream DNS server, or passed) into one text file each:
one domain per line, sorted, unique. By default new domains are merged into
existing files, so the files grow into a collection over time.
The database is opened **read-only**, files are written atomically.

## Requirements

- Pi-hole v6 (uses the `sqlite3` built into `pihole-FTL`, no extra package needed)
- bash 4+, GNU date
- Read access to the database, so usually run with `sudo`

## Installation

```bash
sudo wget -qO /usr/local/bin/pihole-domainexport \
  https://raw.githubusercontent.com/hagezi/files/refs/heads/main/pihole/pihole-domainexport.sh
sudo chmod 755 /usr/local/bin/pihole-domainexport
```

To update, run the same commands again. Check the installed version with `-V`.

## Usage

```
sudo pihole-domainexport -o DIR [options]
```

Without `-k` only blocked domains are exported.

## Categories and files

| Category | File | Content |
|---|---|---|
| `gravity` | `blocked.gravity.txt` | Blocked by the gravity database (adlists) |
| `denylist` | `blocked.blacklist.txt` | Blocked by the exact or regex denylist |
| `upstream` | `blocked.upstream.txt` | Blocked by the upstream DNS server (blocking IP, 0.0.0.0/::, NXDOMAIN without RA bit, EDE 15) |
| `passed` | `passed.txt` | Not blocked: forwarded, answered from cache or stale cache, retried or already forwarded. By default only domains answered without error (`-r OK`). |
| `blocked` | | Shortcut for `gravity`, `denylist` and `upstream` (default) |
| `all` | | Shortcut for all categories |

- Pi-hole calls passed queries "allowed"; they are not necessarily on the
  allowlist. Allowlisted domains are included, FTL does not store them separately.
- For queries blocked during deep CNAME inspection, the domain in the CNAME
  chain that caused the block is exported, not the queried domain.
- The file names of the blocked categories are compatible with the former
  script `exportPiholeQueryLog.sh`.

## Options

### Required

| Option | Meaning |
|---|---|
| `-o, --output DIR` | Output directory (created if missing) |

### Time range

Default: all data in the database. Use only one of `-d`, `-H`, `--from`.

| Option | Meaning |
|---|---|
| `-d, --days N` | Number of days, counted from today 00:00 (1 = today, 2 = today + yesterday, ...) |
| `-H, --hours N` | The last N full hours, ending at the start of the current hour (e.g. 1 at 10:05 = 09:00 to 10:00). Waits briefly if started right after the full hour, until FTL has stored the last queries of that hour. |
| `--from TIME` | Start of the time range |
| `--to TIME` | End of the time range (requires `--from`). Default: now |

`TIME` is anything GNU date understands, e.g. `03:00` (today),
`2026-10-28 03:00`, `yesterday 17:50`.

### Filters

| Option | Meaning |
|---|---|
| `-k, --category CAT` | Category to export, see [Categories and files](#categories-and-files). Repeatable. Default: `blocked` |
| `-q, --qtype TYPE` | Query type to include, e.g. `A`, `AAAA`, `HTTPS`, or `ALL`. Repeatable. Default: `A` and `AAAA` |
| `-r, --reply TYPE` | Category `passed` only: export only domains whose reply had this type or group, e.g. `OK`, `IP`, `NXDOMAIN` or `ANY`. Repeatable. Default: `OK` |
| `-c, --client CLIENT` | Only queries from this client, given as IP address or client name (case-insensitive). Repeatable. |
| `-x, --exclude DOMAIN` | Exclude a domain incl. all its subdomains. Repeatable. A leading dot is ignored. |
| `--keep-local` | Keep local names, see [Local names](#local-names) |

### Output

| Option | Meaning |
|---|---|
| `--overwrite` | Replace the files instead of merging into them |
| `-s, --quiet` | No summary, only errors |

### Other

| Option | Meaning |
|---|---|
| `-f, --db FILE` | Path to the FTL database. Default: `/etc/pihole/pihole-FTL.db` |
| `-h, --help` | Show the help and exit |
| `-V, --version` | Show the version and exit |

Query types: `A AAAA ANY SRV SOA PTR TXT NAPTR MX DS RRSIG DNSKEY NS OTHER SVCB HTTPS ALL`

## Reply types

For `-r`, category `passed` only.

| Type | Meaning |
|---|---|
| `OK` | Group: answered without error (NOERROR), i.e. IP CNAME DOMAIN RRNAME NODATA OTHER DNSSEC BLOB. Default. |
| `ERROR` | Group: error or no answer, i.e. NXDOMAIN SERVFAIL REFUSED NOTIMP NONE and queries without a stored reply |
| `ANY` | All reply types, no filter |
| Single | `IP NXDOMAIN NODATA CNAME DOMAIN RRNAME SERVFAIL REFUSED NOTIMP OTHER DNSSEC NONE BLOB` |

A domain is exported if at least one of its queries matches. `NODATA` counts
as `OK`: the domain exists, it only has no record of the requested type.

## Local names

Unless `--keep-local` is given, these names are never exported: names without
a dot, `localhost`, `pi.hole`, `fritz.box` and names ending in `.local`, `.lan`,
`.localdomain`, `.home`, `.home.arpa`, `.internal`, `.in-addr.arpa`, `.ip6.arpa`.

## Output

A summary per category (suppressed with `-s`):

```
Export of domains (last 7 day(s), query types: A AAAA)
  gravity      1234 found       56 new    98765 total  /srv/dns-data/userdata/blocked.gravity.txt
  denylist       12 found        0 new      345 total  /srv/dns-data/userdata/blocked.blacklist.txt
  upstream        3 found        1 new       67 total  /srv/dns-data/userdata/blocked.upstream.txt
```

## Examples

```bash
# Export all blocked domains (merge with existing files)
sudo pihole-domainexport -o /srv/dns-data/userdata
# Only today, replace existing files
sudo pihole-domainexport -o /tmp/domains -d 1 --overwrite
# Only gravity, last 7 days, incl. HTTPS queries
sudo pihole-domainexport -o /tmp/domains -k gravity -d 7 -q A -q AAAA -q HTTPS
# Passed domains answered without error (default -r OK)
sudo pihole-domainexport -o /tmp/domains -k passed
# Passed domains that really resolved to an IP address
sudo pihole-domainexport -o /tmp/domains -k passed -r IP
# Passed domains with errors (candidates for list cleanup)
sudo pihole-domainexport -o /tmp/domains -k passed -r ERROR --overwrite
# All passed domains, regardless of the reply
sudo pihole-domainexport -o /tmp/domains -k passed -r ANY
# Blocked and passed domains of one client, without test domains
sudo pihole-domainexport -o /tmp/domains -k all -c laptop -x example.com
# The last full hour, no output (e.g. for an hourly cron job)
sudo pihole-domainexport -o /tmp/domains -s -H 1
# Yesterday only, no output (e.g. for a daily cron job)
sudo pihole-domainexport -o /tmp/domains -s --from "yesterday 00:00" --to "today 00:00"
# Use a copy of the database
sudo cp /etc/pihole/pihole-FTL.db /tmp/ftl-copy.db
sudo pihole-domainexport -o /tmp/domains -f /tmp/ftl-copy.db
```

## Cron job

Hourly, with one hour of overlap so a single failed or skipped run loses nothing:

```
5 * * * * /usr/local/bin/pihole-domainexport -o /path/to/data -s -H 2
```

- With `-H 1` every query is exported exactly once, as each run covers the hour before it.
- `-H 2` adds one hour of overlap. The overlap is harmless because files are
  merged; do not combine it with `--overwrite`.
- FTL writes to the database every `database.DBinterval` seconds (default 60).
  `-H` waits until this interval plus 60 seconds has passed after the full hour.

## Privacy

> `passed.txt` is in effect the browsing history of all clients (banks,
> doctors, employer, local services). Do not publish it, e.g. in a public git
> repository, without reviewing it. This is why the category `passed` is not
> part of the default.

## Notes

- Files are written atomically: a crash never leaves a half-written file.
  Temporary files are removed on exit and on interrupt (Ctrl+C, SIGTERM).
- Files are sorted byte-wise (`LC_ALL=C`), so the order is the same in an
  interactive shell, with sudo and in cron, and diffs between runs stay small.
- The permissions of an existing file are kept, new files are created world-readable (644).

## Exit status

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid option, unreadable database, write or database error |

## License

GPL-3.0-or-later. Author: HaGeZi.

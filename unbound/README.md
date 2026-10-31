# Unbound

Configuration and installation guide for **Unbound** as a local caching resolver (recursive with DNSSEC validation, or as DNS-over-TLS forwarder), e.g. as upstream for Pi-hole or AdGuard Home.

| File | Purpose |
|---|---|
| [`installation-arm.md`](installation-arm.md) | Step-by-step guide: build Unbound 1.26.2 from source on ARM64/AArch64 (Debian/Ubuntu, e.g. Raspberry Pi), install, verify |
| [`server.conf`](server.conf) | Unbound configuration, every option commented with the RFC it is based on |
| [`server-forwarder.conf`](server-forwarder.conf) | Optional alternative: forwards all queries via DNS over TLS to Quad9 (optionally also Cloudflare Security) instead of resolving from the root |
| [`unbound-post-install.tar.gz`](unbound-post-install.tar.gz) | Post-install script: `unbound` user, directories, systemd unit, `remote-control` keys |

## server.conf at a glance

- Recursive resolver with DNSSEC validation, listening on `127.0.0.1` port `5335`
- Local copy of the root zone (RFC 8806), verified with ZONEMD (RFC 8976)
- QNAME minimisation, aggressive NSEC, serve-stale (RFC 8767), Extended DNS Errors
- DNS rebinding protection, with commented-out exceptions for DNS blocklists, Wi-Fi calling and Plex
- RFC compliant except for four deliberate deviations, marked `DEVIATION` in the file
- Requires Unbound 1.20 or later; the latest release is recommended, at least 1.25.2

## server-forwarder.conf at a glance

- Forwarder with cache, listening on `127.0.0.1` port `5335`, no recursion and no contact to the root servers
- All queries encrypted via DNS over TLS to Quad9 (malware blocking, DNSSEC validation); Cloudflare Security can be enabled as a second provider
- Follows Quad9's DNS forwarder best practices: no local DNSSEC validation, no QNAME minimisation
- Serve-stale as recommended by RFC 8767 (fresh answer first, stale data after 1.8 s), Extended DNS Errors, same DNS rebinding protection as `server.conf`
- Fully RFC compliant; requires Unbound 1.20 or later; the latest release is recommended, at least 1.25.2

## Recursive or forwarder?

`server.conf` resolves every query itself from the root zone and validates DNSSEC locally: no third party sees all queries. `server-forwarder.conf` sends all queries encrypted to Quad9, which then sees every query, blocks malware domains and validates DNSSEC for you; Unbound only caches. Use one of the two as `/etc/unbound/unbound.conf`. With the forwarder, the root key from the installation guide is not needed and DNSSEC answers carry no `ad` flag.

## Quick start

Follow [`installation-arm.md`](installation-arm.md). To use only the configuration with an existing Unbound (for the forwarder, download `server-forwarder.conf` instead):

```bash
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
sudo unbound-checkconf /etc/unbound/unbound.conf && sudo systemctl restart unbound
```

Check the notes at the top of the configuration file first (minimum version and further hints). Always run `unbound-checkconf` before restarting: Unbound does not start with an invalid configuration.

Pi-hole upstream: `127.0.0.1#5335` · AdGuard Home upstream: `127.0.0.1:5335`

## Author

HaGeZi

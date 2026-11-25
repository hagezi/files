# Unbound

Configs and an install guide for running **Unbound** as a local caching resolver. You can run it recursive with DNSSEC validation, or as a DNS-over-TLS forwarder. Works great as the upstream for Pi-hole or AdGuard Home.

| File | Purpose |
|---|---|
| [`installation-arm.md`](installation-arm.md) | Step-by-step guide to build Unbound 1.26.2 from source on ARM64/AArch64 (Debian/Ubuntu, e.g. Raspberry Pi), install it and check that it works |
| [`server.conf`](server.conf) | Unbound configuration, every option commented with the RFC it's based on |
| [`server-forwarder.conf`](server-forwarder.conf) | Optional alternative: sends all queries via DNS over TLS to Quad9 (Cloudflare Security can be added) instead of resolving from the root |
| [`unbound-post-install.tar.gz`](unbound-post-install.tar.gz) | Post-install script: `unbound` user, directories, systemd unit, `remote-control` keys |

## server.conf in short

- Recursive resolver with DNSSEC validation, listening on `127.0.0.1` port `5335`
- Local copy of the root zone (RFC 8806), checked with ZONEMD (RFC 8976)
- QNAME minimisation, aggressive NSEC, serve-stale (RFC 8767), Extended DNS Errors
- DNS rebinding protection, with commented-out exceptions for DNS blocklists, Wi-Fi calling and Plex
- Follows the RFCs, except for four deliberate deviations marked `DEVIATION` in the file
- Needs Unbound 1.20 or newer. Better use the latest release, at least 1.25.2

## server-forwarder.conf in short

- Caching forwarder on `127.0.0.1` port `5335`. It doesn't recurse and never talks to the root servers
- Every query goes encrypted via DNS over TLS to Quad9, which blocks malware and validates DNSSEC. You can add Cloudflare Security as a second provider
- Sticks to Quad9's best practices for DNS forwarders: no local DNSSEC validation, no QNAME minimisation
- Serve-stale the way RFC 8767 recommends (tries for a fresh answer first, falls back to stale data after 1.8 s), Extended DNS Errors, and the same DNS rebinding protection as `server.conf`
- Fully RFC compliant. Needs Unbound 1.20 or newer, better the latest release, at least 1.25.2

## Recursive or forwarder?

With `server.conf`, Unbound resolves every query itself, starting at the root zone, and checks DNSSEC locally. No third party gets to see all your queries.

With `server-forwarder.conf`, every query goes encrypted to Quad9. Quad9 sees all of them, blocks malware domains and does the DNSSEC validation for you. Unbound just caches.

Pick one and use it as `/etc/unbound/unbound.conf`. If you go with the forwarder, you can skip the root key from the install guide, and DNSSEC answers won't have the `ad` flag.

## Quick start

Follow [`installation-arm.md`](installation-arm.md). Already have Unbound and just want the config? Run this (for the forwarder, grab `server-forwarder.conf` instead):

```bash
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
sudo unbound-checkconf /etc/unbound/unbound.conf && sudo systemctl restart unbound
```

Read the notes at the top of the config file first, they cover the minimum version and a few other things. And always run `unbound-checkconf` before restarting, because Unbound won't start with a broken config.

Pi-hole upstream: `127.0.0.1#5335` · AdGuard Home upstream: `127.0.0.1:5335`

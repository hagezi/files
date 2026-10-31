# Unbound

Configuration and installation guide for **Unbound** as a local, recursive and DNSSEC-validating resolver, e.g. as upstream for Pi-hole or AdGuard Home.

| File | Purpose |
|---|---|
| [`installation-arm.md`](installation-arm.md) | Step-by-step guide: build Unbound 1.26.2 from source on ARM64/AArch64 (Debian/Ubuntu, e.g. Raspberry Pi), install, verify |
| [`server.conf`](server.conf) | Unbound configuration, every option commented with the RFC it is based on |
| [`unbound-post-install.tar.gz`](unbound-post-install.tar.gz) | Post-install script: `unbound` user, directories, systemd unit, `remote-control` keys |

## Configuration at a glance

- Recursive resolver with DNSSEC validation, listening on `127.0.0.1` port `5335`
- Local copy of the root zone (RFC 8806), verified with ZONEMD (RFC 8976)
- QNAME minimisation, aggressive NSEC, serve-stale (RFC 8767), Extended DNS Errors
- DNS rebinding protection, with commented-out exceptions for DNS blocklists, Wi-Fi calling and Plex
- RFC compliant except for four deliberate deviations, marked `DEVIATION` in the file
- Requires Unbound 1.20 or later; the latest release is recommended, at least 1.25.2

## Quick start

Follow [`installation-arm.md`](installation-arm.md). To use only the configuration with an existing Unbound:

```bash
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
sudo unbound-checkconf /etc/unbound/unbound.conf && sudo systemctl restart unbound
```

Check the notes at the top of `server.conf` first (minimum version, sysctl for socket buffers). Always run `unbound-checkconf` before restarting: Unbound does not start with an invalid configuration.

Pi-hole upstream: `127.0.0.1#5335` · AdGuard Home upstream: `127.0.0.1:5335`

## Author

HaGeZi

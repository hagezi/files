# Unbound Installation (ARM64/AArch64)

This README explains how to install and compile **Unbound 1.26.0** from source on an **ARM64 / AArch64** Debian- or Ubuntu-based system.

It also includes a post-install step, a custom configuration, and basic verification commands for DNSSEC.

## Table of Contents

- [Notes](#notes)
- [1. Update the system](#step-1)
- [2. Remove an existing Unbound package](#step-2)
- [3. Install build dependencies](#step-3)
- [4. Download and extract Unbound](#step-4)
- [5. Configure the build](#step-5)
- [6. Compile and install](#step-6)
- [7. Run the post-install package](#step-7)
- [8. Install the configuration file](#step-8)
- [9. Enable and start the service](#step-9)
- [10. Verify the installation](#step-10)
- [11. Test DNSSEC](#step-11)
- [12. Clean up](#step-12)
- [Additional recommendations](#recommendations)
- [Optional: tune thread count](#tune-threads)
- [Optional: logging behavior](#logging)
- [Optional: monitoring and statistics](#monitoring)
- [Update Unbound](#update)
- [Full installation command block](#full-command-block)
- [Troubleshooting](#troubleshooting)
- [Glossary](#glossary)

## Notes <a id="notes"></a>

- This guide assumes a 64-bit ARM Linux system.
- `sudo` access is required.
- The configuration shown here uses **port 5335**, which is useful when another DNS service is already listening on port 53.
- Steps 1 through 12 can be followed one at a time, in order. The [Full installation command block](#full-command-block) near the end repeats the same commands as one continuous list, for copying and pasting all at once.
- The configuration only listens on `127.0.0.1` and only allows queries from `127.0.0.0/8`; see the `access-control` glossary entry for details.
- The configuration keeps a local, continuously updated copy of the DNS root zone through an `auth-zone` block, which reduces the number of queries sent to the public root servers.
- The configuration sets `num-threads: 2`; see [Optional: tune thread count](#tune-threads) for tuning it to the actual hardware.
- The configuration sets `logfile: ""`, so Unbound logs through syslog rather than to its own file; see [Optional: logging behavior](#logging).

## 1. Update the system <a id="step-1"></a>

Start in the home directory and bring the system fully up to date.

```bash
cd $HOME

# Update package lists, upgrade packages, remove obsolete packages, and clean the cache
sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

## 2. Remove an existing Unbound package <a id="step-2"></a>

If Unbound was previously installed from the distribution repository, remove it first to avoid conflicts.

```bash
# Remove the distro-provided Unbound package and related unused dependencies
sudo apt --purge autoremove unbound -y
```

## 3. Install build dependencies <a id="step-3"></a>

Install the toolchain, development libraries, and helper utilities required for compilation.

```bash
sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y
```

## 4. Download and extract Unbound <a id="step-4"></a>

Download the source archive and unpack it.

```bash
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.0.tar.gz
tar -xvzf unbound-1.26.0.tar.gz
cd unbound-1.26.0/
```

### Comment

This guide is pinned to version `1.26.0`. If a newer release is preferred, replace the version number in both the URL and directory name.

## 5. Configure the build <a id="step-5"></a>

Set a basic optimization flag and configure the ARM64 build.

```bash
export CFLAGS="-O2"

./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
```

## 6. Compile and install <a id="step-6"></a>

Build Unbound and install it system-wide.

```bash
make
sudo make install
```

On multi-core systems, compilation can be faster with:

```bash
make -j"$(nproc)"
```

## 7. Run the post-install package <a id="step-7"></a>

Download the additional post-install archive, extract it, and execute the script.

```bash
wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh
```

### Comment

This script:

1. Creates the `unbound` system user and group.
2. Creates the `/var/lib/unbound` directory with the correct ownership.
3. Installs the init script, systemd unit, and a helper script needed to run Unbound as a service.
4. Generates the key and certificate files needed for `remote-control`, used by the configuration in [step 8](#step-8).

It is safe to run more than once.

### Create the DNSSEC root key

Unbound needs one more file before it can start: the DNSSEC root trust anchor, at `/var/lib/unbound/root.key`.

Run this command once:

```bash
sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key
```

Then confirm the file now has content:

```bash
cat /var/lib/unbound/root.key
```

If this shows some text starting with `.` and a set of numbers, the file was created successfully.

## 8. Install the configuration file <a id="step-8"></a>

Return to the home directory, download the provided configuration, and move it into place.

```bash
cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
```

### Comment

This replaces the main Unbound configuration with the downloaded file. A few parts of it are worth knowing about:

- `msg-cache-size: 256m` and `rrset-cache-size: 512m` control the size of Unbound's built-in cache.
- `module-config: "validator iterator"` turns on DNSSEC validation and recursive resolution.
- Several privacy- and security-related options are already set to sensible values, reducing the information Unbound reveals to other servers and making it more resistant to common attacks.
- `access-control: 127.0.0.0/8 allow`, together with `interface: 127.0.0.1`, means Unbound only answers queries from the local machine; see the `access-control` glossary entry for more detail.
- A `remote-control:` section allows the `unbound-control` command to manage the running service, using the files created in [step 7](#step-7).
- An `auth-zone:` section keeps a local copy of the DNS root zone to speed up resolution.

### Recommended checks

Inspect the configuration:

```bash
cat /etc/unbound/unbound.conf
```

Check that the `remote-control` files created in step 7 are present:

```bash
ls -l /etc/unbound/unbound_server.key /etc/unbound/unbound_server.pem /etc/unbound/unbound_control.key /etc/unbound/unbound_control.pem
```

If any of them are missing, run `sudo unbound-control-setup` before starting the service.

Validate the syntax before starting the service:

```bash
sudo unbound-checkconf /etc/unbound/unbound.conf
```

No output means the configuration is valid. If there is a problem, the command prints a description of what and where.

## 9. Enable and start the service <a id="step-9"></a>

Enable Unbound at boot and start it immediately.

```bash
sudo systemctl enable unbound
sudo systemctl start unbound
```

### Comment

If the service does not start, inspect the logs with:

```bash
sudo journalctl -u unbound -b
```

## 10. Verify the installation <a id="step-10"></a>

Check the service state.

```bash
sudo systemctl status unbound
```

### Comment

To confirm the remote control interface set up in step 7 is reachable, run:

```bash
sudo unbound-control status
```

## 11. Test DNSSEC <a id="step-11"></a>

Run a negative DNSSEC test and then a positive validation test against the local resolver on port `5335`.

```bash
dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335
```

### Expected result

- `fail01.dnssec.works` should return `SERVFAIL`, because the domain is intentionally broken and validation should fail.
- `dnssec.works` queried with `+ad` should return the `ad` flag, which indicates successful DNSSEC validation.

If both results match, the installation is complete and working.

## 12. Clean up <a id="step-12"></a>

Remove the downloaded source and extracted directories when the installation is complete.

```bash
cd $HOME
rm -rf unbound-*
```

## Additional recommendations <a id="recommendations"></a>

- Confirm that port `5335` fits the local DNS design, especially when using AdGuard Home, Pi-hole, or another resolver.
- When pointing AdGuard Home or Pi-hole to this Unbound instance, set the upstream DNS server address explicitly. AdGuard Home expects `127.0.0.1:5335`, while Pi-hole expects `127.0.0.1#5335` in its custom upstream field, and all other upstream servers should be disabled to force traffic through Unbound.
- Do not enable a separate DNSSEC validation option in AdGuard Home or Pi-hole. In AdGuard Home, the "Enable DNSSEC" option only inspects and passes through the `ad` flag that Unbound already set; it does not perform its own validation. In Pi-hole's default setup, leave DNSSEC validation off on that layer as well.
- To confirm that DNSSEC validation is working end to end, query Unbound directly on port `5335`, as shown in [step 11](#step-11).
- Because `remote-control` is enabled with `control-interface: 127.0.0.1`, the control channel is only reachable from the local machine. Do not change this to a non-loopback address without adding proper access restrictions, since it grants administrative control over the resolver.
- The `auth-zone` block lists the root server addresses directly in the configuration. Since root server IP addresses can change over time, periodically compare them against the current root hints file distributed with the `dns-root-data` package.
- If Unbound is later configured to also listen on a non-loopback interface, for example to serve other devices on a local network, add an explicit `access-control: 0.0.0.0/0 refuse` (and the IPv6 equivalent) alongside a rule allowing the intended network range.

## Optional: tune thread count <a id="tune-threads"></a>

NLnet Labs recommends setting `num-threads` equal to the number of CPU cores on the system, since each thread can then run on its own core without competing for CPU time. The configuration installed in this guide uses `num-threads: 2`, which may be lower than the number of cores available on many ARM64 boards, such as a 4-core or 8-core Raspberry Pi.

1. Check how many CPU cores are available:

   ```bash
   nproc
   ```

2. Edit `/etc/unbound/unbound.conf` and set `num-threads` to that value, for example:

   ```
   num-threads: 4
   ```

3. When increasing `num-threads`, also increase the related `*-cache-slabs` settings (`msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs`, `infra-cache-slabs`). NLnet Labs' guidance is to use a power of two at or above the thread count, so for `num-threads: 4`, a value of `4` for each slab setting is a reasonable match.

4. Validate and apply the change:

   ```bash
   sudo unbound-checkconf /etc/unbound/unbound.conf
   sudo systemctl restart unbound
   ```

On a system that is shared with other services, such as a Pi also running Pi-hole or AdGuard Home, leaving one core free for other workloads by setting `num-threads` slightly below the total core count is also a reasonable choice.

## Optional: logging behavior <a id="logging"></a>

With `logfile: ""`, Unbound sends its log output to syslog, which on most current Debian- or Ubuntu-based systems ends up in the systemd journal, viewable with `journalctl -u unbound`. Log rotation is handled automatically by journald.

If a dedicated log file is preferred instead, `logfile` can be set to a path such as `/var/log/unbound/unbound.log`. In that case, add a `logrotate` configuration for that file, and after each rotation, trigger Unbound to release and reopen the file handle:

```bash
sudo unbound-control log_reopen
```

## Optional: monitoring and statistics <a id="monitoring"></a>

Unbound tracks internal counters, such as the number of queries and cache hits, and exposes them through `unbound-control`:

```bash
sudo unbound-control stats_noreset
```

This prints the current counters without resetting them.

By default, only aggregate counters are collected. To also break statistics down by query type, add the following to `/etc/unbound/unbound.conf` and restart the service:

```
server:
    extended-statistics: yes
```

For dashboards or alerting, a small daemon can poll `unbound-control stats_noreset` and expose the result in a format tools like Prometheus understand. The `unbound_exporter` project maintained by Let's Encrypt is a commonly used option for this, and works with the `remote-control` setup already in place from this guide.

## Update Unbound <a id="update"></a>

Because Unbound was installed from source, it will not receive updates through `apt`. Rebuild it whenever a new upstream release or security patch becomes available.

If you previously installed an older Unbound version using this guide and want to upgrade to a newer source release, repeat steps 4 through 6, then restart the Unbound service:

```bash
cd $HOME

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.0.tar.gz
tar -xvzf unbound-1.26.0.tar.gz
cd unbound-1.26.0/

export CFLAGS="-O2"
./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
make
sudo make install

sudo unbound-checkconf /etc/unbound/unbound.conf
sudo systemctl restart unbound

sudo systemctl status unbound

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

## Full installation command block <a id="full-command-block"></a>

The same commands as steps 1 through 12 above, listed together for copying and running in sequence.

```bash
cd $HOME

sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
sudo apt --purge autoremove unbound -y

sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.0.tar.gz
tar -xvzf unbound-1.26.0.tar.gz
cd unbound-1.26.0/

export CFLAGS="-O2"
./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
make
sudo make install

wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh

sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key

cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf

sudo unbound-checkconf /etc/unbound/unbound.conf
sudo systemctl enable unbound
sudo systemctl start unbound

sudo systemctl status unbound
sudo unbound-control status

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

## Troubleshooting <a id="troubleshooting"></a>

**Service fails to start**
Check `sudo journalctl -u unbound -b` for the exact error. A common cause is a syntax error in `/etc/unbound/unbound.conf` that was missed during `unbound-checkconf`, or a port conflict if another resolver is already bound to the configured port.

**`unbound-checkconf` reports an error**
Re-open `/etc/unbound/unbound.conf` and check indentation, since Unbound's configuration format is sensitive to structure. Confirm that referenced paths, such as the root key file or the chroot directory, actually exist on disk.

**Service fails with a permission error on the root key file**
This usually means the root key file is not owned by the `unbound` user. Compare the file owner against the expected user:

```bash
ls -l /var/lib/unbound/root.key
id unbound
```

If the file is owned by `root` or another user, fix the ownership directly:

```bash
sudo chown unbound:unbound /var/lib/unbound/root.key
```

**Service fails to start because of the remote control interface**
This usually means the key and certificate files are missing entirely, for example because `post-install.sh` was not run, or was run before `unbound-control-setup` was available on the system. Generate them and restart:

```bash
sudo unbound-control-setup
sudo systemctl restart unbound
```

**DNSSEC test does not return the expected result**
If `dig +ad dnssec.works @127.0.0.1 -p 5335` does not return the `ad` flag, confirm that the root trust anchor file exists and is not empty, and that the system clock is correct, since DNSSEC signatures are time-sensitive. Re-running `sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key` and restarting the service is a safe first step.

**Queries from other devices on the network are refused**
This is expected, since the configuration listens only on `127.0.0.1` and only allows `127.0.0.0/8`. To serve other devices, add a listening interface for the local network and a matching `access-control` rule for that network's address range.

**`unbound-control stats` or an exporter shows no data, or the connection is refused**
Confirm the `remote-control` key and certificate files exist and are valid, as described in [step 8](#step-8), and that `unbound-control status` succeeds first, as in [step 10](#step-10). If per-query-type detail is expected but missing, check that `extended-statistics: yes` has been added.

**Build fails during `./configure` or `make`**
Re-check that all packages from step 3 are installed. A failed `./configure` step usually names the missing library directly in its output.

## Glossary <a id="glossary"></a>

**Unbound**
A validating, recursive, and caching DNS resolver developed by NLnet Labs. It resolves DNS queries itself instead of simply forwarding them, and it supports native DNSSEC validation.

**ARM64 / AArch64**
The 64-bit version of the ARM processor architecture, used for example in the Raspberry Pi 3/4/5. AArch64 refers to the same architecture under its official ARM naming scheme.

**DNSSEC (Domain Name System Security Extensions)**
An extension of the DNS protocol that cryptographically signs responses. It allows a resolver to verify that a response actually originated from the authoritative server and was not tampered with.

**num-threads**
The `unbound.conf` option that sets how many worker threads Unbound uses to process queries in parallel. Related settings such as `msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs`, and `infra-cache-slabs` divide the corresponding caches into that many (or more) independently locked segments.

**logfile**
The `unbound.conf` option that sets where log output is written. An empty value, `logfile: ""`, sends log output to syslog instead of a dedicated file.

**log_reopen**
An `unbound-control` command that tells Unbound to close and reopen its log output, mainly used after an external tool such as `logrotate` has rotated a dedicated log file.

**extended-statistics**
An `unbound.conf` option that, when set to `yes`, makes Unbound collect more detailed statistics, such as counts broken down by query type.

**stats_noreset**
An `unbound-control` command that prints Unbound's internal performance counters, such as query counts and cache hit rates, without resetting them.

**unbound_exporter**
A third-party Prometheus metrics exporter, maintained by Let's Encrypt, that connects to Unbound's `remote-control` interface and exposes statistics for Prometheus.

**systemd integration**
Unbound's ability to hook into the Linux init and service manager systemd. During startup, systemd starts Unbound as `root`, Unbound reads privileged files and binds its listening ports, and only then drops down to the unprivileged `unbound` user.

**post-install.sh**
A shell script, hosted in the `hagezi/files` repository, that creates the `unbound` system user, the `/var/lib/unbound` directory, the init script and systemd unit, and the `remote-control` key and certificate files.

**Root key / trust anchor**
The public cryptographic key of the DNS root zone, forming the trust anchor for the entire DNSSEC validation chain. It is created with `unbound-anchor` and stored at `/var/lib/unbound/root.key`, owned by the `unbound` user.

**auto-trust-anchor-file**
The `unbound.conf` option that tells Unbound where to find and continuously update its DNSSEC root trust anchor.

**module-config**
The `unbound.conf` option that defines which processing modules are active, for example `"validator iterator"`, which turns on DNSSEC validation and recursive resolution.

**access-control**
The `unbound.conf` option that determines which client IP ranges may query Unbound, using actions such as `allow`, `refuse`, or `deny`.

**remote-control**
A `unbound.conf` section that enables the `unbound-control` utility to manage a running Unbound instance, for example to query status or flush the cache. It requires the key and certificate files created by `post-install.sh`.

**unbound-control**
A command-line tool for interacting with a running Unbound daemon over its remote control interface, for example `unbound-control status` or `unbound-control stats_noreset`.

**unbound-control-setup**
A command-line tool that generates the key and certificate files needed for the `remote-control` interface.

**auth-zone**
A `unbound.conf` section that keeps a local, file-based copy of a DNS zone, most commonly the root zone, to speed up resolution.

**Port 5335**
An alternative, non-standard port for DNS queries, used here so Unbound can run alongside another DNS service on port 53.

**AD flag (Authenticated Data)**
A flag in DNS responses indicating that the resolver successfully validated the response using DNSSEC. It only appears when the query is made with the `+ad` option.

**SERVFAIL**
A DNS response code indicating a server failure, which in the context of DNSSEC typically means signature validation failed.

**unbound-checkconf**
A command-line tool that checks the syntax of the Unbound configuration file, printing no output when the configuration is valid.

**unbound-anchor**
A command-line tool that sets up or updates the DNSSEC root trust anchor.

**CFLAGS**
An environment variable that passes compiler flags to the build process. `CFLAGS="-O2"` applies a moderate level of compiler optimization.

**./configure**
The standard script used in source-based builds to detect the system environment and generate a `Makefile`.

**journalctl**
A command-line tool for reading the systemd journal. `journalctl -u unbound -b` shows log entries for the Unbound service from the current boot.

**dig**
A command-line utility for querying DNS servers directly, used in this guide to test the local Unbound instance.

**Upstream DNS server**
The DNS server that another resolver or ad-blocking tool, such as AdGuard Home or Pi-hole, forwards its queries to. In this guide, Unbound acts as that upstream server, listening on `127.0.0.1` at port `5335`.

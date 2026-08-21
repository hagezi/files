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
- The post-install script and configuration file used in this guide are self-maintained, hosted in the `hagezi/files` repository. Review them before executing them in production regardless, since it is good practice to confirm the current content of any downloaded script matches what is expected, especially after later edits.
- Unbound's normal in-memory caching (message cache, RRset cache, key cache) is active and sized through settings like `msg-cache-size` and `rrset-cache-size` in the configuration. This is separate from the optional `cachedb` module, which adds a second, persistent cache backend such as Redis; `cachedb` is compiled in but not enabled in this configuration.
- The configuration enables `remote-control`. The post-install script in [step 7](#step-7) already generates the required control keys, so no separate manual step is needed.
- The configuration keeps a local, continuously updated copy of the DNS root zone through an `auth-zone` block, which reduces the number of queries sent to the public root servers.
- The configuration only listens on `127.0.0.1` and only allows queries from `127.0.0.0/8`. Unbound refuses queries from any other address by default, even without this explicit rule, so this setting mainly documents the intent rather than changing the default behavior.
- The configuration sets `num-threads: 2`. This is a reasonable default, but it can optionally be tuned to the actual number of CPU cores; see [Optional: tune thread count](#tune-threads).
- The configuration sets `logfile: ""`, so Unbound logs through syslog rather than to its own file; see [Optional: logging behavior](#logging) for what this means in practice.

## 1. Update the system <a id="step-1"></a>

Start in the home directory and bring the system fully up to date.

```bash
cd $HOME

# Update package lists, upgrade packages, remove obsolete packages, and clean the cache
sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

### Comment

This reduces the chance of build problems caused by outdated packages or dependency mismatches.

## 2. Remove an existing Unbound package <a id="step-2"></a>

If Unbound was previously installed from the distribution repository, remove it first to avoid conflicts.

```bash
# Remove the distro-provided Unbound package and related unused dependencies
sudo apt --purge autoremove unbound -y
```

### Comment

This helps prevent conflicts between repository binaries and the custom version built from source.

## 3. Install build dependencies <a id="step-3"></a>

Install the toolchain, development libraries, and helper utilities required for compilation.

```bash
sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y
```

### Comment

These packages provide support for:

- DNSSEC
- `dnstap`
- Redis cachedb
- HTTP/2
- Python bindings
- systemd integration

## 4. Download and extract Unbound <a id="step-4"></a>

Download the source archive and unpack it.

```bash
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.0.tar.gz
tar -xvzf unbound-1.26.0.tar.gz
cd unbound-1.26.0/
```

### Comment

This guide is pinned to version `1.26.0`. If a newer release is preferred, replace the version number in both the URL and directory name.

### Recommended check

Before building, verify the archive against the official checksum and signature. NLnet Labs does not publish these values in this document; they must be looked up directly at the source for the version being installed:

- [NLnet Labs Unbound downloads page](https://nlnetlabs.nl/downloads/unbound/)
- [NLnet Labs Unbound release announcements](https://nlnetlabs.nl/news/)

Both pages list the SHA256 checksum and the PGP signature for each release. Once you have the published checksum, verify the downloaded archive with:

```bash
sha256sum unbound-1.26.0.tar.gz
```

Compare the resulting hash character by character against the value shown on the NLnet Labs page for the same version. This check applies to the upstream Unbound source archive, which is a genuine third-party download, unlike the post-install script and configuration file used later in this guide.

## 5. Configure the build <a id="step-5"></a>

Set a basic optimization flag and configure the ARM64 build.

```bash
export CFLAGS="-O2"

./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
```

### Comment

This configuration enables a feature-rich build with support for:

- `dnstap`
- Redis-backed cache storage
- EDNS Client Subnet
- systemd integration
- Python modules
- TCP Fast Open

Compiling in a feature only makes the code available. The configuration file installed in [step 8](#step-8) does not activate every compiled-in feature; for example, the optional `cachedb` module is compiled in but not listed in `module-config`, so its persistent Redis-backed cache layer stays inactive unless the configuration is changed. This does not affect Unbound's normal in-memory caching, which works independently of `cachedb` and is active by default. See the [Glossary](#glossary) for details on `cachedb` and TCP Fast Open.

### Security note

The option `--with-chroot-dir=` disables chrooting. That can simplify integration, but it is less restrictive than running Unbound inside a chroot.

## 6. Compile and install <a id="step-6"></a>

Build Unbound and install it system-wide.

```bash
make
sudo make install
```

### Comment

On multi-core systems, compilation can be faster with:

```bash
make -j"$(nproc)"
```

If the build fails, the most common causes are missing development packages or an incorrect build environment.

## 7. Run the post-install package <a id="step-7"></a>

Download the additional post-install archive, extract it, and execute the script.

```bash
wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh
```

### Comment

This script performs the following actions, in order:

1. Creates the `unbound` system user and group if they do not already exist, using `/var/lib/unbound` as the home directory.
2. Creates `/var/lib/unbound` if missing, and sets its ownership to `unbound:unbound`.
3. Copies an init script to `/etc/init.d/unbound`, a systemd unit to `/usr/lib/systemd/system/unbound.service`, and a helper script to `/usr/libexec/unbound-helper`, each only if the target file does not already exist.
4. Generates the `remote-control` key and certificate files with `unbound-control-setup`, but only if `/etc/unbound/unbound_control.key` does not already exist.

Because the last step already runs `unbound-control-setup` automatically, no separate manual `unbound-control-setup` call is needed later, even though the configuration installed in [step 8](#step-8) enables `remote-control`.

Each of these actions is skipped if its target already exists, so re-running the script on a system that already has these files in place does not overwrite them.

This step runs `unbound-control-setup` as `root`, which creates the resulting key and certificate files under `/etc/unbound/` owned by `root`. This does not cause a permission problem in practice: systemd starts the Unbound daemon as `root`, and Unbound reads its server key and certificate while still running with root privileges, before it drops down to the `unbound` user afterward as directed by the built-in default (or a configured `username:` value). By the time Unbound has switched to the unprivileged `unbound` user, it has already finished reading those files.

### Important

Since this script is downloaded from a repository rather than typed in directly, confirm it still matches the version this guide describes before running it:

```bash
cat post-install.sh
```

### Root key initialization

This step is required in addition to the post-install script above, which does not create or manage the DNSSEC root trust anchor. Unlike the remote control key files, the root trust anchor is not only read once at startup, it is also periodically rewritten by Unbound while running as the unprivileged `unbound` user, so it does need to be owned by that user specifically, not just readable by root at startup.

The configuration uses `auto-trust-anchor-file` pointing at `/var/lib/unbound/root.key`, and if that file is missing or empty when the service starts, Unbound fails to start with a validator error, since it has no key material to validate DNSSEC signatures against. Unbound does not create this file by itself, and the post-install script above creates the `unbound` user and the `/var/lib/unbound` directory, but not the root key file inside it. This has to be done manually, once, before starting Unbound for the first time.

Follow these steps:

1. Check whether the file already exists and has content:

   ```bash
   ls -l /var/lib/unbound/root.key
   ```

2. Run `unbound-anchor` as the `unbound` user, so the resulting file has the correct owner:

   ```bash
   sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key
   ```

3. Confirm the file now exists, is not empty, and is owned by `unbound`:

   ```bash
   ls -l /var/lib/unbound/root.key
   cat /var/lib/unbound/root.key
   ```

The command is safe to run even if the file already exists: it creates the file with a built-in starting key if it is missing or empty, and leaves a valid existing anchor unchanged. Once `unbound.conf` is in place with `auto-trust-anchor-file` set to this path, Unbound keeps the key up to date automatically through periodic RFC 5011 checks, so this manual step normally only needs to be done once, right after installation.

## 8. Install the configuration file <a id="step-8"></a>

Return to the home directory, download the provided configuration, and move it into place.

```bash
cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
```

### Comment

This replaces the main Unbound configuration with the downloaded file. This particular configuration includes several notable sections beyond basic resolver settings:

- Standard in-memory caching is fully active through settings such as `msg-cache-size: 256m`, `rrset-cache-size: 512m`, and `key-cache-size: 32m`, along with `prefetch: yes` and `prefetch-key: yes` to refresh popular records before they expire. This caching works independently of `cachedb`.
- `module-config: "validator iterator"` under `server:` enables DNSSEC validation and recursive resolution, but does not include `cachedb`, so the optional persistent Redis cache backend stays inactive even though it was compiled in. This only affects the optional second-layer cache, not the in-memory caching described above.
- Privacy and hardening options such as `qname-minimisation: yes`, `hide-identity: yes`, `hide-version: yes`, `harden-dnssec-stripped: yes`, and `aggressive-nsec: yes` reduce the information Unbound reveals to upstream servers and make it more resistant to certain classes of DNS attacks. `harden-algo-downgrade` is explicitly set to `no`, which allows validation to succeed even if a zone advertises a weaker DNSSEC algorithm alongside a stronger one, trading a small amount of strictness for wider compatibility.
- `access-control: 127.0.0.0/8 allow`, combined with `interface: 127.0.0.1`, restricts Unbound to answering only local queries. This matches Unbound's built-in default behavior, which already refuses queries from any address that is not explicitly allowed, so this line documents the intended access scope rather than changing it.
- `num-threads: 2` is set for the worker thread count. This is a safe, conservative default; see [Optional: tune thread count](#tune-threads) for how to adjust it to the actual hardware.
- `logfile: ""` and `log-time-ascii: yes` route Unbound's log output through syslog rather than a dedicated file; see [Optional: logging behavior](#logging) for what this means for log rotation.
- A `remote-control:` block with `control-enable: yes`, which allows the `unbound-control` utility to manage the running daemon. The key and certificate files this requires were already generated by the post-install script in [step 7](#step-7). This also provides the basis for optional monitoring; see [Optional: monitoring and statistics](#monitoring).
- An `auth-zone:` block for the root zone (`name: "."`), which keeps a local, continuously synchronized copy of the root zone on disk at `/var/lib/unbound/root.zone`. With `for-upstream: yes` and `for-downstream: no`, this copy is used internally to speed up resolution and reduce load on the public root servers, but it is never served directly to clients as an authoritative answer.

### Recommended checks

Inspect the configuration:

```bash
cat /etc/unbound/unbound.conf
```

This configuration does not set a `username:` option, so Unbound runs as its built-in default user `unbound`, the same user created by the post-install script in step 7.

Confirm the `remote-control` key and certificate files exist, since they were expected to be created automatically in step 7:

```bash
ls -l /etc/unbound/unbound_server.key /etc/unbound/unbound_server.pem /etc/unbound/unbound_control.key /etc/unbound/unbound_control.pem
```

If any of them are missing, run `sudo unbound-control-setup` before starting the service.

Validate the syntax before starting the service:

```bash
sudo unbound-checkconf /etc/unbound/unbound.conf
```

If the command returns no output, the configuration is valid. Internally, `unbound-checkconf` exits with status code `0` for a correct configuration and status code `1` if an error was found. This exit code can be checked with `echo $?` right after running the command.

Also confirm that the file uses consistent indentation. Unbound's configuration parser tolerates both spaces and tabs, but a file that mixes them inconsistently is harder to edit safely later and can hide subtle mistakes; `unbound-checkconf` above is the authoritative check regardless of formatting style.

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

Check the service state and confirm the compiled feature set.

```bash
sudo systemctl status unbound
unbound -V
```

### Comment

`unbound -V` is useful for verifying that options such as `dnstap`, `cachedb`, `subnet`, and Python support were compiled in. This only confirms the feature was compiled into the binary; it does not confirm the feature is active, since some modules also require explicit settings in `unbound.conf`. In this setup, `cachedb` is a good example: it is compiled in, but its optional persistent cache backend is not enabled by the configuration. Unbound's regular in-memory caching is unaffected and works regardless.

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

## 12. Clean up <a id="step-12"></a>

Remove the downloaded source and extracted directories when the installation is complete.

```bash
cd $HOME
rm -rf unbound-*
```

### Comment

This keeps the home directory clean after installation.

## Additional recommendations <a id="recommendations"></a>

- Keep a backup of `/etc/unbound/unbound.conf` before replacing it.
- Confirm that port `5335` fits the local DNS design, especially when using AdGuard Home, Pi-hole, or another resolver.
- If Unbound should listen on port `53`, adjust the configuration accordingly.
- When pointing AdGuard Home or Pi-hole to this Unbound instance, set the upstream DNS server address explicitly. AdGuard Home expects `127.0.0.1:5335`, while Pi-hole expects `127.0.0.1#5335` in its custom upstream field, and all other upstream servers should be disabled to force traffic through Unbound.
- DNSSEC validation is already performed by Unbound itself. Do not enable a separate DNSSEC validation option in AdGuard Home or Pi-hole for this purpose, since neither tool re-validates the cryptographic signatures. In AdGuard Home, the "Enable DNSSEC" option only inspects and passes through the `ad` flag that Unbound already set; it does not perform its own validation and is not required for DNSSEC to work. In Pi-hole's default setup, leave DNSSEC validation off on that layer as well, since enabling it on both layers can lead to unnecessary double handling of the same flag rather than added protection.
- To confirm that DNSSEC validation is working end to end, query Unbound directly on port `5335`, as shown in [step 11](#step-11), rather than relying on a validation toggle in AdGuard Home or Pi-hole.
- Once `auto-trust-anchor-file` is configured, no periodic manual `unbound-anchor` runs are needed; Unbound tracks and updates the anchor on its own as long as the service can read and write the file.
- Regular caching is already active and tuned in this configuration through the in-memory cache settings; no action is needed to benefit from it. The `cachedb` module is compiled in but not active, and only relevant if a persistent, shared, or restart-surviving cache backend such as Redis is specifically desired. To enable it, add `cachedb` to `module-config` (for example `"validator cachedb iterator"`) and add a matching `cachedb:` block with backend settings.
- If TCP Fast Open is required in practice, check that the kernel parameter `net.ipv4.tcp_fastopen` is set to `3` (enables both client and server mode) with `sysctl net.ipv4.tcp_fastopen`. Compiling Unbound with `--enable-tfo-client --enable-tfo-server` alone does not enable TFO at the operating system level.
- The post-install script only creates the `unbound` user, required directories, service files, and remote control credentials if they do not already exist. If any of these were removed manually at some point, either re-run the script or recreate the missing item directly.
- Because `remote-control` is enabled with `control-interface: 127.0.0.1`, the control channel is only reachable from the local machine. Do not change this to a non-loopback address without adding proper access restrictions, since it grants administrative control over the resolver.
- The `auth-zone` block lists the root server addresses directly in the configuration. Since root server IP addresses can change over time, periodically compare them against the current root hints file distributed with the `dns-root-data` package.
- If Unbound is later configured to also listen on a non-loopback interface, for example to serve other devices on a local network, add an explicit `access-control: 0.0.0.0/0 refuse` (and the IPv6 equivalent) alongside a rule allowing the intended network range. This is not required for the loopback-only setup in this guide, but becomes relevant as soon as additional interfaces are added.
- Since the post-install script and configuration file are self-maintained rather than pulled from an upstream project, keep the copy in the `hagezi/files` repository in sync whenever this guide is updated, so the documented behavior continues to match what actually gets downloaded and executed.

## Optional: tune thread count <a id="tune-threads"></a>

This step is optional and can be performed at any time after installation, without repeating any earlier step. It does not change whether Unbound works, only how efficiently it uses the available hardware.

NLnet Labs recommends setting `num-threads` equal to the number of CPU cores on the system, since each thread can then run on its own core without competing for CPU time. The configuration installed in this guide uses `num-threads: 2`, which is a safe default but may be lower than the number of cores available on many ARM64 boards, such as a 4-core or 8-core Raspberry Pi.

1. Check how many CPU cores are available:

   ```bash
   nproc
   ```

2. Edit `/etc/unbound/unbound.conf` and set `num-threads` to that value, for example:

   ```
   num-threads: 4
   ```

3. When increasing `num-threads`, also increase the related `*-cache-slabs` settings (`msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs`, `infra-cache-slabs`) to reduce lock contention between threads. NLnet Labs' guidance is to use a power of two at or above the thread count, so for `num-threads: 4`, a value of `4` for each slab setting is a reasonable match; the configuration in this guide uses `2` for all four, matching the original `num-threads: 2`.

4. Validate and apply the change:

   ```bash
   sudo unbound-checkconf /etc/unbound/unbound.conf
   sudo systemctl restart unbound
   ```

On a system that is shared with other services, such as a Pi also running Pi-hole or AdGuard Home, leaving one core free for other workloads by setting `num-threads` slightly below the total core count is also a reasonable choice, rather than always maximizing it.

## Optional: logging behavior <a id="logging"></a>

This section explains what the configuration's logging settings actually do and clarifies why no separate log rotation setup is needed for the default behavior. No action is required to benefit from this; it is included to explain the existing `logfile: ""` and `verbosity: 1` settings and to describe what changes if a dedicated log file is used instead.

With `logfile: ""`, Unbound does not write to a file of its own. Log output goes to syslog instead, which on most current Debian- or Ubuntu-based systems means it ends up in the systemd journal. This has two practical consequences:

- Log rotation is already handled by journald's own retention settings, typically configured in `/etc/systemd/journald.conf` (for example `SystemMaxUse=`), rather than through a separate `logrotate` rule for Unbound. No Unbound-specific logrotate configuration needs to be created for this setup.
- Logs are viewed with `journalctl -u unbound`, as already used for troubleshooting in this guide, rather than by tailing a file under `/var/log/`.

If a dedicated log file is preferred instead, for example to keep Unbound's logs fully separate from the rest of the system journal, `logfile` can be set to a path such as `/var/log/unbound/unbound.log`. In that case, a `logrotate` configuration should be added for that file, and after each rotation, Unbound needs to release and reopen the file handle, which can be triggered without restarting the service:

```bash
sudo unbound-control log_reopen
```

Raising `verbosity` above the current value of `1` produces substantially more log output and is mainly useful for temporary debugging rather than continuous operation, since it increases both log volume and, at high settings, the load on the resolver itself.

## Optional: monitoring and statistics <a id="monitoring"></a>

This section is optional and builds on the `remote-control` interface that is already active after [step 7](#step-7) and [step 8](#step-8). No changes are required to the installation for basic statistics to work; the exporter setup described further down is an additional, separate step.

Unbound tracks internal counters, such as the number of queries, cache hits and misses, and average recursion time, and exposes them through `unbound-control`. Two related commands are available:

```bash
sudo unbound-control stats
sudo unbound-control stats_noreset
```

`stats` prints the current counters and then resets them to zero, useful for measuring activity over a fixed interval. `stats_noreset` prints the same counters without resetting them, which is generally the better choice for external monitoring tools that expect a continuously increasing counter, such as Prometheus.

By default, only aggregate counters are collected. To also break statistics down by query type and other details, add the following to `/etc/unbound/unbound.conf` and restart the service:

```
server:
    extended-statistics: yes
```

For dashboards or alerting, a small daemon can poll `unbound-control stats_noreset` and expose the result in a format tools like Prometheus understand. The `unbound_exporter` project maintained by Let's Encrypt is a commonly used option, and connects to the same `remote-control` interface already configured in this guide, without requiring any change to `control-enable`, `control-interface`, or `control-port`. Setting up such an exporter, and connecting it to a monitoring stack like Prometheus and Grafana, is beyond the scope of this installation guide, but no additional Unbound-side configuration beyond `extended-statistics` is required to make the underlying data available.

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
unbound -V

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

Re-running the post-install script during an update is optional, since it only touches files that do not already exist and will not overwrite the existing service definition, directories, or remote control credentials.

## Full installation command block <a id="full-command-block"></a>

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
unbound -V
sudo unbound-control status

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

### Note on this command block

The `unbound-anchor` line above uses `-u unbound`, since the configuration installed in this guide does not set a `username:` option and Unbound therefore runs as its built-in default user `unbound`, the same user the post-install script creates. If a different configuration is used instead, one that sets a custom `username:` value, run `unbound-anchor` as that user instead, or drop `-u unbound` entirely if `username: ""` is set to keep Unbound running as `root`.

`unbound-control-setup` is not called separately in this command block, because `post-install.sh` already runs it as part of its own steps, provided `/etc/unbound/unbound_control.key` did not already exist beforehand. Unlike the root key, the resulting files do not need to be owned by `unbound`, since Unbound reads them while still running as `root`, before dropping privileges.

The thread count is left at the configuration's default of `num-threads: 2` in this block. See [Optional: tune thread count](#tune-threads) to adjust it after installation. Logging and statistics are likewise left at their configured defaults; see [Optional: logging behavior](#logging) and [Optional: monitoring and statistics](#monitoring) for further, non-mandatory adjustments.

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

Note that this only applies to the root key file. The `remote-control` key files under `/etc/unbound/` are read by Unbound while it is still running as `root`, so they being owned by `root` is expected and not a cause of permission errors.

**Service fails to start because of the remote control interface**
This usually means the key and certificate files are missing entirely, for example because `post-install.sh` was not run, or was run before `unbound-control-setup` was available on the system. Generate them and restart:

```bash
sudo unbound-control-setup
sudo systemctl restart unbound
```

**DNSSEC test does not return the expected result**
If `dig +ad dnssec.works @127.0.0.1 -p 5335` does not return the `ad` flag, confirm that the root trust anchor file exists and is not empty, and that the system clock is correct, since DNSSEC signatures are time-sensitive. Re-running `sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key` and restarting the service is a safe first step.

**DNSSEC works on Unbound but not through AdGuard Home or Pi-hole**
This usually means the `ad` flag from Unbound is not being passed through by the layer in front of it. Query Unbound directly first, as in step 11, to confirm validation succeeds there. If it does, check that AdGuard Home or Pi-hole is actually configured to use Unbound as its only upstream, since a stripped or missing `ad` flag at the client is a display or forwarding issue rather than a sign that validation itself failed.

**Responses do not seem to be cached at all**
This would not be explained by `cachedb` being inactive, since regular in-memory caching runs independently of it and is enabled by default in this configuration. Check `msg-cache-size`, `rrset-cache-size`, and related settings in `unbound.conf` instead, and confirm the client is actually querying the same name and record type repeatedly within the record's TTL.

**A persistent or shared cache backend such as Redis does not seem to be used**
This is expected with the configuration used in this guide, since its `module-config` only lists `"validator iterator"` and does not include `cachedb`. To activate the optional `cachedb` module, add it to `module-config` (for example `"validator cachedb iterator"`) and add a `cachedb:` block with a valid backend. This is unrelated to regular in-memory caching, which is unaffected either way.

**Queries from other devices on the network are refused**
This is expected with the configuration used in this guide, since it listens only on `127.0.0.1` and only allows `127.0.0.0/8`. To serve other devices, add a listening interface for the local network and a matching `access-control` rule for that network's address range; do not simply widen `access-control` without also changing `interface`, since Unbound will still only be reachable on the interfaces it is bound to.

**CPU usage seems high, or resolution seems slower than expected under load**
Check whether `num-threads` is well matched to the number of available CPU cores, as described in [Optional: tune thread count](#tune-threads). A thread count far below the core count leaves capacity unused; a thread count far above it can cause unnecessary context switching.

**A log file grows without ever being rotated**
This only applies if `logfile` was changed from the default `""` to an actual file path. With the default, syslog and journald handle rotation automatically, as described in [Optional: logging behavior](#logging). If a dedicated log file is used instead, confirm a `logrotate` configuration exists for it, and that `unbound-control log_reopen` is triggered after each rotation so Unbound releases the old file handle.

**`unbound-control stats` or an exporter shows no data, or the connection is refused**
Confirm the `remote-control` key and certificate files exist and are valid, as described in [step 8](#step-8), and that `unbound-control status` succeeds first, as in [step 10](#step-10). If per-query-type detail is expected but missing, check that `extended-statistics: yes` has been added, as described in [Optional: monitoring and statistics](#monitoring); it is not part of the default configuration installed in this guide.

**Build fails during `./configure` or `make`**
Re-check that all packages from step 3 are installed. A failed `./configure` step usually names the missing library directly in its output.

## Glossary <a id="glossary"></a>

**Unbound**
A validating, recursive, and caching DNS resolver developed by NLnet Labs. It resolves DNS queries itself instead of simply forwarding them, and it supports native DNSSEC validation.

**ARM64 / AArch64**
The 64-bit version of the ARM processor architecture, used for example in the Raspberry Pi 3/4/5. AArch64 refers to the same architecture under its official ARM naming scheme.

**DNSSEC (Domain Name System Security Extensions)**
An extension of the DNS protocol that cryptographically signs responses. It allows a resolver to verify that a response actually originated from the authoritative server and was not tampered with. In this setup, Unbound is the only component performing that cryptographic validation.

**Chroot**
A security mechanism that confines a process to an isolated directory, preventing it from accessing the rest of the file system. In this guide, chroot is intentionally disabled, which simplifies setup but reduces process isolation.

**dnstap**
A binary protocol for logging DNS traffic. It allows query and response data to be recorded and forwarded to a separate analysis or logging system without placing heavy load on Unbound's performance.

**In-memory caching**
Unbound's built-in, default caching mechanism, which stores recently resolved messages, resource record sets, and DNSSEC keys directly in the daemon's memory. It is controlled by settings such as `msg-cache-size`, `rrset-cache-size`, and `key-cache-size`, and is active in this configuration without any extra setup. `prefetch` and `prefetch-key` extend this by refreshing popular cache entries before they expire, reducing the chance of a client ever waiting on a fresh lookup. This caching layer is entirely separate from the optional `cachedb` module described below; disabling or not using `cachedb` has no effect on it.

**cachedb / Redis**
An optional Unbound module that adds a second, persistent cache layer behind the built-in in-memory cache described above. If Unbound cannot find an answer in memory, it can query this backend, for example a Redis database, before falling back to a full resolution. Its main benefit is that the cache can survive a restart of Unbound or be shared between multiple Unbound instances, unlike the in-memory cache. Compiling Unbound with `--enable-cachedb` only makes the module available; it must additionally be listed in `module-config` (for example `"validator cachedb iterator"`) and configured with a `cachedb:` block before it does anything. The configuration used in this guide does not enable it, which only means this optional persistent layer is unused, not that caching in general is disabled.

**EDNS Client Subnet (ECS)**
An EDNS(0) option defined in RFC 7871 that lets a resolver forward part of the client's IP address to the authoritative server. This allows the server to return geographically closer responses, for example with content delivery networks. For privacy reasons, some operators, such as Cloudflare, do not support ECS.

**TCP Fast Open (TFO)**
A TCP extension that speeds up connection setup by allowing data to be sent in the very first handshake packet. This reduces latency for repeated connections to the same server. The `--enable-tfo-client` and `--enable-tfo-server` build options only compile in support; the operating system also needs the `net.ipv4.tcp_fastopen` kernel parameter set appropriately, typically to `3` for both client and server mode.

**num-threads**
The `unbound.conf` option that sets how many worker threads Unbound uses to process queries in parallel. NLnet Labs recommends matching this to the number of available CPU cores. Related settings such as `msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs`, and `infra-cache-slabs` divide the corresponding caches into that many (or more) independently locked segments, reducing contention between threads as the thread count increases.

**logfile**
The `unbound.conf` option that sets where log output is written. An empty value, `logfile: ""`, tells Unbound to send log output to syslog instead of a dedicated file, which on most current Linux systems means the output ends up in the systemd journal and is subject to journald's own retention and rotation settings rather than a separate `logrotate` rule.

**log_reopen**
An `unbound-control` command that tells Unbound to close and reopen its log output. It is mainly useful after a log file has been rotated by an external tool such as `logrotate`, so Unbound releases the old file handle and continues writing to the new one instead of the now-renamed file. It has no relevant effect when logging through syslog, since syslog handles this internally.

**extended-statistics**
An `unbound.conf` option that, when set to `yes`, makes Unbound collect more detailed statistics, such as counts broken down by query type, in addition to the basic aggregate counters that are always collected. It is not enabled in the configuration used in this guide and is only needed for more detailed monitoring.

**stats / stats_noreset**
Two related `unbound-control` commands that print Unbound's internal performance counters, such as query counts, cache hit rates, and average recursion time. `stats` resets the counters to zero after printing them, while `stats_noreset` leaves them unchanged, which is generally preferred when an external monitoring system is expected to track continuously increasing values over time.

**unbound_exporter**
A third-party Prometheus metrics exporter, maintained by Let's Encrypt, that connects to Unbound's `remote-control` interface, retrieves statistics with `stats_noreset`, and exposes them in a format Prometheus can scrape. It reuses the same `remote-control` settings already configured in this guide and does not require changes to `control-enable`, `control-interface`, or `control-port`.

**systemd integration**
Unbound's ability to hook into the Linux init and service manager systemd, for example through socket activation or status notifications sent to the service supervisor. In practice, this also covers the startup sequence: systemd starts Unbound as `root`, Unbound reads privileged files and binds its listening ports, and only then drops down to the unprivileged `username:` account.

**post-install.sh**
A self-maintained shell script, hosted in the `hagezi/files` repository, that automates several setup tasks after compiling Unbound: creating the `unbound` system user and group, creating `/var/lib/unbound` with correct ownership, installing an init script, a systemd unit, and a helper script, and generating the `remote-control` key and certificate files. Each action only runs if its target does not already exist, so re-running the script is safe. It does not create or manage the DNSSEC root trust anchor.

**Root key / trust anchor**
The public cryptographic key of the DNS root zone. It forms the trust anchor for the entire DNSSEC validation chain and is required by Unbound to verify signatures all the way up to the root of the DNS tree. Unlike the remote control key files, this file is read and periodically rewritten by Unbound after it has already dropped privileges to the `unbound` user, so it must be owned by that user specifically. Neither Unbound itself nor the `post-install.sh` script used in this guide creates it automatically, so it must be created explicitly with `unbound-anchor` once, before the first start.

**auto-trust-anchor-file**
The `unbound.conf` option that tells Unbound where to find and continuously update its DNSSEC root trust anchor. Once set, Unbound tracks anchor changes automatically through periodic RFC 5011 checks, so the file only needs to be created once, not maintained manually afterward.

**username (unbound.conf option)**
The `unbound.conf` setting that defines which unprivileged system user Unbound switches to after binding its listening sockets and reading its startup files. If the option is left out of the configuration entirely, Unbound falls back to its built-in default, the user `unbound`. Files that Unbound needs to read or write on an ongoing basis while running as this unprivileged user, such as the root key file, must be owned by it, or the service fails with a permission error; files only read once at startup while Unbound is still root do not have this requirement.

**module-config**
The `unbound.conf` option that defines which processing modules are active and in what order, for example `"validator iterator"`. A module that was compiled into the Unbound binary, such as `cachedb`, still does nothing at runtime unless its name is also listed here. This setting does not control Unbound's regular in-memory caching, which is always available regardless of which modules are listed.

**access-control**
The `unbound.conf` option that determines which client IP ranges may query Unbound, using actions such as `allow`, `refuse`, or `deny`. Unbound's built-in default is to allow only localhost and refuse everything else, even without any `access-control` line present; this configuration adds an explicit `127.0.0.0/8 allow` rule that matches that default. Adding a broader interface later without a matching, deliberately scoped `access-control` rule is a common way to unintentionally expose a resolver to unwanted queries.

**qname-minimisation**
A DNS privacy feature defined in RFC 7816. Instead of sending the full domain name to every server in the resolution chain, Unbound sends only the minimum number of labels each server actually needs to answer, reducing how much of a query is exposed to intermediate and root-level servers.

**harden-algo-downgrade**
An `unbound.conf` option that controls how strictly Unbound treats DNSSEC algorithm agility. When set to `yes`, Unbound requires validation to succeed with the strongest algorithm a zone advertises; when set to `no`, as in this configuration, validation can also succeed using a weaker advertised algorithm, which improves compatibility with zones that publish mixed-strength signatures at the cost of some strictness.

**remote-control**
A `unbound.conf` section that enables the `unbound-control` utility to manage a running Unbound instance, for example to query status, reload configuration, or flush the cache. It requires cryptographic keys and certificates, in this guide generated automatically by the `post-install.sh` script, before the service can start successfully with `control-enable: yes`. It also forms the basis for optional external monitoring, as described in [Optional: monitoring and statistics](#monitoring).

**unbound-control**
A command-line tool for interacting with a running Unbound daemon over its remote control interface, for example `unbound-control status`, `unbound-control reload`, or `unbound-control stats_noreset`. It depends on the `remote-control` section being correctly configured and initialized.

**unbound-control-setup**
A command-line tool that generates the key and certificate files needed for the `remote-control` interface: `unbound_server.key`, `unbound_server.pem`, `unbound_control.key`, and `unbound_control.pem`. In this guide, it is run automatically by `post-install.sh`, so no separate manual invocation is normally required.

**auth-zone**
A `unbound.conf` section that keeps a local, file-based copy of a DNS zone, most commonly the root zone. With `for-upstream: yes` and `for-downstream: no`, Unbound uses this local copy internally while resolving queries, which reduces traffic to the public root servers, but does not serve the zone data directly to clients as an authoritative answer. This corresponds to the setup described in RFC 8806.

**Port 5335**
An alternative, non-standard port for DNS queries. It is used in this guide so that Unbound can run alongside another DNS service, such as AdGuard Home or Pi-hole, on port 53 without causing conflicts.

**AD flag (Authenticated Data)**
A flag in DNS responses indicating that the resolver, in this setup Unbound, successfully validated the response using DNSSEC. It only appears when the query is made with the `+ad` option and validation succeeded. Tools placed in front of Unbound, such as AdGuard Home or Pi-hole, can only pass this flag along or strip it; they do not generate it themselves.

**SERVFAIL**
A DNS response code indicating a server failure. In the context of DNSSEC, it typically occurs when signature validation fails, for example because a domain is intentionally configured with an invalid signature.

**unbound-checkconf**
A command-line tool that checks the syntax of the Unbound configuration file before the service is started or reloaded. It exits with status code `0` for a valid configuration and status code `1` if an error was found, and it normally prints no output on success.

**unbound-anchor**
A command-line tool that sets up or updates the DNSSEC root trust anchor. If the target file does not exist or is empty, it writes a built-in starting key to it; if a valid anchor already exists, it verifies and updates it as needed. It should be run as the same system user Unbound uses at runtime, so the resulting file has the correct owner, and it is intended to run once before the first start of the service.

**CFLAGS**
An environment variable that passes compiler flags to the build process. Setting `CFLAGS="-O2"` tells the compiler to apply a moderate level of optimization, balancing build time against runtime performance of the resulting binary.

**libevent**
A C library that provides an event notification mechanism used by Unbound to handle many simultaneous network connections efficiently, without needing a separate thread for each one.

**libhiredis**
A minimalistic C client library for Redis. Unbound links against it when the `cachedb` module is compiled with Redis support, since it provides the low-level functions needed to talk to a Redis server.

**libnghttp2**
A library implementing the HTTP/2 protocol. Unbound uses it to support DNS-over-HTTPS (DoH) queries, which carry DNS traffic inside encrypted HTTP/2 connections.

**HTTP/2**
A major revision of the HTTP protocol that allows multiplexed requests over a single connection. In the context of Unbound, it is the transport layer that enables DNS-over-HTTPS, letting DNS queries travel alongside regular encrypted web traffic.

**./configure**
The standard script used in source-based builds to detect the system environment and generate a `Makefile`. Its flags, such as `--prefix`, `--sysconfdir`, or `--localstatedir`, define where Unbound and its supporting files will be installed.

**--prefix**
A `./configure` option that sets the base installation directory for the compiled software. In this guide it is set to `/usr`, so binaries end up in paths such as `/usr/sbin`.

**--sysconfdir**
A `./configure` option that sets the directory for configuration files. Here it points to `/etc`, which is why the final configuration lives at `/etc/unbound/unbound.conf`.

**--localstatedir**
A `./configure` option that sets the directory for variable runtime data, such as PID files or the root key. In this guide it points to `/var`.

**pyunbound / pythonmodule**
Two related but distinct Python integration options. `--with-pythonmodule` compiles a scripting hook that lets Unbound run custom Python code during query processing, while `--with-pyunbound` builds a separate Python library for writing standalone applications that use Unbound's resolving engine.

**journalctl**
A command-line tool for reading the systemd journal, the central log storage used by services such as Unbound. Running `journalctl -u unbound -b` shows log entries for the Unbound service from the current boot, which helps diagnose startup failures.

**dig**
A command-line utility for querying DNS servers directly. It is used in this guide to send test queries to the local Unbound instance and inspect the raw response, including flags like `ad` or status codes like `SERVFAIL`.

**Upstream DNS server**
The DNS server that another resolver or ad-blocking tool, such as AdGuard Home or Pi-hole, forwards its queries to. In this guide, Unbound acts as the upstream server for those tools, listening on `127.0.0.1` at port `5335`. Because Unbound already validates DNSSEC, the upstream relationship is one-directional: the tool in front of Unbound trusts the validation result it receives, it does not repeat it.

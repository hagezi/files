# Unbound Installation (ARM64/AArch64)

This guide walks you through building **Unbound 1.26.2** from source on an **ARM64 / AArch64** machine running Debian or Ubuntu, a Raspberry Pi for example.

After the build you run a small post-install script, drop in a ready-made configuration and check that DNSSEC works.

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

- You need a 64-bit ARM Linux system and `sudo` access.
- Unbound listens on **port 5335** here, so it can run next to something else that already uses port 53 (Pi-hole, AdGuard Home and so on).
- You can go through steps 1 to 12 one by one. If you'd rather paste everything at once, the [Full installation command block](#full-command-block) near the end has the same commands in one list.
- Unbound only listens on `127.0.0.1`. Its default access control lets localhost (`127.0.0.0/8`) in and refuses everyone else. The `access-control` entry in the glossary has the details.
- An `auth-zone` block keeps a local copy of the DNS root zone and keeps it up to date, so Unbound has to ask the public root servers a lot less often.
- The configuration sets `num-threads: 2`. To match it to your hardware, see [Optional: tune thread count](#tune-threads).
- There's no `logfile` setting, so Unbound logs to syslog (its default) and not to a file of its own. More on that in [Optional: logging behavior](#logging).
- The configuration follows the RFCs, with four deliberate exceptions marked `DEVIATION` in the file. It also has DNS rebinding protection, with a few optional exceptions you can switch on. See [step 8](#step-8).
- You need at least Unbound 1.20 for this configuration. Better use the latest release, at least 1.25.2.
- If you don't want Unbound to resolve from the root itself, use `server-forwarder.conf` instead of `server.conf`. It sends all queries encrypted (DNS over TLS) to Quad9. Where this changes things, [step 7](#step-7), [step 8](#step-8) and [step 11](#step-11) tell you.

## 1. Update the system <a id="step-1"></a>

Go to your home directory and bring the system up to date.

```bash
cd $HOME

# Update package lists, upgrade packages, remove obsolete packages, and clean the cache
sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

## 2. Remove an existing Unbound package <a id="step-2"></a>

If you installed Unbound from your distro's repository before, remove it first so the two don't get in each other's way.

```bash
# Remove the distro-provided Unbound package and related unused dependencies
sudo apt --purge autoremove unbound -y
```

## 3. Install build dependencies <a id="step-3"></a>

This installs the compiler toolchain, the development libraries and a few helper tools. Don't skip `pkg-config`: systemd support (`--enable-systemd`) needs it, and without it `./configure` stops with an error.

```bash
sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev pkg-config protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y
```

## 4. Download and extract Unbound <a id="step-4"></a>

Grab the source archive, check it and unpack it.

```bash
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz.sha256
[ "$(sha256sum unbound-1.26.2.tar.gz | cut -d' ' -f1)" = "$(cut -d' ' -f1 unbound-1.26.2.tar.gz.sha256)" ] && echo "Checksum OK" || echo "Checksum FAILED"
tar -xvzf unbound-1.26.2.tar.gz
cd unbound-1.26.2/
```

### Good to know

The checksum line has to print `Checksum OK`. If it prints anything else, the download is broken or someone messed with it. Delete it and stop here.

This guide uses version `1.26.2`. Unbound ships security releases pretty regularly, so have a look at https://nlnetlabs.nl/projects/unbound/download/ first. If there's a newer version, use it and change the version number in the URLs and the directory name.

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

Got more than one core? This builds faster:

```bash
make -j"$(nproc)"
```

## 7. Run the post-install package <a id="step-7"></a>

Download the post-install archive, unpack it and run the script.

```bash
wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh
```

### What the script does

1. Creates the `unbound` system user and group.
2. Creates `/var/lib/unbound` with the right owner.
3. Installs the init script, the systemd unit and a helper script, so Unbound can run as a service.
4. Generates the key and certificate files for `remote-control`, which the configuration in [step 8](#step-8) uses.

You can run it as often as you like, nothing breaks.

### Create the DNSSEC root key

With `server.conf`, Unbound needs one more file before it starts: the DNSSEC root trust anchor at `/var/lib/unbound/root.key`. Using `server-forwarder.conf`? Then you don't need this file and can skip this part.

Run this once:

```bash
sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key
```

`unbound-anchor` exits with `1` when it created or updated the file, and with `0` when there was nothing to update. Both are fine.

Now check that the root key is in there:

```bash
grep "DNSKEY 257" /var/lib/unbound/root.key
```

You should see at least one line that starts with `.` and contains `DNSKEY 257` (that's the key signing key of the root zone). If so, you're good.

## 8. Install the configuration file <a id="step-8"></a>

Go back to your home directory, download the configuration and put it in place.

```bash
cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
```

### Using the forwarder instead

Download `server-forwarder.conf` and move it to the same spot:

```bash
cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server-forwarder.conf
sudo mv server-forwarder.conf /etc/unbound/unbound.conf
```

### What's in server.conf

The downloaded file replaces Unbound's main configuration. A few things in `server.conf` you should know about:

- `msg-cache-size: 128m` and `rrset-cache-size: 256m` set how big Unbound's cache is.
- `module-config: "validator iterator"` turns on DNSSEC validation and recursive resolution.
- A bunch of privacy and security options are already set to sensible values. Unbound gives away less about you to other servers and holds up better against common attacks. Each option has a comment with the RFC it's based on, and the four deliberate deviations are marked `DEVIATION`.
- `interface: 127.0.0.1` plus Unbound's default access control means only your own machine can ask Unbound anything. The `access-control` glossary entry explains this a bit more.
- DNS rebinding protection (`private-address`) strips private and special-use addresses out of public answers. Some services need an exception, like DNS blocklists for mail servers, Wi-Fi calling or Plex. They're already in the file as commented-out `private-domain` lines. Just remove the `#` in front of the ones you need.
- A `remote-control:` section lets `unbound-control` manage the running service, using the files from [step 7](#step-7).
- An `auth-zone:` section keeps a local copy of the DNS root zone, which makes lookups faster.

### Set the socket buffer limits

`server.conf` uses a 4 MB receive buffer (`so-rcvbuf`), and Unbound uses a 4 MB send buffer by default. When systemd starts Unbound as root, Unbound sets these buffers itself. Without root (in a container, say), the kernel limits win: Unbound logs a warning and falls back to smaller buffers. Setting the limits permanently fixes that, and it doesn't hurt if you never need it:

```bash
printf 'net.core.rmem_max = 4194304\nnet.core.wmem_max = 4194304\n' | sudo tee /etc/sysctl.d/99-unbound.conf
sudo sysctl --system
```

### Quick checks before you start it

Take a look at the configuration:

```bash
cat /etc/unbound/unbound.conf
```

Make sure the `remote-control` files from step 7 are there:

```bash
ls -l /etc/unbound/unbound_server.key /etc/unbound/unbound_server.pem /etc/unbound/unbound_control.key /etc/unbound/unbound_control.pem
```

If one of them is missing, run `sudo unbound-control-setup` before you start the service.

Check the syntax:

```bash
sudo unbound-checkconf /etc/unbound/unbound.conf
```

If everything's fine, you'll see `unbound-checkconf: no errors in /etc/unbound/unbound.conf`. If not, it tells you what's wrong and where.

## 9. Enable and start the service <a id="step-9"></a>

Make Unbound start at boot and start it right now.

```bash
sudo systemctl enable unbound
sudo systemctl start unbound
```

If it doesn't come up, the logs usually tell you why:

```bash
sudo journalctl -u unbound -b
```

## 10. Verify the installation <a id="step-10"></a>

Check that the service is running.

```bash
sudo systemctl status unbound
```

And check that the remote control interface from step 7 answers:

```bash
sudo unbound-control status
```

## 11. Test DNSSEC <a id="step-11"></a>

Now ask your local resolver on port `5335` two things: one domain that should fail DNSSEC, and one that should pass.

```bash
dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335
```

### What you should see

- `fail01.dnssec.works` returns `SERVFAIL`. The domain is broken on purpose, so validation has to fail.
- `dnssec.works` with `+ad` comes back with the `ad` flag set. That means DNSSEC validation worked.

If you get both, you're done and everything works.

With `server-forwarder.conf`, Quad9 does the DNSSEC validation. `fail01.dnssec.works` still returns `SERVFAIL`, but `dnssec.works` comes back without the `ad` flag, because your Unbound doesn't validate on its own. A `NOERROR` answer with an IP address means it's working.

## 12. Clean up <a id="step-12"></a>

Delete the downloaded source and the unpacked folders.

```bash
cd $HOME
rm -rf unbound-*
```

## Additional recommendations <a id="recommendations"></a>

- Make sure port `5335` fits your DNS setup, especially if AdGuard Home, Pi-hole or another resolver is in the mix.
- When you point AdGuard Home or Pi-hole at this Unbound, enter the upstream address by hand. AdGuard Home wants `127.0.0.1:5335`, Pi-hole wants `127.0.0.1#5335` in its custom upstream field. Turn off all other upstream servers so every query goes through Unbound.
- Don't turn on DNSSEC validation in AdGuard Home or Pi-hole as well. AdGuard Home's "Enable DNSSEC" only looks at the `ad` flag Unbound already set and passes it on, it doesn't validate anything itself. In Pi-hole's default setup, leave DNSSEC validation off on that layer too.
- To check that DNSSEC works all the way through, ask Unbound directly on port `5335`, like in [step 11](#step-11).
- `remote-control` runs with `control-interface: 127.0.0.1`, so only the local machine can reach it. Keep it that way. Anyone who can reach the control channel can run your resolver, so never put it on a non-loopback address without proper access restrictions.
- The `auth-zone` block in `server.conf` lists the addresses of the root servers that allow zone transfers (b, c, d, f, g, h, k) and of ICANN's transfer servers right in the configuration. These addresses can change. Every now and then, compare the root server addresses with the root hints file from the `dns-root-data` package, and the whole list with the `auth-zone` example in the `example.conf` of the current Unbound release. If none of the listed servers can be reached, `fallback-enabled: yes` makes sure Unbound keeps resolving as usual.
- If you later let Unbound listen on a non-loopback interface too, for example to serve other devices on your LAN, add an explicit `access-control: 0.0.0.0/0 refuse` (plus the IPv6 version) and a rule that allows the network you actually want.

## Optional: tune thread count <a id="tune-threads"></a>

NLnet Labs recommends setting `num-threads` to the number of CPU cores. That way every thread gets its own core and they don't fight over CPU time. This guide's configuration uses `num-threads: 2`, which is less than many ARM64 boards have (a Raspberry Pi with 4 or 8 cores, for example).

1. Check how many cores you have:

   ```bash
   nproc
   ```

2. Open `/etc/unbound/unbound.conf` and set `num-threads` to that number, for example:

   ```
   num-threads: 4
   ```

3. The related `*-cache-slabs` settings (`msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs`, `infra-cache-slabs`) aren't set in the configuration. Unbound picks them automatically: a power of two, at least 4, matching `num-threads` (4 for up to 5 threads, 8 for 6 to 10 threads). You don't need to touch anything else.

   `server-forwarder.conf` is different. It uses one thread on purpose (fewer TLS connections that get reused more) and sets `msg-cache-slabs`, `rrset-cache-slabs` and `infra-cache-slabs` to `1`. If you raise `num-threads` there, delete those three lines.

4. Check and apply the change:

   ```bash
   sudo unbound-checkconf /etc/unbound/unbound.conf
   sudo systemctl restart unbound
   ```

If the machine also runs other stuff, like a Pi with Pi-hole or AdGuard Home on it, it's totally fine to set `num-threads` a little below the core count and leave one core free.

## Optional: logging behavior <a id="logging"></a>

Without a `logfile` setting, Unbound logs to syslog. On most current Debian and Ubuntu systems that ends up in the systemd journal, and you can read it with `journalctl -u unbound`. journald takes care of log rotation for you.

If you'd rather have a separate log file, set `logfile` to a path like `/var/log/unbound/unbound.log`. Then you also need a `logrotate` configuration for that file, and after each rotation Unbound has to let go of the old file and open the new one:

```bash
sudo unbound-control log_reopen
```

## Optional: monitoring and statistics <a id="monitoring"></a>

Unbound keeps internal counters, like how many queries it answered and how many came from the cache. You can read them with `unbound-control`:

```bash
sudo unbound-control stats_noreset
```

That prints the current counters and leaves them as they are.

`extended-statistics: yes` is already on in the configuration, so you also get the numbers broken down by query type, reply code and more.

Want dashboards or alerts? A small daemon can poll `unbound-control stats_noreset` and hand the numbers to something like Prometheus. A popular choice is `unbound_exporter`, maintained by Let's Encrypt. It works with the `remote-control` setup you already have from this guide.

## Update Unbound <a id="update"></a>

You built Unbound from source, so `apt` won't update it. Rebuild it whenever a new release or security fix comes out. Security releases are announced at https://nlnetlabs.nl/projects/unbound/security-advisories/.

To upgrade an Unbound you installed with this guide, repeat steps 4 to 6 with the new version and restart the service:

```bash
cd $HOME

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz.sha256
[ "$(sha256sum unbound-1.26.2.tar.gz | cut -d' ' -f1)" = "$(cut -d' ' -f1 unbound-1.26.2.tar.gz.sha256)" ] && echo "Checksum OK" || echo "Checksum FAILED"
tar -xvzf unbound-1.26.2.tar.gz
cd unbound-1.26.2/

export CFLAGS="-O2"
./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
make
sudo make install

sudo unbound-checkconf /etc/unbound/unbound.conf && sudo systemctl restart unbound

sudo systemctl status unbound

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

## Full installation command block <a id="full-command-block"></a>

Everything from steps 1 to 12 in one go, ready to copy and run. Keep an eye on the checksum line: if it says `Checksum FAILED`, stop right there.

```bash
cd $HOME

sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
sudo apt --purge autoremove unbound -y

sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev pkg-config protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.26.2.tar.gz.sha256
[ "$(sha256sum unbound-1.26.2.tar.gz | cut -d' ' -f1)" = "$(cut -d' ' -f1 unbound-1.26.2.tar.gz.sha256)" ] && echo "Checksum OK" || echo "Checksum FAILED"
tar -xvzf unbound-1.26.2.tar.gz
cd unbound-1.26.2/

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

printf 'net.core.rmem_max = 4194304\nnet.core.wmem_max = 4194304\n' | sudo tee /etc/sysctl.d/99-unbound.conf
sudo sysctl --system

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

**Service won't start**
Run `sudo journalctl -u unbound -b` and read the exact error. Usually it's a syntax error in `/etc/unbound/unbound.conf` that slipped past `unbound-checkconf`, or another resolver already sitting on the configured port.

**`unbound-checkconf` reports an error**
Open `/etc/unbound/unbound.conf` at the line from the error message. Every option has to be in the right section (`server:`, `remote-control:`, `auth-zone:`, or `forward-zone:` in `server-forwarder.conf`). An option your installed version doesn't know also shows up as a syntax error (the version notes at the top of the file tell you what needs which version). And check that the paths the file points to, like the root key file, really exist.

**Permission error on the root key file**
Most of the time the file doesn't belong to the `unbound` user. Compare the owner with the user:

```bash
ls -l /var/lib/unbound/root.key
id unbound
```

If it belongs to `root` or someone else, fix it:

```bash
sudo chown unbound:unbound /var/lib/unbound/root.key
```

**Service won't start because of the remote control interface**
Usually the key and certificate files just aren't there, for example because `post-install.sh` never ran, or ran before `unbound-control-setup` was on the system. Create them and restart:

```bash
sudo unbound-control-setup
sudo systemctl restart unbound
```

**DNSSEC test doesn't give the expected result**
With `server.conf`: if `dig +ad dnssec.works @127.0.0.1 -p 5335` comes back without the `ad` flag, check that the root trust anchor file exists and isn't empty, and that the system clock is right. DNSSEC signatures depend on the time. Running `sudo -u unbound unbound-anchor -a /var/lib/unbound/root.key` again and restarting the service is a safe thing to try first. With `server-forwarder.conf`, no `ad` flag is normal (see [step 11](#step-11)).

**Other devices on the network get refused**
That's on purpose. The configuration only listens on `127.0.0.1`, and Unbound's default access control only lets `127.0.0.0/8` in. To serve other devices, add a listening interface on your LAN and an `access-control` rule for that network's address range.

**`unbound-control stats` or an exporter shows nothing, or the connection is refused**
Check that the `remote-control` key and certificate files exist and are valid ([step 8](#step-8)), and that `unbound-control status` works ([step 10](#step-10)). If the per-query-type numbers are missing, make sure `extended-statistics: yes` is still in the configuration.

**Build fails during `./configure` or `make`**
Check again that every package from step 3 is installed. When `./configure` fails, it usually names the missing library right in its output.

## Glossary <a id="glossary"></a>

**Unbound**
A validating, recursive and caching DNS resolver by NLnet Labs. It resolves DNS queries itself instead of just passing them on, and it validates DNSSEC natively.

**ARM64 / AArch64**
The 64-bit version of the ARM processor architecture, found for example in the Raspberry Pi 3/4/5. AArch64 is ARM's official name for the same thing.

**DNSSEC (Domain Name System Security Extensions)**
An extension to DNS that signs answers cryptographically. A resolver can check that an answer really came from the authoritative server and nobody changed it on the way.

**num-threads**
The `unbound.conf` option for how many worker threads handle queries in parallel. Related settings like `msg-cache-slabs`, `rrset-cache-slabs`, `key-cache-slabs` and `infra-cache-slabs` split the matching caches into segments that are locked separately. If you don't set them, Unbound uses a power of two, at least 4, that matches `num-threads`.

**logfile**
The `unbound.conf` option for where logs go. Leave it out or set it empty (`logfile: ""`) and Unbound logs to syslog instead of its own file.

**log_reopen**
An `unbound-control` command that makes Unbound close and reopen its log output. You mostly need it after a tool like `logrotate` has rotated a separate log file.

**extended-statistics**
An `unbound.conf` option. Set it to `yes` and Unbound collects more detailed statistics, like counts per query type.

**stats_noreset**
An `unbound-control` command that prints Unbound's internal counters, like query counts and cache hit rates, without resetting them.

**unbound_exporter**
A third-party Prometheus exporter maintained by Let's Encrypt. It talks to Unbound's `remote-control` interface and makes the statistics available to Prometheus.

**systemd integration**
Unbound's support for systemd, the Linux init and service manager, switched on with `--enable-systemd`. Unbound tells systemd when it's ready to answer queries, so services ordered after `unbound.service` only start then. Separately from that, Unbound starts as `root`, reads privileged files, binds its ports and then switches to the unprivileged `unbound` user.

**post-install.sh**
A shell script in the `hagezi/files` repository. It creates the `unbound` system user, the `/var/lib/unbound` directory, the init script and systemd unit, and the `remote-control` key and certificate files.

**Root key / trust anchor**
The public key of the DNS root zone. The whole DNSSEC validation chain is built on it. You create it with `unbound-anchor`, and it lives at `/var/lib/unbound/root.key`, owned by the `unbound` user.

**auto-trust-anchor-file**
The `unbound.conf` option that tells Unbound where its DNSSEC root trust anchor is and keeps it updated.

**module-config**
The `unbound.conf` option that sets which processing modules run, for example `"validator iterator"` for DNSSEC validation plus recursive resolution.

**access-control**
The `unbound.conf` option that decides which client IP ranges may ask Unbound anything, with actions like `allow`, `refuse` or `deny`. Without it, Unbound only allows localhost (`127.0.0.0/8`) and refuses everyone else.

**remote-control**
An `unbound.conf` section that lets `unbound-control` manage a running Unbound, for example to check its status or flush the cache. It needs the key and certificate files that `post-install.sh` creates.

**unbound-control**
A command-line tool for talking to a running Unbound through its remote control interface, for example `unbound-control status` or `unbound-control stats_noreset`.

**unbound-control-setup**
A command-line tool that generates the key and certificate files for the `remote-control` interface.

**auth-zone**
An `unbound.conf` section that keeps a local, file-based copy of a DNS zone. Most of the time that's the root zone, to make lookups faster.

**Port 5335**
A non-standard port for DNS queries. It's used here so Unbound can run next to another DNS service on port 53.

**AD flag (Authenticated Data)**
A flag in DNS answers that says the resolver validated the answer with DNSSEC. The resolver only sets it if the query had the AD or DO bit set (RFC 6840). `dig` sets the AD bit by default, `+ad` just makes it explicit.

**SERVFAIL**
A DNS response code for a server failure. With DNSSEC it usually means signature validation failed.

**unbound-checkconf**
A command-line tool that checks the syntax of the Unbound configuration file. For a valid file it prints `no errors in` and the file name.

**unbound-anchor**
A command-line tool that sets up or updates the DNSSEC root trust anchor.

**CFLAGS**
An environment variable that passes flags to the compiler. `CFLAGS="-O2"` turns on a moderate level of optimization.

**./configure**
The usual script in source builds. It looks at your system and generates a `Makefile`.

**journalctl**
A command-line tool for reading the systemd journal. `journalctl -u unbound -b` shows the Unbound log entries since the last boot.

**dig**
A command-line tool that sends queries straight to a DNS server. This guide uses it to test the local Unbound.

**Upstream DNS server**
The DNS server that another resolver or ad blocker, like AdGuard Home or Pi-hole, sends its queries to. Here, Unbound is that upstream server, on `127.0.0.1` port `5335`.

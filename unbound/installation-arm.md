# Unbound Installation on ARM

This README explains how to install and compile **Unbound 1.25.0** from source on an **ARM64 / AArch64** Debian- or Ubuntu-based system.

It also includes a post-install step, a custom configuration, and basic verification commands for DNSSEC.

## Notes

- This guide assumes a 64-bit ARM Linux system.
- `sudo` access is required.
- The configuration shown here uses **port 5335**, which is useful when another DNS service is already listening on port 53.
- Some files in this workflow are downloaded from third-party sources. Review them before executing them in production.

## 1. Update the system

Start in the home directory and bring the system fully up to date.

```bash
cd $HOME

# Update package lists, upgrade packages, remove obsolete packages, and clean the cache
sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

### Comment

This reduces the chance of build problems caused by outdated packages or dependency mismatches.

## 2. Remove an existing Unbound package

If Unbound was previously installed from the distribution repository, remove it first to avoid conflicts.

```bash
# Remove the distro-provided Unbound package and related unused dependencies
sudo apt --purge autoremove unbound -y
```

### Comment

This helps prevent conflicts between repository binaries and the custom version built from source.

## 3. Install build dependencies

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

## 4. Download and extract Unbound

Download the source archive and unpack it.

```bash
wget https://nlnetlabs.nl/downloads/unbound/unbound-1.25.0.tar.gz
tar -xvzf unbound-1.25.0.tar.gz
cd unbound-1.25.0/
```

### Comment

This guide is pinned to version `1.25.0`. If a newer release is preferred, replace the version number in both the URL and directory name.

### Recommended check

Before building, verify the official checksum or signature from NLnet Labs.

## 5. Configure the build

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

### Security note

The option `--with-chroot-dir=` disables chrooting. That can simplify integration, but it is less restrictive than running Unbound inside a chroot.

## 6. Compile and install

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

## 7. Run the post-install package

Download the additional post-install archive, extract it, and execute the script.

```bash
wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh
```

### Comment

This step may install supporting files such as:

- service definitions
- runtime directories
- permissions
- root key handling
- integration files

### Important

Because this script is hosted in a third-party repository, inspect it before running it:

```bash
cat post-install.sh
```

## 8. Install the configuration file

Return to the home directory, download the provided configuration, and move it into place.

```bash
cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf
```

### Comment

This replaces the main Unbound configuration with the downloaded file.

### Recommended checks

Inspect the configuration:

```bash
cat /etc/unbound/unbound.conf
```

Validate the syntax before starting the service:

```bash
sudo unbound-checkconf /etc/unbound/unbound.conf
```

If the command returns no output, the configuration is valid.

## 9. Enable and start the service

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

## 10. Verify the installation

Check the service state and confirm the compiled feature set.

```bash
sudo systemctl status unbound
unbound -V
```

### Comment

`unbound -V` is useful for verifying that options such as `dnstap`, `cachedb`, `subnet`, and Python support were compiled in.

## 11. Test DNSSEC

Run a negative DNSSEC test and then a positive validation test against the local resolver on port `5335`.

```bash
dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335
```

### Expected result

- `fail01.dnssec.works` should return `SERVFAIL`, because the domain is intentionally broken and validation should fail.
- `dnssec.works` queried with `+ad` should return the `ad` flag, which indicates successful DNSSEC validation.

## 12. Clean up

Remove the downloaded source and extracted directories when the installation is complete.

```bash
cd $HOME
rm -rf unbound-*
```

### Comment

This keeps the home directory clean after installation.

## Additional recommendations

- Keep a backup of `/etc/unbound/unbound.conf` before replacing it.
- Confirm that port `5335` fits the local DNS design, especially when using AdGuard Home, Pi-hole, or another resolver.
- If Unbound should listen on port `53`, adjust the configuration accordingly.

## Update Unbound

Because Unbound was installed from source, it will not receive updates through `apt`. Rebuild it whenever a new upstream release or security patch becomes available.       
                   
If you previously installed an older Unbound version using this guide and want to upgrade to a newer source release, repeat steps 4 through 6, then restart the Unbound service:

```bash
cd $HOME

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.25.0.tar.gz
tar -xvzf unbound-1.25.0.tar.gz
cd unbound-1.25.0/

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

rm -rf unbound-*
```

## Full installation command block

```bash
cd $HOME

sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
sudo apt --purge autoremove unbound -y

sudo apt install bison flex libevent-dev libexpat1-dev libhiredis-dev libnghttp2-dev libprotobuf-c-dev libssl-dev libsystemd-dev protobuf-c-compiler python3-dev swig build-essential python-is-python3 dns-root-data dnsutils wget curl -y

wget https://nlnetlabs.nl/downloads/unbound/unbound-1.25.0.tar.gz
tar -xvzf unbound-1.25.0.tar.gz
cd unbound-1.25.0/

export CFLAGS="-O2"
./configure --build=aarch64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --infodir=\${prefix}/share/info --libdir=\${prefix}/lib/aarch64-linux-gnu --mandir=\${prefix}/share/man --localstatedir=/var --runstatedir=/run --sysconfdir=/etc --with-chroot-dir= --with-dnstap-socket-path=/run/dnstap.sock --with-libevent --with-libhiredis --with-libnghttp2 --with-pidfile=/run/unbound.pid --with-pythonmodule --with-pyunbound --with-rootkey-file=/var/lib/unbound/root.key --disable-dependency-tracking --disable-flto --disable-maintainer-mode --disable-option-checking --disable-rpath --disable-silent-rules --enable-cachedb --enable-dnstap --enable-subnet --enable-systemd --enable-tfo-client --enable-tfo-server
make
sudo make install

wget https://github.com/hagezi/files/raw/refs/heads/main/unbound/unbound-post-install.tar.gz
tar -xvzf unbound-post-install.tar.gz
cd unbound-post-install
sudo ./post-install.sh

cd $HOME
wget https://raw.githubusercontent.com/hagezi/files/refs/heads/main/unbound/server.conf
sudo mv server.conf /etc/unbound/unbound.conf

sudo unbound-checkconf /etc/unbound/unbound.conf
sudo systemctl enable unbound
sudo systemctl start unbound

sudo systemctl status unbound
unbound -V

dig fail01.dnssec.works @127.0.0.1 -p 5335
dig +ad dnssec.works @127.0.0.1 -p 5335

cd $HOME
rm -rf unbound-*
```

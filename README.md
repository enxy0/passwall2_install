# Passwall2 OpenWrt installation script

English | [Русский](README.ru.md)

Automated installation script for Passwall2 on OpenWrt routers. It installs Passwall2 from the official GitHub releases of [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2), using either `opkg` or `apk` depending on the OpenWrt release.

## Quick install

Run this on your OpenWrt device:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)"
```

`wget` on OpenWrt is the BusyBox/uclient-fetch build and supports HTTPS out of the box.

Pass options after `--`:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- 26.9.2-1
```

Alternative: download first, inspect the script, then run it.

```sh
cd /tmp && rm -f passwall2.sh && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh
less passwall2.sh
sh passwall2.sh
```

## Proxy cores

Since upstream release `26.8.27` the Passwall2 runtime archive no longer contains a proxy core: `xray-core` and `sing-box` were dropped from it, together with the standalone Hysteria2 and naive cores. Without a core Passwall2 starts but fails silently.

Cores that come with the runtime archive are used as they are. The official OpenWrt feeds are only a fallback: after the runtime packages are installed, the script installs from the feeds any core that the archive did not provide. Older releases therefore need no extra download. Use `--no-xray` or `--no-sing-box` to skip a core, for example on a device with little flash (`sing-box` needs about 44 MB).

## Features

- **GitHub release installation**: installs the latest release by default or a specific release when provided
- **Package manager detection**: uses `apk` on OpenWrt 25.x builds and `opkg` on older builds
- **Automatic architecture detection**: detects the device architecture automatically
- **Dependency management**: installs required packages such as `dnsmasq-full`, kernel modules, `curl`, `unzip`, and `jsonfilter`
- **Configuration backup**: backs up the existing Passwall2 configuration before installation
- **Clean install option**: removes existing packages before reinstalling
- **LuCI-only mode**: installs only the web interface
- **Proxy core fallback**: installs `xray-core` and `sing-box` from the official OpenWrt feeds when the release archive does not bundle them
- **Error reporting**: shows installation errors and common recovery hints

## Installation

Install the latest release:

```sh
./passwall2.sh
```

Install a specific release:

```sh
./passwall2.sh 26.6.3-1
```

## Usage

```text
Usage: passwall2.sh [OPTIONS] [VER]

Options:
  [VER]               Optional release version (e.g., 26.6.3-1)
  -c, --clean         Clean install (remove old packages first)
  -l, --only-luci     Install only LuCI interface (skip binaries)
      --no-xray       Do not install xray-core
      --no-sing-box   Do not install sing-box (~44 MB on flash)
  -h, --help          Show help message

Examples:
  passwall2.sh                  Install latest release
  passwall2.sh 26.6.3-1         Install a specific release
  passwall2.sh -c               Clean install of latest release
  passwall2.sh -l               LuCI-only install
  passwall2.sh --no-sing-box    Install with xray-core only
```

## What the script does

1. Checks internet connectivity, free space, and basic device information
2. Detects `apk` or `opkg` and installs required tools such as `curl`, `unzip`, and `jsonfilter`
3. Ensures `kmod-nft-tproxy` and `kmod-nft-socket` are installed
4. Replaces basic `dnsmasq` with `dnsmasq-full` when needed
5. Detects the OpenWrt architecture automatically
6. Backs up the existing `/etc/config/passwall2` configuration if present
7. Downloads the matching LuCI package and runtime package archive from GitHub releases
8. Installs the bundled runtime packages such as chinadns-ng, shadowsocks-rust, simple-obfs, v2ray-plugin, and the geodata files
9. Installs `xray-core` and `sing-box` from the official OpenWrt feeds if the archive did not provide them
10. Installs the Passwall2 LuCI package and warns when no proxy core is present
11. Cleans up temporary files

## After installation

1. Open the LuCI web interface
2. Go to `Services -> Passwall2`
3. Configure your proxy settings

## Troubleshooting

**Not enough space**

Use `-c` to remove existing packages before reinstalling:

```sh
./passwall2.sh -c
```

**No compatible binary package**

Use `-l` for a LuCI-only installation:

```sh
./passwall2.sh -l
```

**Passwall2 starts but no traffic is proxied**

Check that a proxy core is installed: `/usr/bin/xray` or `/usr/bin/sing-box` must exist. Without a core the log shows `process /tmp/etc/passwall2/acl/default.json error`. Install a core manually if the feeds were unavailable:

```sh
apk add xray-core sing-box     # OpenWrt 25.x
opkg install xray-core sing-box  # older releases
```

**Installation fails**

Check internet connectivity, DNS settings, available storage, and whether the selected Passwall2 release has assets for your architecture.

## Credits

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): original project by the OpenWrt Passwall team

## License

This installation script is provided as-is for personal and educational use.

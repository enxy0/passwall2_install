# Passwall2 OpenWrt installation script

English | [Русский](README.ru.md)

Automated installation script for Passwall2 on OpenWrt routers. It installs Passwall2 from the official GitHub releases of [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2), using either `opkg` or `apk` depending on the OpenWrt release.

## Quick install

Run this on your OpenWrt device:

```sh
cd /tmp && rm -f passwall2.sh && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh && sh passwall2.sh
```

## Features

- **GitHub release installation**: installs the latest release by default or a specific release when provided
- **Package manager detection**: uses `apk` on OpenWrt 25.x builds and `opkg` on older builds
- **Automatic architecture detection**: detects the device architecture automatically
- **Dependency management**: installs required packages such as `dnsmasq-full`, kernel modules, `curl`, `unzip`, and `jsonfilter`
- **Configuration backup**: backs up the existing Passwall2 configuration before installation
- **Clean install option**: removes existing packages before reinstalling
- **LuCI-only mode**: installs only the web interface
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
Usage: ./passwall2.sh [OPTIONS] [VER]

Options:
  [VER]               Optional release version (e.g., 26.6.3-1)
  -c, --clean         Clean install (remove old packages first)
  -l, --only-luci     Install only LuCI interface (skip binaries)
  -h, --help          Show help message

Examples:
  ./passwall2.sh             Install latest release
  ./passwall2.sh 26.6.3-1    Install a specific release
  ./passwall2.sh -c          Clean install of latest release
  ./passwall2.sh -l          LuCI-only install
```

## What the script does

1. Checks internet connectivity, free space, and basic device information
2. Detects `apk` or `opkg` and installs required tools such as `curl`, `unzip`, and `jsonfilter`
3. Ensures `kmod-nft-tproxy` and `kmod-nft-socket` are installed
4. Replaces basic `dnsmasq` with `dnsmasq-full` when needed
5. Detects the OpenWrt architecture automatically
6. Backs up the existing `/etc/config/passwall2` configuration if present
7. Downloads the matching LuCI package and runtime package archive from GitHub releases
8. Installs Passwall2 and bundled runtime packages such as Xray, sing-box, chinadns-ng, Hysteria, HAProxy, microsocks, and NaiveProxy when present in the release archive
9. Cleans up temporary files

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

**Installation fails**

Check internet connectivity, DNS settings, available storage, and whether the selected Passwall2 release has assets for your architecture.

## Credits

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): original project by the OpenWrt Passwall team

## License

This installation script is provided as-is for personal and educational use.

# Passwall2 OpenWrt installation script

English | [Русский](README.ru.md)

Automated installation script for Passwall2 on OpenWrt routers. Supports both SourceForge feed installation for routine updates and GitHub release installation for specific versions.

## Quick install

Run this on your OpenWrt device:

```sh
cd /tmp && rm -f passwall2.sh && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh && sh passwall2.sh
```

## Features

- **Two installation modes**:
  - **SourceForge feed** (default): uses package feeds for easier updates via `opkg`
  - **GitHub releases**: installs the latest or a specific release directly
- **Automatic architecture detection**: detects the device architecture automatically
- **Dependency management**: installs required packages such as `dnsmasq-full`, kernel modules, `curl`, `unzip`, and `jsonfilter`
- **Configuration backup**: backs up the existing Passwall2 configuration before installation
- **Clean install option**: removes existing packages before reinstalling
- **LuCI-only mode**: installs only the web interface in GitHub mode
- **Error reporting**: shows installation errors and common recovery hints

## Installation modes

### 1. SourceForge feed installation

Default mode. Uses package feeds for standard installation and follow-up updates:

```sh
./passwall2.sh
```

Advantages:

- Updates remain available through `opkg update` and `opkg upgrade`
- Dependency resolution stays with the package manager
- Feed packages are signed

### 2. GitHub release installation

Install the latest release or a specific version directly from GitHub:

```sh
# Install the latest release
./passwall2.sh -g

# Install a specific version
./passwall2.sh -g v26.2.14-1
```

## Usage

```text
Usage: ./passwall2.sh [OPTIONS]

Options:
  -g, --github [VER]  Install from GitHub releases. Optional version (e.g., v26.2.14-1)
  -c, --clean         Clean install (remove old packages first)
  -l, --only-luci     Install only LuCI interface (skip binaries). GitHub mode only
  -h, --help          Show help message

Examples:
  ./passwall2.sh                Install latest from SourceForge feed
  ./passwall2.sh -g             Install latest from GitHub
  ./passwall2.sh -g v26.2.14-1  Install a specific version from GitHub
  ./passwall2.sh -g -c          Clean install from GitHub
  ./passwall2.sh -g -l          LuCI-only install from GitHub
```

## What the script does

1. Checks internet connectivity, free space, and basic device information
2. Installs required tools such as `curl`, `unzip`, and `jsonfilter`
3. Ensures `kmod-nft-tproxy` and `kmod-nft-socket` are installed
4. Replaces basic `dnsmasq` with `dnsmasq-full` when needed
5. Detects the OpenWrt architecture automatically
6. Backs up the existing `/etc/config/passwall2` configuration if present
7. Installs Passwall2 and related packages
8. Cleans up temporary files

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

Use `-l` for a LuCI-only installation in GitHub mode:

```sh
./passwall2.sh -g -l
```

**Installation fails**

Check internet connectivity, DNS settings, and available storage.

## Credits

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): original project by the OpenWrt Passwall team
- SourceForge feed maintained by the Passwall community

## License

This installation script is provided as-is for personal and educational use.

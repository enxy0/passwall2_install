# passwall2_install

English | [Русский](README.ru.md)

Shell script that installs [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) on an OpenWrt router from the upstream GitHub releases. Works with both `opkg` and `apk` (OpenWrt 25.x).

## Install

Run on the router:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)"
```

Options go after `--`:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- 26.9.2-1
```

> **Note:** since release `26.8.27` the upstream archive ships no proxy core. The script installs `xray-core` and `sing-box` from the official OpenWrt feeds when the archive does not include them. Use `--no-xray` or `--no-sing-box` to skip one (`sing-box` takes about 44 MB of flash).

To read the script before running it:

```sh
cd /tmp && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh
less passwall2.sh
sh passwall2.sh
```

## Options

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
  passwall2.sh -c 26.6.3-1      Clean install of a specific release
  passwall2.sh -l               LuCI-only install
  passwall2.sh --no-sing-box    Install with xray-core only
  passwall2.sh --no-xray        Install with sing-box only
```

With the one-liner, put the same arguments after `--`:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c 26.6.3-1
```

## What the script does

1. Installs `curl`, `unzip`, `jsonfilter`, `kmod-nft-tproxy`, `kmod-nft-socket`, and replaces `dnsmasq` with `dnsmasq-full` if needed.
2. Backs up `/etc/config/passwall2` if it exists.
3. Downloads the LuCI package and the runtime archive for the detected architecture.
4. Installs the runtime packages from the archive (chinadns-ng, shadowsocks-rust, simple-obfs, v2ray-plugin, geodata).
5. Installs `xray-core` and `sing-box` from the feeds if the archive did not include them.
6. Installs the LuCI package and cleans up.

Then open LuCI and go to `Services -> Passwall2`.

## Troubleshooting

**Not enough space.** Run with `-c` to remove the old packages first, or skip `sing-box` with `--no-sing-box`.

**No compatible binary package.** Run with `-l` to install only the LuCI interface.

**Passwall2 starts but no traffic is proxied.** A proxy core is missing: `/usr/bin/xray` or `/usr/bin/sing-box` must exist. The log shows `process /tmp/etc/passwall2/acl/default.json error`. Install a core manually:

```sh
apk add xray-core sing-box       # OpenWrt 25.x
opkg install xray-core sing-box  # older releases
```

## Credits

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): original project by the OpenWrt Passwall team

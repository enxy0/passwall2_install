# passwall2_install

[English](README.md) | Русский

Скрипт ставит [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) на роутер с OpenWrt из GitHub releases upstream-проекта. Работает и с `opkg`, и с `apk` (OpenWrt 25.x).

## Установка

Запустите на роутере:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)"
```

Опции передаются после `--`:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- 26.9.2-1
```

> **Примечание:** начиная с релиза `26.8.27` в архиве upstream нет прокси-ядра. Скрипт ставит `xray-core` и `sing-box` из официальных фидов OpenWrt, если их нет в архиве. Чтобы пропустить ядро, используйте `--no-xray` или `--no-sing-box` (`sing-box` занимает около 44 МБ flash).

Чтобы посмотреть скрипт перед запуском:

```sh
cd /tmp && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh
less passwall2.sh
sh passwall2.sh
```

## Опции

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

Для однострочника те же аргументы передаются после `--`:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c 26.6.3-1
```

## Что делает скрипт

1. Ставит `curl`, `unzip`, `jsonfilter`, `kmod-nft-tproxy`, `kmod-nft-socket` и при необходимости заменяет `dnsmasq` на `dnsmasq-full`.
2. Делает резервную копию `/etc/config/passwall2`, если файл есть.
3. Скачивает LuCI-пакет и архив runtime-пакетов под архитектуру устройства.
4. Ставит runtime-пакеты из архива (chinadns-ng, shadowsocks-rust, simple-obfs, v2ray-plugin, geodata).
5. Ставит `xray-core` и `sing-box` из фидов, если их не было в архиве.
6. Ставит LuCI-пакет и удаляет временные файлы.

После этого откройте LuCI и перейдите в `Services -> Passwall2`.

## Решение проблем

**Недостаточно места.** Запустите с `-c`, чтобы сначала удалить старые пакеты, или пропустите `sing-box` через `--no-sing-box`.

**Нет подходящего бинарного пакета.** Запустите с `-l`, чтобы поставить только LuCI-интерфейс.

**Passwall2 запускается, но трафик не идет через прокси.** Нет прокси-ядра: должен существовать `/usr/bin/xray` или `/usr/bin/sing-box`. В логе видно `process /tmp/etc/passwall2/acl/default.json error`. Поставьте ядро вручную:

```sh
apk add xray-core sing-box       # OpenWrt 25.x
opkg install xray-core sing-box  # старые версии
```

## Благодарности

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): оригинальный проект команды OpenWrt Passwall

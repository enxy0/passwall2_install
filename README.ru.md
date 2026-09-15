# passwall2_install

[English](README.md) | Русский

Скрипт ставит [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) на роутер с OpenWrt из GitHub releases upstream-проекта. Работает и с `opkg`, и с `apk` (OpenWrt 25.x).

## Быстрая установка

Запустите на роутере:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)"
```

Это вся установка. Чтобы изменить состав пакетов, смотрите [Опции](#опции).

> **Примечание:** начиная с релиза `26.8.27` в архиве upstream нет прокси-ядра. Скрипт ставит `xray-core` и `sing-box` из [фида сборок passwall](https://github.com/moetayuko/openwrt-passwall-build) — там они заметно новее, чем в официальных фидах OpenWrt. Фид остается прописанным (`/etc/apk/repositories.d/passwall.list` для `apk`, `/etc/opkg/customfeeds.conf` для `opkg`), поэтому ядра можно обновлять и позже. Чтобы пропустить ядро, используйте `--no-xray` или `--no-sing-box` (`sing-box` занимает около 44 МБ flash), а `--no-feed` оставляет только те фиды, которые уже есть на роутере.

Чтобы посмотреть скрипт перед запуском:

```sh
cd /tmp && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh
less passwall2.sh
sh passwall2.sh
```

## Опции

Опции передаются после `--`. Каждая строка ниже заменяет команду выше — запустите одну из них, а не обе.

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- 26.9.2-1
sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- -c 26.6.3-1
```

Полный список:

```text
Usage: passwall2.sh [OPTIONS] [VER]

Options:
  [VER]               Optional release version (e.g., 26.6.3-1)
  -c, --clean         Clean install (remove old packages first)
  -l, --only-luci     Install only LuCI interface (skip binaries)
      --no-xray       Do not install xray-core
      --no-sing-box   Do not install sing-box (~44 MB on flash)
      --no-feed       Do not add the passwall build feed
      --no-restart    Do not restart the Passwall2 services after the install
  -h, --help          Show help message

Examples:
  passwall2.sh                  Install latest release
  passwall2.sh 26.6.3-1         Install a specific release
  passwall2.sh -c               Clean install of latest release
  passwall2.sh -c 26.6.3-1      Clean install of a specific release
  passwall2.sh -l               LuCI-only install
  passwall2.sh --no-sing-box    Install with xray-core only
  passwall2.sh --no-xray        Install with sing-box only
  passwall2.sh --no-feed        Install the cores from the existing feeds
```

## Что делает скрипт

1. Ставит `curl`, `unzip`, `jsonfilter`, `kmod-nft-tproxy`, `kmod-nft-socket` и при необходимости заменяет `dnsmasq` на `dnsmasq-full`.
2. Делает резервную копию `/etc/config/passwall2`, если файл есть.
3. Скачивает LuCI-пакет и архив runtime-пакетов под архитектуру устройства.
4. Ставит runtime-пакеты из архива (chinadns-ng, shadowsocks-rust, simple-obfs, v2ray-plugin, geodata).
5. Прописывает фид сборок passwall и ставит или обновляет из него `xray-core` и `sing-box`. Если фид не удалось добавить или прочитать, строка фида удаляется, а ядра ставятся из официальных фидов OpenWrt.
6. Ставит LuCI-пакет и удаляет временные файлы.
7. Перезапускает службы Passwall2, которые работали до установки. Пакет запускается командой `start`, а не `restart`, из-за чего остается второй процесс прокси. Остановленная служба остается остановленной. Шаг пропускается через `--no-restart`.

После этого откройте LuCI и перейдите в `Services -> Passwall2`.

Фид остается прописанным, поэтому ядра можно обновлять без этого скрипта:

```sh
apk update && apk add --upgrade xray-core sing-box   # OpenWrt 25.x
opkg update && opkg upgrade xray-core sing-box       # старые версии
```

Обновляйте только эти пакеты. Полное обновление командой `apk upgrade` или `opkg upgrade` на OpenWrt не рекомендуется.

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

# Скрипт установки Passwall2 для OpenWrt

[English](README.md) | Русский

Автоматизированный скрипт установки Passwall2 для роутеров на OpenWrt. Он устанавливает Passwall2 из официальных GitHub releases проекта [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2), используя `opkg` или `apk` в зависимости от версии OpenWrt.

## Быстрая установка

Запустите эту команду на устройстве с OpenWrt:

```sh
cd /tmp && rm -f passwall2.sh && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh && sh passwall2.sh
```

## Возможности

- **Установка из GitHub release**: по умолчанию устанавливает последний релиз или конкретный релиз, если он указан
- **Определение пакетного менеджера**: использует `apk` на OpenWrt 25.x и `opkg` на более старых версиях
- **Автоматическое определение архитектуры**: скрипт сам определяет архитектуру устройства
- **Управление зависимостями**: устанавливает необходимые пакеты, включая `dnsmasq-full`, kernel modules, `curl`, `unzip` и `jsonfilter`
- **Резервная копия конфигурации**: сохраняет текущую конфигурацию Passwall2 перед установкой
- **Чистая установка**: может удалить уже установленные пакеты перед переустановкой
- **Режим только LuCI**: устанавливает только веб-интерфейс
- **Сообщения об ошибках**: показывает детали ошибок и типовые подсказки по восстановлению

## Установка

Установить последний релиз:

```sh
./passwall2.sh
```

Установить конкретный релиз:

```sh
./passwall2.sh 26.6.3-1
```

## Использование

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

## Что делает скрипт

1. Проверяет подключение к интернету, свободное место и базовую информацию об устройстве
2. Определяет `apk` или `opkg` и устанавливает необходимые утилиты, включая `curl`, `unzip` и `jsonfilter`
3. Проверяет наличие `kmod-nft-tproxy` и `kmod-nft-socket`
4. При необходимости заменяет обычный `dnsmasq` на `dnsmasq-full`
5. Автоматически определяет архитектуру OpenWrt
6. Создает резервную копию `/etc/config/passwall2`, если файл существует
7. Скачивает подходящий LuCI-пакет и архив runtime-пакетов из GitHub releases
8. Устанавливает Passwall2 и runtime-пакеты из архива, включая Xray, sing-box, chinadns-ng, Hysteria, HAProxy, microsocks и NaiveProxy, если они есть в релизе
9. Удаляет временные файлы

## После установки

1. Откройте веб-интерфейс LuCI
2. Перейдите в `Services -> Passwall2`
3. Настройте параметры прокси

## Решение проблем

**Недостаточно места**

Используйте `-c`, чтобы удалить уже установленные пакеты перед переустановкой:

```sh
./passwall2.sh -c
```

**Нет подходящего бинарного пакета**

Используйте `-l` для установки только LuCI:

```sh
./passwall2.sh -l
```

**Установка завершается ошибкой**

Проверьте подключение к интернету, DNS, свободное место и наличие assets для вашей архитектуры в выбранном релизе Passwall2.

## Благодарности

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): оригинальный проект команды OpenWrt Passwall

## Лицензия

Этот скрипт установки предоставляется как есть для личного и образовательного использования.

# Скрипт установки Passwall2 для OpenWrt

[English](README.md) | Русский

Автоматизированный скрипт установки Passwall2 для роутеров на OpenWrt. Поддерживает установку через SourceForge feed для обычных обновлений и установку из GitHub releases для конкретных версий.

## Быстрая установка

Запустите эту команду на вашем устройстве с OpenWrt:

```sh
cd /tmp && rm -f passwall2.sh && wget -O passwall2.sh https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh && sh passwall2.sh
```

## Возможности

- **Два режима установки**:
  - **SourceForge feed** (по умолчанию): использует package feeds для более удобных обновлений через `opkg`
  - **GitHub releases**: устанавливает последний или конкретный релиз напрямую
- **Автоматическое определение архитектуры**: скрипт сам определяет архитектуру устройства
- **Управление зависимостями**: устанавливает необходимые пакеты, включая `dnsmasq-full`, kernel modules, `curl`, `unzip` и `jsonfilter`
- **Резервная копия конфигурации**: сохраняет текущую конфигурацию Passwall2 перед установкой
- **Чистая установка**: может удалить уже установленные пакеты перед переустановкой
- **Режим только LuCI**: устанавливает только веб-интерфейс в GitHub-режиме
- **Сообщения об ошибках**: показывает детали ошибок и типовые подсказки по восстановлению

## Режимы установки

### 1. Установка через SourceForge feed

Режим по умолчанию. Использует package feeds для стандартной установки и последующих обновлений:

```sh
./passwall2.sh
```

Преимущества:

- Обновления доступны через `opkg update` и `opkg upgrade`
- Разрешение зависимостей остается на стороне пакетного менеджера
- Пакеты из feed подписаны

### 2. Установка из GitHub release

Позволяет установить последний релиз или конкретную версию напрямую из GitHub:

```sh
# Установить последний релиз
./passwall2.sh -g

# Установить конкретную версию
./passwall2.sh -g v26.2.14-1
```

## Использование

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

## Что делает скрипт

1. Проверяет подключение к интернету, свободное место и базовую информацию об устройстве
2. Устанавливает необходимые утилиты, включая `curl`, `unzip` и `jsonfilter`
3. Проверяет наличие `kmod-nft-tproxy` и `kmod-nft-socket`
4. При необходимости заменяет обычный `dnsmasq` на `dnsmasq-full`
5. Автоматически определяет архитектуру OpenWrt
6. Создает резервную копию `/etc/config/passwall2`, если файл существует
7. Устанавливает Passwall2 и связанные пакеты
8. Удаляет временные файлы

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

Используйте `-l` для установки только LuCI в GitHub-режиме:

```sh
./passwall2.sh -g -l
```

**Установка завершается ошибкой**

Проверьте подключение к интернету, настройки DNS и объем доступного места.

## Благодарности

- [Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2): оригинальный проект команды OpenWrt Passwall
- SourceForge feed поддерживается сообществом Passwall

## Лицензия

Этот скрипт установки предоставляется как есть для личного и образовательного использования.

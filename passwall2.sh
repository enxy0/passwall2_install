#!/bin/sh

PACKAGE_MANAGER=""
PACKAGE_TYPE=""
REPO_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases"
BASE_DOWNLOAD_URL="https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download"
TEMP_DIR="/tmp/passwall2_update"
CONFIG_DIR="/etc/config"
BACKUP_SUFFIX=$(date +%Y%m%d)
MIN_SPACE_KB=20480

FEED_BASE_URL="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
FEED_NAMES="passwall_luci passwall_packages passwall2"
FEED_RUNTIME_PACKAGES="xray-core sing-box chinadns-ng hysteria geoview v2ray-geoip v2ray-geosite haproxy microsocks naiveproxy tcping"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'

msg() {
    case "$1" in
        ok)    echo -e "${C_GREEN}[OK]${C_RESET} $2" ;;
        err)   echo -e "${C_RED}[ERROR]${C_RESET} $2"; exit 1 ;;
        warn)  echo -e "${C_YELLOW}[WARN]${C_RESET} $2" ;;
        info)  echo -e "${C_CYAN}[INFO]${C_RESET} $2" ;;
        head)  echo -e "\n${C_BOLD}$2${C_RESET}" ;;
        *)     echo "$1" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    if command_exists apk; then
        PACKAGE_MANAGER="apk"
        PACKAGE_TYPE="apk"
    elif command_exists opkg; then
        PACKAGE_MANAGER="opkg"
        PACKAGE_TYPE="ipk"
    else
        msg err "No supported package manager found: need apk or opkg"
    fi
}

pkg_update() {
    case "$PACKAGE_MANAGER" in
        apk) apk update ;;
        opkg) opkg update ;;
    esac
}

pkg_install() {
    case "$PACKAGE_MANAGER" in
        apk) apk add --upgrade "$@" ;;
        opkg) opkg install "$@" ;;
    esac
}

pkg_install_feed() {
    case "$PACKAGE_MANAGER" in
        apk)
            if [ "$ALLOW_UNTRUSTED_FEEDS" = true ]; then
                apk add --upgrade --allow-untrusted "$@"
            else
                apk add --upgrade "$@"
            fi
            ;;
        opkg) opkg install "$@" ;;
    esac
}

pkg_update_feed() {
    local log_file="$1"

    if pkg_update >"$log_file" 2>&1; then
        return 0
    fi

    if [ "$PACKAGE_MANAGER" = "apk" ] && grep -q 'UNTRUSTED signature' "$log_file"; then
        cat "$log_file"
        msg warn "Passwall apk feed signature is not trusted by apk; retrying with --allow-untrusted"
        ALLOW_UNTRUSTED_FEEDS=true
        if apk update --allow-untrusted >"$log_file" 2>&1; then
            return 0
        fi
    fi

    if [ "$PACKAGE_MANAGER" = "apk" ] && apk search --allow-untrusted --from repositories --exact luci-app-passwall2 2>/dev/null | grep -q '^luci-app-passwall2-'; then
        msg warn "Using cached package indexes after failed refresh"
        ALLOW_UNTRUSTED_FEEDS=true
        return 0
    fi

    return 1
}

pkg_install_local() {
    case "$PACKAGE_MANAGER" in
        apk) apk add --allow-untrusted --force-reinstall "$1" ;;
        opkg) opkg install "$1" --force-reinstall ;;
    esac
}

pkg_remove() {
    case "$PACKAGE_MANAGER" in
        apk) apk del "$@" ;;
        opkg) opkg remove "$@" ;;
    esac
}

pkg_remove_force() {
    case "$PACKAGE_MANAGER" in
        apk) apk del "$@" ;;
        opkg) opkg remove "$@" --force-depends ;;
    esac
}

ensure_direct_resolver() {
    [ -f /tmp/resolv.conf ] || return 0

    local has_loopback=false
    local has_direct=false
    local key value

    while read -r key value _; do
        [ "$key" = "nameserver" ] || continue
        case "$value" in
            127.*|::1) has_loopback=true ;;
            *) has_direct=true ;;
        esac
    done < /tmp/resolv.conf

    if [ "$has_direct" = false ]; then
        cp /tmp/resolv.conf /tmp/resolv.conf.passwall2.bak 2>/dev/null || true
        {
            grep '^search ' /tmp/resolv.conf 2>/dev/null
            echo 'nameserver 9.9.9.9'
            echo 'nameserver 1.1.1.1'
        } > /tmp/resolv.conf
        if [ "$has_loopback" = true ]; then
            msg warn "Using temporary direct resolvers while replacing dnsmasq"
        else
            msg warn "Using temporary direct resolvers because no system resolver is configured"
        fi
    fi
}

ensure_command() {
    local path="$1"
    local package="$2"

    [ -x "$path" ] && return 0
    msg warn "Installing $package"
    pkg_update && pkg_install "$package" || msg err "Failed to install $package"
}

pkg_is_installed() {
    case "$PACKAGE_MANAGER" in
        apk) apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg list-installed | grep -q "^$1 " ;;
    esac
}

pkg_list_installed() {
    case "$PACKAGE_MANAGER" in
        apk) apk info | sort -u ;;
        opkg) opkg list-installed | awk '{print $1}' | sort -u ;;
    esac
}

pkg_list_upgradable() {
    case "$PACKAGE_MANAGER" in
        apk)
            apk list --upgradable 2>/dev/null | awk '{print $1}' | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' | sort -u
            ;;
        opkg) opkg list-upgradable | awk '{print $1}' | sort -u ;;
    esac
}

pkg_available() {
    case "$PACKAGE_MANAGER" in
        apk)
            if [ "$ALLOW_UNTRUSTED_FEEDS" = true ]; then
                apk search --allow-untrusted --from repositories --exact "$1" 2>/dev/null | grep -q "^$1-"
            else
                apk search --from repositories --exact "$1" 2>/dev/null | grep -q "^$1-"
            fi
            ;;
        opkg) opkg list "$1" 2>/dev/null | grep -q "^$1 -" ;;
    esac
}

ensure_feed_packages_available() {
    local missing=""
    local package=""

    for package in luci-app-passwall2 $FEED_RUNTIME_PACKAGES; do
        if ! pkg_available "$package"; then
            missing="$missing $package"
        fi
    done

    missing=$(echo "$missing" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$missing" ]; then
        msg err "Required feed packages are unavailable: $missing. Use --github or retry after feed refresh works."
    fi
}

get_apk_feed_version() {
    local package="$1"

    apk --allow-untrusted policy "$package" 2>/dev/null | awk -v feed_base="$FEED_BASE_URL" '
        $1 ~ /:$/ {
            version=$1
            sub(/:$/, "", version)
            next
        }
        index($0, feed_base) && version != "" {
            print version
            exit
        }
    '
}

get_feed_install_args() {
    local packages="$1"
    local args=""
    local package=""
    local version=""

    case "$PACKAGE_MANAGER" in
        apk)
            for package in $packages; do
                version=$(get_apk_feed_version "$package")

                if [ -n "$version" ]; then
                    args="$args $package=$version"
                else
                    args="$args $package"
                fi
            done
            ;;
        opkg) args="$packages" ;;
    esac

    echo "$args" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

install_available_feed_packages() {
    local packages="$1"
    local available=""
    local package=""
    local install_args=""

    for package in $packages; do
        if pkg_available "$package"; then
            available="$available $package"
        else
            msg warn "Package not available in feeds: $package"
        fi
    done

    available=$(echo "$available" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$available" ] || return 0

    install_args=$(get_feed_install_args "$available")
    msg info "Installing: $install_args"
    pkg_install_feed $install_args
}

ensure_dnsmasq_full() {
    msg info "Checking dnsmasq-full"
    if pkg_is_installed dnsmasq-full; then
        msg ok "dnsmasq-full already installed"
        return 0
    fi

    ensure_direct_resolver
    case "$PACKAGE_MANAGER" in
        opkg)
            if pkg_is_installed dnsmasq; then
                msg info "Removing dnsmasq"
                pkg_remove dnsmasq || msg err "Failed to remove dnsmasq"
            fi
            ;;
    esac

    msg info "Installing dnsmasq-full"
    pkg_install dnsmasq-full || msg err "Failed to install dnsmasq-full"
    msg ok "dnsmasq-full installed"

    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || msg warn "dnsmasq restart failed; check DNS manually"
    fi
}

list_installed_named_packages() {
    local packages="$1"
    local installed=""
    local package=""

    for package in $packages; do
        if pkg_is_installed "$package"; then
            installed="$installed $package"
        fi
    done

    echo "$installed" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

pkg_print_architectures() {
    case "$PACKAGE_MANAGER" in
        apk)
            get_architecture
            ;;
        opkg)
            opkg print-architecture | awk '{print $2}' | awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}'
            ;;
    esac
}

get_local_package_name() {
    local file="$1"

    case "$PACKAGE_TYPE" in
        apk) basename "$file" ".$PACKAGE_TYPE" | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' ;;
        ipk) basename "$file" ".$PACKAGE_TYPE" | cut -d'_' -f1 ;;
    esac
}

get_feed_key_url() {
    case "$PACKAGE_MANAGER" in
        apk) echo "${FEED_BASE_URL}/apk.pub" ;;
        opkg) echo "${FEED_BASE_URL}/ipk.pub" ;;
    esac
}

download_file() {
    local url="$1"
    local output="$2"

    curl -s -L --fail --retry 3 --connect-timeout 20 -o "$output" "$url"
}

install_feed_key() {
    local key_file=""
    local key_url=""

    key_url=$(get_feed_key_url)
    case "$PACKAGE_MANAGER" in
        apk)
            key_file="/etc/apk/keys/openwrt-passwall-build.pub"
            if [ -s "$key_file" ]; then
                msg ok "Feed key already exists"
                return 0
            fi

            download_file "$key_url" /tmp/passwall.pub || \
                download_file "https://sourceforge.net/projects/openwrt-passwall-build/files/apk.pub/download" /tmp/passwall.pub || \
                msg err "Failed to download feed key"
            mkdir -p /etc/apk/keys || msg err "Failed to prepare apk keys directory"
            cp /tmp/passwall.pub "$key_file" || msg err "Failed to add feed key"
            ;;
        opkg)
            download_file "$key_url" /tmp/passwall.pub || \
                download_file "https://sourceforge.net/projects/openwrt-passwall-build/files/ipk.pub/download" /tmp/passwall.pub || \
                msg err "Failed to download feed key"
            opkg-key add /tmp/passwall.pub || msg err "Failed to add feed key"
            ;;
    esac

    rm -f /tmp/passwall.pub
    msg ok "Feed key added"
}

get_feed_url() {
    local feed="$1"

    case "$PACKAGE_MANAGER" in
        apk) echo "${FEED_BASE_URL}/releases/packages-${RELEASE_VER}/${ARCH}/${feed}/packages.adb" ;;
        opkg) echo "${FEED_BASE_URL}/releases/packages-${RELEASE_VER}/${ARCH}/${feed}" ;;
    esac
}

get_architecture() {
    local arch=""

    if [ -r /etc/openwrt_release ]; then
        arch=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
    fi

    if [ -n "$arch" ]; then
        echo "$arch"
        return
    fi

    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        arch=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -1)
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        arch=$(apk --print-arch 2>/dev/null)
    fi

    echo "$arch"
}

get_release_version() {
    if [ -r /etc/openwrt_release ]; then
        . /etc/openwrt_release
        case "$DISTRIB_RELEASE" in
            *.*.*) echo "${DISTRIB_RELEASE%.*}" ;;
            *) echo "$DISTRIB_RELEASE" ;;
        esac
    fi
}

list_feed_packages() {
    case "$PACKAGE_MANAGER" in
        apk)
            apk search 2>/dev/null | awk '{print $1}' | sed 's/-[0-9][^-[:space:]]*-r[0-9].*$//' | grep -E '^(luci-app-passwall2|luci-i18n-passwall2-)' | sort -u
            ;;
        opkg)
            for feed_file in /var/opkg-lists/passwall_luci /var/opkg-lists/passwall_packages /var/opkg-lists/passwall2; do
                [ -f "$feed_file" ] || continue
                gzip -dc "$feed_file" 2>/dev/null || cat "$feed_file" 2>/dev/null
            done | awk '/^Package: / {print $2}' | sort -u
            ;;
    esac
}

list_installed_packages() {
    pkg_list_installed
}

list_upgradable_packages() {
    pkg_list_upgradable
}

print_pkg_warnings() {
    local log_file="$1"

    if [ "$PACKAGE_MANAGER" = "opkg" ] && grep -qE 'resolve_conffiles:|^Collected errors:$' "$log_file"; then
        msg warn "opkg reported warnings"
        grep -E 'resolve_conffiles:|^Collected errors:$|^ \* ' "$log_file" | sed 's/^/  /'
    fi
}

print_space_hint() {
    local log_file="$1"

    if grep -qiE '(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)' "$log_file"; then
        msg warn "Suggestion: try --clean to free space"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Description:"
    echo "  Install Passwall2 from SourceForge feed (default) or GitHub releases."
    echo "  Automatically uses apk or opkg, depending on availability."
    echo ""
    echo "Options:"
    echo "  -g, --github [VER]  Install from GitHub releases. Optional version (e.g., v2.0.1)."
    echo "  -c, --clean         Clean install (remove old packages first)."
    echo "  -l, --only-luci     Install only LuCI interface (skip binaries). GitHub mode only."
    echo "  -h, --help          Show this help message."
    echo ""
    echo "Examples:"
    echo "  $0                  Install latest from SourceForge feed (default)"
    echo "  $0 -g               Install latest from GitHub"
    echo "  $0 -g v2.0.1        Install specific version from GitHub"
    echo "  $0 -g -c            Clean install from GitHub (latest)"
    echo ""
    exit 0
}

GITHUB_MODE=false
TARGET_VERSION=""
CLEAN_INSTALL=false
ONLY_LUCI=false
ALLOW_UNTRUSTED_FEEDS=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) show_help ;;
        -g|--github)
            GITHUB_MODE=true
            shift
            case "$1" in
                ""|-*) ;;
                *) TARGET_VERSION="$1"; shift ;;
            esac
            ;;
        -c|--clean) CLEAN_INSTALL=true; shift ;;
        -l|--only-luci) ONLY_LUCI=true; shift ;;
        -*) msg err "Unknown option: $1" ;;
        *) msg err "Unknown argument: $1. Use --github flag to specify version." ;;
    esac
done

msg head "System checks"

detect_package_manager
msg ok "Package manager: ${C_BOLD}$PACKAGE_MANAGER${C_RESET}"

msg info "Checking connectivity"
if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
    msg ok "Connectivity confirmed"
else
    msg err "No internet connection"
fi

ensure_direct_resolver

ensure_command /usr/bin/unzip unzip
ensure_command /usr/bin/curl curl
ensure_command /usr/bin/jsonfilter jsonfilter

DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown Device")
msg info "Device: ${C_BOLD}$DEVICE_MODEL${C_RESET}"

FREE_SPACE=$(df -k /tmp | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_SPACE_KB" ]; then
    msg err "Not enough space in /tmp: need ${MIN_SPACE_KB} KB, found ${FREE_SPACE} KB"
else
    msg ok "Space available in /tmp: ${FREE_SPACE} KB"
fi

msg head "Dependencies"

ensure_dnsmasq_full

msg info "Checking kernel modules"
for module in kmod-nft-tproxy kmod-nft-socket; do
    if ! pkg_is_installed "$module"; then
        msg info "Installing $module"
        pkg_install "$module" || msg err "Failed to install $module"
        msg ok "$module installed"
    else
        msg ok "$module already installed"
    fi
done

msg head "Platform"

ARCH=$(get_architecture)
if [ -z "$ARCH" ]; then
    msg err "Failed to detect architecture"
fi
msg ok "Architecture: ${C_BOLD}$ARCH${C_RESET}"

RELEASE_VER=$(get_release_version)
if [ -n "$RELEASE_VER" ]; then
    msg ok "OpenWrt release: ${C_BOLD}$RELEASE_VER${C_RESET}"
fi

msg head "Preparation"
rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || msg err "Failed to prepare temp directory"

for config_file in "$CONFIG_DIR"/passwall2*; do
    [ -f "$config_file" ] || continue
    case "$config_file" in
        *.bak*) continue ;;
    esac
    BACKUP_FILE="$config_file-$BACKUP_SUFFIX.bak"
    cp "$config_file" "$BACKUP_FILE"
    msg ok "Backed up config: $BACKUP_FILE"
done

if [ "$GITHUB_MODE" = false ]; then
    msg head "Feed installation"

    if [ -z "$RELEASE_VER" ]; then
        msg err "OpenWrt release not detected"
    fi

    msg info "Configuring feeds"
    msg info "Downloading feed key"
    install_feed_key

    msg info "Writing feed entries"
    case "$PACKAGE_MANAGER" in
        apk)
            mkdir -p /etc/apk/repositories.d || msg err "Failed to prepare apk repositories directory"
            FEED_CONFIG="/etc/apk/repositories.d/customfeeds.list"
            [ -f "$FEED_CONFIG" ] && cp "$FEED_CONFIG" "$FEED_CONFIG.bak"
            > "$FEED_CONFIG"
            ;;
        opkg)
            FEED_CONFIG="/etc/opkg/customfeeds.conf"
            [ -f "$FEED_CONFIG" ] && cp "$FEED_CONFIG" "$FEED_CONFIG.bak"
            > "$FEED_CONFIG"
            ;;
    esac

    for feed in $FEED_NAMES; do
        FEED_URL=$(get_feed_url "$feed")
        case "$PACKAGE_MANAGER" in
            apk) echo "$FEED_URL" >> "$FEED_CONFIG" ;;
            opkg) echo "src/gz $feed $FEED_URL" >> "$FEED_CONFIG" ;;
        esac
        msg ok "Added feed: $feed"
    done

    msg head "Package discovery"
    msg info "Checking installed Passwall packages"

    msg head "Install"
    msg info "Updating package lists"
    UPDATE_LOG=$(mktemp /tmp/passwall2-update.XXXXXX) || msg err "Failed to create temp file"
    if pkg_update_feed "$UPDATE_LOG"; then
        cat "$UPDATE_LOG"
        rm -f "$UPDATE_LOG"
    else
        cat "$UPDATE_LOG"
        rm -f "$UPDATE_LOG"
        msg err "Failed to update package lists"
    fi

    FEED_PACKAGES_FILE=$(mktemp /tmp/passwall2-feed-packages.XXXXXX) || msg err "Failed to create temp file"
    INSTALLED_PACKAGES_FILE=$(mktemp /tmp/passwall2-installed-packages.XXXXXX) || msg err "Failed to create temp file"
    UPGRADABLE_PACKAGES_FILE=$(mktemp /tmp/passwall2-upgradable-packages.XXXXXX) || msg err "Failed to create temp file"

    list_feed_packages > "$FEED_PACKAGES_FILE"
    list_installed_packages > "$INSTALLED_PACKAGES_FILE"
    list_upgradable_packages > "$UPGRADABLE_PACKAGES_FILE"

    ensure_feed_packages_available

    PASSWALL_INSTALLED_PACKAGES=$(grep -Fxf "$INSTALLED_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    PASSWALL_UPGRADABLE_PACKAGES=$(grep -Fxf "$UPGRADABLE_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    rm -f "$FEED_PACKAGES_FILE" "$INSTALLED_PACKAGES_FILE" "$UPGRADABLE_PACKAGES_FILE"

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing Passwall installation"

        REMOVE_LOG=$(mktemp /tmp/passwall2-remove.XXXXXX) || msg err "Failed to create temp file"

        if pkg_is_installed luci-app-passwall2; then
            msg info "Removing luci-app-passwall2"
            if ! pkg_remove_force luci-app-passwall2 >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall2"
            fi
        fi

        if [ -n "$PASSWALL_INSTALLED_PACKAGES" ]; then
            msg info "Removing: $PASSWALL_INSTALLED_PACKAGES"
            if ! pkg_remove_force $PASSWALL_INSTALLED_PACKAGES >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall packages"
            fi
        else
            msg info "No additional installed Passwall feed packages to remove"
        fi

        RUNTIME_INSTALLED_PACKAGES=$(list_installed_named_packages "$FEED_RUNTIME_PACKAGES")
        if [ -n "$RUNTIME_INSTALLED_PACKAGES" ]; then
            msg info "Removing runtime packages: $RUNTIME_INSTALLED_PACKAGES"
            if ! pkg_remove_force $RUNTIME_INSTALLED_PACKAGES >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall runtime packages"
            fi
        else
            msg info "No installed Passwall runtime packages to remove"
        fi

        rm -f "$REMOVE_LOG"
        msg ok "Existing packages removed"
    fi

    msg head "Install"
    msg info "Installing Passwall2"
    INSTALL_LOG=$(mktemp /tmp/passwall2-install.XXXXXX) || msg err "Failed to create temp file"
    if pkg_install_feed luci-app-passwall2 >"$INSTALL_LOG" 2>&1; then
        cat "$INSTALL_LOG"
        print_pkg_warnings "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg ok "Passwall2 installed"
    else
        cat "$INSTALL_LOG"
        print_space_hint "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg err "Failed to install Passwall2"
    fi

    msg head "Runtime packages"
    RUNTIME_LOG=$(mktemp /tmp/passwall2-runtime.XXXXXX) || msg err "Failed to create temp file"
    if install_available_feed_packages "$FEED_RUNTIME_PACKAGES" >"$RUNTIME_LOG" 2>&1; then
        cat "$RUNTIME_LOG"
        print_pkg_warnings "$RUNTIME_LOG"
        rm -f "$RUNTIME_LOG"
        msg ok "Runtime packages installed"
    else
        cat "$RUNTIME_LOG"
        print_space_hint "$RUNTIME_LOG"
        rm -f "$RUNTIME_LOG"
        msg err "Failed to install runtime packages"
    fi

    msg head "Passwall packages"
    if [ "$CLEAN_INSTALL" = true ]; then
        TARGET_PASSWALL_PACKAGES="$PASSWALL_INSTALLED_PACKAGES"
    else
        TARGET_PASSWALL_PACKAGES="$PASSWALL_UPGRADABLE_PACKAGES"
    fi

    if [ -n "$TARGET_PASSWALL_PACKAGES" ]; then
        if [ "$CLEAN_INSTALL" = true ]; then
            msg info "Installing: $TARGET_PASSWALL_PACKAGES"
        else
            msg info "Refreshing: $TARGET_PASSWALL_PACKAGES"
        fi

        REFRESH_LOG=$(mktemp /tmp/passwall2-refresh.XXXXXX) || msg err "Failed to create temp file"
        if pkg_install_feed $TARGET_PASSWALL_PACKAGES >"$REFRESH_LOG" 2>&1; then
            cat "$REFRESH_LOG"
            print_pkg_warnings "$REFRESH_LOG"
            rm -f "$REFRESH_LOG"
        else
            cat "$REFRESH_LOG"
            print_space_hint "$REFRESH_LOG"
            rm -f "$REFRESH_LOG"
            msg err "Failed to refresh Passwall packages"
        fi

        msg ok "Passwall packages refreshed"
    else
        if [ "$CLEAN_INSTALL" = true ]; then
            msg info "No installed Passwall packages to refresh"
        else
            msg info "No Passwall package updates available"
        fi
    fi
else
    msg head "GitHub installation"
    msg info "Fetching release metadata"

    if [ -z "$TARGET_VERSION" ]; then
        API_URL="$REPO_URL/latest"
    else
        API_URL="$REPO_URL/tags/$TARGET_VERSION"
    fi
    
    API_RESPONSE=$(curl -s --fail "$API_URL")
    if [ $? -ne 0 ]; then
        msg err "Failed to fetch release metadata from GitHub"
    fi

    RELEASE_TAG=$(echo "$API_RESPONSE" | jsonfilter -e '@.tag_name')
    msg ok "Release: ${C_BOLD}$RELEASE_TAG${C_RESET}"

    case "$PACKAGE_TYPE" in
        apk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2-" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
        ipk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2_" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
    esac

    ZIP_FILENAME=""

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Resolving package set"
        SUPPORTED_ARCHS=$(pkg_print_architectures)

        for arch in $SUPPORTED_ARCHS; do
            CANDIDATE_NAME="passwall_packages_${PACKAGE_TYPE}_${arch}.zip"

            if echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep -q "^${CANDIDATE_NAME}$"; then
                ZIP_FILENAME="$CANDIDATE_NAME"
                msg ok "Binary package: ${C_BOLD}$ZIP_FILENAME${C_RESET}"
                break
            fi
        done

        if [ -z "$ZIP_FILENAME" ]; then
            msg warn "No binary package matched detected architectures"
            echo "$SUPPORTED_ARCHS"
            msg warn "Available release assets:"
            echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep ".zip"
            msg err "No compatible binary package found. Use --only-luci for a LuCI-only install"
        fi
    else
        msg info "Skipping binary package lookup"
    fi

    msg head "Download"

    if [ -n "$LUCI_FILENAME" ]; then
        msg info "Downloading LuCI package"
        curl -L -s --fail -o "$LUCI_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$LUCI_FILENAME"
        [ -s "$LUCI_FILENAME" ] || msg err "Failed to download LuCI package."
    else
        msg err "LuCI package not found in release assets."
    fi

    if [ "$ONLY_LUCI" = false ] && [ -n "$ZIP_FILENAME" ]; then
        msg info "Downloading binary archive"
        curl -L -s --fail -o "$ZIP_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$ZIP_FILENAME"

        if [ -s "$ZIP_FILENAME" ]; then
            msg ok "Binary archive downloaded"
            unzip -q -j "$ZIP_FILENAME" && rm "$ZIP_FILENAME"
            msg ok "Binary archive unpacked"
        else
            msg err "Failed to download binary ZIP. File is empty."
        fi
    fi

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing installation"
        pkg_remove_force luci-app-passwall2 >/dev/null 2>&1

        if [ "$ONLY_LUCI" = false ]; then
            for pkg_file in *."$PACKAGE_TYPE"; do
                [ -f "$pkg_file" ] || continue
                [ "$pkg_file" = "$LUCI_FILENAME" ] && continue
                pkg_name=$(get_local_package_name "$pkg_file")
                if [ "$pkg_name" != "libc" ] && [ "$pkg_name" != "kernel" ]; then
                    [ "$pkg_name" = "simple-obfs-client" ] && pkg_remove_force simple-obfs >/dev/null 2>&1
                    pkg_remove_force "$pkg_name" >/dev/null 2>&1
                fi
            done
        fi
        msg ok "Existing packages removed"
    fi

    msg head "Install"

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Installing packages"
        for pkg_file in *."$PACKAGE_TYPE"; do
            [ -f "$pkg_file" ] || continue
            [ "$pkg_file" = "$LUCI_FILENAME" ] && continue

            ERROR_LOG=$(mktemp)
            if pkg_install_local "$pkg_file" >/dev/null 2>"$ERROR_LOG"; then
                echo -e "${C_GREEN}[OK]${C_RESET} ${pkg_file}"
                rm "$pkg_file"
            else
                echo -e "${C_RED}[ERROR]${C_RESET} ${pkg_file}"
                if [ -s "$ERROR_LOG" ]; then
                    echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
                    cat "$ERROR_LOG" | sed 's/^/    /'
                    if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                        echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
                    fi
                fi
            fi
            rm -f "$ERROR_LOG"
        done
    fi

    msg info "Installing LuCI package"
    ERROR_LOG=$(mktemp)
    if pkg_install_local "$LUCI_FILENAME" >/dev/null 2>"$ERROR_LOG"; then
        rm "$LUCI_FILENAME"
        rm -f "$ERROR_LOG"
        msg ok "LuCI installed"
    else
        if [ -s "$ERROR_LOG" ]; then
            echo -e "${C_YELLOW}[WARN]${C_RESET} Error details:"
            cat "$ERROR_LOG" | sed 's/^/  /'
            if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$ERROR_LOG"; then
                echo -e "${C_YELLOW}[WARN]${C_RESET} Suggestion: try --clean to free space"
            fi
        fi
        rm -f "$ERROR_LOG"
        msg err "Failed to install LuCI package"
    fi
fi

cd /tmp && rm -rf "$TEMP_DIR"

msg ok "Installation completed"

exit 0

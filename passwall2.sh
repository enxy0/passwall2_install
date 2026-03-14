#!/bin/sh

PACKAGE_TYPE="ipk"
REPO_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases"
BASE_DOWNLOAD_URL="https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download"
TEMP_DIR="/tmp/passwall2_update"
CONFIG_DIR="/etc/config"
BACKUP_SUFFIX=$(date +%Y%m%d)
MIN_SPACE_KB=20480

FEED_BASE_URL="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
FEED_KEY_URL="${FEED_BASE_URL}/passwall.pub"

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

get_architecture() {
    local arch=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -1)

    if [ -z "$arch" ] && [ -r /etc/openwrt_release ]; then
        arch=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
    fi

    echo "$arch"
}

get_release_version() {
    if [ -r /etc/openwrt_release ]; then
        . /etc/openwrt_release
        echo "${DISTRIB_RELEASE%.*}"
    fi
}

list_feed_packages() {
    for feed_file in /var/opkg-lists/passwall_luci /var/opkg-lists/passwall_packages /var/opkg-lists/passwall2; do
        [ -f "$feed_file" ] || continue
        gzip -dc "$feed_file" 2>/dev/null || cat "$feed_file" 2>/dev/null
    done | awk '/^Package: / {print $2}' | sort -u
}

list_installed_packages() {
    opkg list-installed | awk '{print $1}' | sort -u
}

list_upgradable_packages() {
    opkg list-upgradable | awk '{print $1}' | sort -u
}

print_opkg_warnings() {
    local log_file="$1"

    if grep -qE 'resolve_conffiles:|^Collected errors:$' "$log_file"; then
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

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) show_help ;;
        -g|--github)
            GITHUB_MODE=true
            shift
            if [ -n "$1" ] && case "$1" in -*) ;; *) true;; esac; then
                TARGET_VERSION="$1"
                shift
            fi
            ;;
        -c|--clean) CLEAN_INSTALL=true; shift ;;
        -l|--only-luci) ONLY_LUCI=true; shift ;;
        -*) msg err "Unknown option: $1" ;;
        *) msg err "Unknown argument: $1. Use --github flag to specify version." ;;
    esac
done

msg head "System checks"

msg info "Checking connectivity"
if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
    msg ok "Connectivity confirmed"
else
    msg err "No internet connection"
fi

[ -x /usr/bin/unzip ] || { msg warn "Installing unzip"; opkg update && opkg install unzip; }
[ -x /usr/bin/curl ] || { msg warn "Installing curl"; opkg update && opkg install curl; }
[ -x /usr/bin/jsonfilter ] || { msg warn "Installing jsonfilter"; opkg update && opkg install jsonfilter; }

DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown Device")
msg info "Device: ${C_BOLD}$DEVICE_MODEL${C_RESET}"

FREE_SPACE=$(df -k /tmp | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_SPACE_KB" ]; then
    msg err "Not enough space in /tmp: need ${MIN_SPACE_KB} KB, found ${FREE_SPACE} KB"
else
    msg ok "Space available in /tmp: ${FREE_SPACE} KB"
fi

msg head "Dependencies"

msg info "Checking dnsmasq-full"
if ! opkg list-installed | grep -q "^dnsmasq-full "; then
    if opkg list-installed | grep -q "^dnsmasq "; then
        msg info "Removing dnsmasq"
        opkg remove dnsmasq || msg err "Failed to remove dnsmasq"
    fi
    msg info "Installing dnsmasq-full"
    opkg install dnsmasq-full || msg err "Failed to install dnsmasq-full"
    msg ok "dnsmasq-full installed"
else
    msg ok "dnsmasq-full already installed"
fi

msg info "Checking kernel modules"
for module in kmod-nft-tproxy kmod-nft-socket; do
    if ! opkg list-installed | grep -q "^$module "; then
        msg info "Installing $module"
        opkg install "$module" || msg err "Failed to install $module"
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
    curl -s -L --fail -o /tmp/passwall.pub "$FEED_KEY_URL" || msg err "Failed to download feed key"
    opkg-key add /tmp/passwall.pub || msg err "Failed to add feed key"
    rm -f /tmp/passwall.pub
    msg ok "Feed key added"

    msg info "Writing feed entries"
    [ -f /etc/opkg/customfeeds.conf ] && cp /etc/opkg/customfeeds.conf /etc/opkg/customfeeds.conf.bak
    > /etc/opkg/customfeeds.conf

    for feed in passwall_luci passwall_packages passwall2; do
        echo "src/gz $feed https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-$RELEASE_VER/$ARCH/$feed" >> /etc/opkg/customfeeds.conf
        msg ok "Added feed: $feed"
    done

    msg head "Package discovery"
    msg info "Checking installed Passwall packages"

    msg head "Install"
    msg info "Updating package lists"
    opkg update || msg err "Failed to update package lists"

    FEED_PACKAGES_FILE=$(mktemp /tmp/passwall2-feed-packages.XXXXXX) || msg err "Failed to create temp file"
    INSTALLED_PACKAGES_FILE=$(mktemp /tmp/passwall2-installed-packages.XXXXXX) || msg err "Failed to create temp file"
    UPGRADABLE_PACKAGES_FILE=$(mktemp /tmp/passwall2-upgradable-packages.XXXXXX) || msg err "Failed to create temp file"

    list_feed_packages > "$FEED_PACKAGES_FILE"
    list_installed_packages > "$INSTALLED_PACKAGES_FILE"
    list_upgradable_packages > "$UPGRADABLE_PACKAGES_FILE"

    PASSWALL_INSTALLED_PACKAGES=$(grep -Fxf "$INSTALLED_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    PASSWALL_UPGRADABLE_PACKAGES=$(grep -Fxf "$UPGRADABLE_PACKAGES_FILE" "$FEED_PACKAGES_FILE" | grep -vx "luci-app-passwall2" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    rm -f "$FEED_PACKAGES_FILE" "$INSTALLED_PACKAGES_FILE" "$UPGRADABLE_PACKAGES_FILE"

    if [ "$CLEAN_INSTALL" = true ]; then
        msg head "Cleanup"
        msg info "Removing existing Passwall installation"

        REMOVE_LOG=$(mktemp /tmp/passwall2-remove.XXXXXX) || msg err "Failed to create temp file"

        if opkg list-installed | grep -q "^luci-app-passwall2 "; then
            if ! opkg remove luci-app-passwall2 --force-depends >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall2"
            fi
        fi

        if [ -n "$PASSWALL_INSTALLED_PACKAGES" ]; then
            msg info "Removing: $PASSWALL_INSTALLED_PACKAGES"
            if ! opkg remove $PASSWALL_INSTALLED_PACKAGES --force-depends >"$REMOVE_LOG" 2>&1; then
                cat "$REMOVE_LOG"
                rm -f "$REMOVE_LOG"
                msg err "Failed to remove Passwall packages"
            fi
        else
            msg info "No installed Passwall packages to remove"
        fi

        rm -f "$REMOVE_LOG"
        msg ok "Existing packages removed"
    fi

    msg head "Install"
    msg info "Installing Passwall2"
    INSTALL_LOG=$(mktemp /tmp/passwall2-install.XXXXXX) || msg err "Failed to create temp file"
    if opkg install luci-app-passwall2 >"$INSTALL_LOG" 2>&1; then
        cat "$INSTALL_LOG"
        print_opkg_warnings "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg ok "Passwall2 installed"
    else
        cat "$INSTALL_LOG"
        print_space_hint "$INSTALL_LOG"
        rm -f "$INSTALL_LOG"
        msg err "Failed to install Passwall2"
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
        if opkg install $TARGET_PASSWALL_PACKAGES >"$REFRESH_LOG" 2>&1; then
            cat "$REFRESH_LOG"
            print_opkg_warnings "$REFRESH_LOG"
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

    LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2_" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1)

    ZIP_FILENAME=""

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Resolving package set"
        SUPPORTED_ARCHS=$(opkg print-architecture | awk '{print $2}' | awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}')

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
        opkg remove luci-app-passwall2 --force-depends >/dev/null 2>&1

        if [ "$ONLY_LUCI" = false ]; then
            for ipk in *.ipk; do
                pkg_name=$(echo "$ipk" | cut -d'_' -f1)
                if [ "$pkg_name" != "libc" ] && [ "$pkg_name" != "kernel" ]; then
                    [ "$pkg_name" = "simple-obfs-client" ] && opkg remove simple-obfs --force-depends >/dev/null 2>&1
                    opkg remove "$pkg_name" --force-depends >/dev/null 2>&1
                fi
            done
        fi
        msg ok "Existing packages removed"
    fi

    msg head "Install"

    if [ "$ONLY_LUCI" = false ]; then
        msg info "Installing packages"
        for ipk in *.ipk; do
            [ "$ipk" = "$LUCI_FILENAME" ] && continue

            ERROR_LOG=$(mktemp)
            if opkg install "$ipk" --force-reinstall >/dev/null 2>"$ERROR_LOG"; then
                echo -e "${C_GREEN}[OK]${C_RESET} ${ipk}"
                rm "$ipk"
            else
                echo -e "${C_RED}[ERROR]${C_RESET} ${ipk}"
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
    if opkg install "$LUCI_FILENAME" --force-reinstall >/dev/null 2>"$ERROR_LOG"; then
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

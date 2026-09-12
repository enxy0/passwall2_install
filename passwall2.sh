#!/bin/sh

SCRIPT_NAME="passwall2.sh"
PACKAGE_MANAGER=""
PACKAGE_TYPE=""
REPO_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall2/releases"
BASE_DOWNLOAD_URL="https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/download"
FEED_BASE_URL="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
FEED_APK_LIST="/etc/apk/repositories.d/passwall.list"
FEED_APK_KEY="/etc/apk/keys/openwrt-passwall-build.pem"
FEED_OPKG_CONF="/etc/opkg/customfeeds.conf"
FEED_FILE=""
FEED_LINE=""
FEED_URL=""
FEED_TEMP_FILE=""
FEED_ADDED=false
WANTED_CORES=""
TEMP_DIR="/tmp/passwall2_update"
CONFIG_DIR="/etc/config"
BACKUP_SUFFIX=$(date +%Y%m%d-%H%M%S)
MIN_SPACE_KB=20480
RESOLV_BACKUP=""
RESTORE_RESOLVER=false
BACKUP_FILES=""
RUNTIME_INSTALLED=0
RUNTIME_FAILED=0

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    C_RESET=$(printf '\033[0m')
    C_BOLD=$(printf '\033[1m')
    C_RED=$(printf '\033[1;31m')
    C_GREEN=$(printf '\033[1;32m')
    C_YELLOW=$(printf '\033[1;33m')
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
fi

cleanup() {
    remove_passwall_feed

    if [ -n "$FEED_TEMP_FILE" ]; then
        rm -f "$FEED_TEMP_FILE"
        FEED_TEMP_FILE=""
    fi

    if [ "$RESTORE_RESOLVER" = true ] && [ -n "$RESOLV_BACKUP" ] && [ -f "$RESOLV_BACKUP" ]; then
        cp "$RESOLV_BACKUP" /tmp/resolv.conf 2>/dev/null || true
        rm -f "$RESOLV_BACKUP"
    fi

    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

title() {
    printf '%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

section() {
    printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

line() {
    printf '  %s: %s\n' "$1" "$2"
}

note() {
    printf '  %s\n' "$1"
}

warn() {
    printf '\n%sWARN%s\n' "$C_YELLOW" "$C_RESET"
    printf '  %s\n' "$1"
}

fail() {
    printf '\n%sERROR%s\n' "$C_RED" "$C_RESET"
    printf '  %s\n' "$1"
    exit 1
}

success() {
    printf '  %s%s%s\n' "$C_GREEN" "$1" "$C_RESET"
}

msg() {
    case "$1" in
        ok)    success "$2" ;;
        err)   fail "$2" ;;
        warn)  warn "$2" ;;
        info)  note "$2" ;;
        head)  section "$2" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

format_kb() {
    local kb="$1"
    local mb=$(( (kb + 1023) / 1024 ))

    echo "${mb} MB"
}

print_error_log() {
    local log_file="$1"

    if [ -s "$log_file" ]; then
        note "Package manager output:"
        sed 's/^/    /' "$log_file"
        if grep -qiE "(space|No space left|disk full|available on filesystem|needs|verify_pkg_installable)" "$log_file"; then
            note "Try: $SCRIPT_NAME --clean"
        fi
    fi
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

pkg_upgrade_hint() {
    case "$PACKAGE_MANAGER" in
        apk) echo "apk update && apk add --upgrade $*" ;;
        opkg) echo "opkg update && opkg upgrade $*" ;;
    esac
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
        RESOLV_BACKUP="/tmp/resolv.conf.passwall2.$$.bak"
        cp /tmp/resolv.conf "$RESOLV_BACKUP" 2>/dev/null && RESTORE_RESOLVER=true
        {
            grep '^search ' /tmp/resolv.conf 2>/dev/null
            echo 'nameserver 9.9.9.9'
            echo 'nameserver 1.1.1.1'
        } > /tmp/resolv.conf
        if [ "$has_loopback" = true ]; then
            warn "Using temporary direct resolvers during installation. The original resolver will be restored before exit."
        else
            warn "No direct resolver is configured. A temporary resolver will be used during installation."
        fi
    fi
}

ensure_command() {
    local path="$1"
    local package="$2"

    [ -x "$path" ] && return 0
    note "Installing required tool: $package"
    pkg_update && pkg_install "$package" || msg err "Failed to install $package"
}

pkg_is_installed() {
    case "$PACKAGE_MANAGER" in
        apk) apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg list-installed | grep -q "^$1 " ;;
    esac
}

pkg_installed_version() {
    local name="$1"
    local entry=""

    case "$PACKAGE_MANAGER" in
        apk)
            entry=$(apk list --installed "$name" 2>/dev/null | awk 'NR==1 {print $1}')
            echo "${entry#$name-}"
            ;;
        opkg)
            opkg list-installed "$name" 2>/dev/null | awk 'NR==1 {print $3}'
            ;;
    esac
}

ensure_dnsmasq_full() {
    local dnsmasq_full_ipk=""
    local dnsmasq_log=""

    if pkg_is_installed dnsmasq-full; then
        return 0
    fi

    ensure_direct_resolver
    case "$PACKAGE_MANAGER" in
        opkg)
            if pkg_is_installed dnsmasq; then
                note "Preparing dnsmasq-full package..."
                dnsmasq_log=$(mktemp)
                if ! (cd "$TEMP_DIR" && opkg download dnsmasq-full) >"$dnsmasq_log" 2>&1; then
                    print_error_log "$dnsmasq_log"
                    rm -f "$dnsmasq_log"
                    msg err "Failed to download dnsmasq-full before replacing dnsmasq"
                fi
                rm -f "$dnsmasq_log"

                dnsmasq_full_ipk=$(ls "$TEMP_DIR"/dnsmasq-full_*.ipk 2>/dev/null | head -n 1)
                [ -n "$dnsmasq_full_ipk" ] || msg err "Downloaded dnsmasq-full package was not found"

                note "Replacing dnsmasq with dnsmasq-full"
                pkg_remove dnsmasq || msg err "Failed to remove dnsmasq"
                opkg install "$dnsmasq_full_ipk" || msg err "Failed to install dnsmasq-full"

                if [ -x /etc/init.d/dnsmasq ]; then
                    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || msg warn "dnsmasq restart failed; check DNS manually"
                fi
                return 0
            fi
            ;;
    esac

    note "Installing required package: dnsmasq-full"
    pkg_install dnsmasq-full || msg err "Failed to install dnsmasq-full"

    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || msg warn "dnsmasq restart failed; check DNS manually"
    fi
}

ensure_passwall_feed() {
    local arch=""
    local branch=""
    local feed_path=""
    local key_file=""
    local feed_tmp=""
    local expected=0
    local written=0

    # DISTRIB_ARCH is the OpenWrt package architecture the feed path needs; get_architecture can fall back to the CPU architecture.
    if [ -r /etc/openwrt_release ]; then
        arch=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
    fi
    branch=$(get_release_version)

    if [ -z "$branch" ] || [ -z "$arch" ]; then
        warn "Failed to read DISTRIB_RELEASE or DISTRIB_ARCH from /etc/openwrt_release."
        return 1
    fi

    case "$branch" in
        *SNAPSHOT*) feed_path="snapshots/packages/$arch/passwall_packages" ;;
        *) feed_path="releases/packages-$branch/$arch/passwall_packages" ;;
    esac

    FEED_URL="$FEED_BASE_URL/$feed_path"

    case "$PACKAGE_MANAGER" in
        apk)
            FEED_FILE="$FEED_APK_LIST"
            FEED_LINE="$FEED_URL/packages.adb"

            if [ -f "$FEED_FILE" ] && grep -qF "$FEED_LINE" "$FEED_FILE"; then
                line "Passwall feed" "$FEED_FILE (already configured)"
                return 0
            fi

            if [ ! -s "$FEED_APK_KEY" ]; then
                note "Downloading the passwall build signing key..."
                key_file="$TEMP_DIR/passwall-build-apk.pub"
                if ! curl -L -s --fail -o "$key_file" "$FEED_BASE_URL/apk.pub"; then
                    rm -f "$key_file"
                    warn "Failed to download the passwall build signing key."
                    return 1
                fi

                if ! grep -q 'BEGIN PUBLIC KEY' "$key_file"; then
                    rm -f "$key_file"
                    warn "The downloaded passwall build signing key is not a public key in PEM format."
                    return 1
                fi

                mkdir -p /etc/apk/keys || return 1
                if ! cp "$key_file" "$FEED_APK_KEY" || ! grep -q 'END PUBLIC KEY' "$FEED_APK_KEY"; then
                    rm -f "$FEED_APK_KEY" "$key_file"
                    warn "Failed to install the passwall build signing key into $FEED_APK_KEY."
                    return 1
                fi
                rm -f "$key_file"
            fi

            mkdir -p /etc/apk/repositories.d || return 1
            if ! echo "$FEED_LINE" > "$FEED_FILE" || ! grep -qF "$FEED_LINE" "$FEED_FILE"; then
                rm -f "$FEED_FILE"
                warn "Failed to write $FEED_FILE."
                return 1
            fi
            ;;
        opkg)
            FEED_FILE="$FEED_OPKG_CONF"
            FEED_LINE="src/gz passwall_packages $FEED_URL"

            if [ -f "$FEED_FILE" ] && grep -qF "$FEED_LINE" "$FEED_FILE"; then
                line "Passwall feed" "$FEED_FILE (already configured)"
                return 0
            fi

            note "Downloading the passwall build signing key..."
            key_file="$TEMP_DIR/passwall-build-ipk.pub"
            if ! curl -L -s --fail -o "$key_file" "$FEED_BASE_URL/ipk.pub"; then
                rm -f "$key_file"
                warn "Failed to download the passwall build signing key."
                return 1
            fi

            if ! opkg-key add "$key_file" >/dev/null 2>&1; then
                rm -f "$key_file"
                warn "Failed to add the passwall build signing key with opkg-key."
                return 1
            fi
            rm -f "$key_file"

            if [ -f "$FEED_FILE" ] && grep -q "passwall_packages" "$FEED_FILE"; then
                note "Replacing an outdated passwall feed line in $FEED_FILE"
            fi

            feed_tmp="$FEED_FILE.passwall2.$$"
            FEED_TEMP_FILE="$feed_tmp"
            if ! touch "$feed_tmp" 2>/dev/null; then
                FEED_TEMP_FILE=""
                warn "Failed to write $FEED_FILE. The existing feed configuration was left unchanged."
                return 1
            fi

            expected=$(grep -cv "passwall_packages" "$FEED_FILE" 2>/dev/null)
            expected=$(( ${expected:-0} + 1 ))
            {
                grep -v "passwall_packages" "$FEED_FILE" 2>/dev/null
                echo "$FEED_LINE"
            } > "$feed_tmp" 2>/dev/null
            written=$(wc -l < "$feed_tmp" 2>/dev/null)

            if [ "${written:-0}" -ne "$expected" ] ||
               ! grep -qF "$FEED_LINE" "$feed_tmp" 2>/dev/null || ! mv "$feed_tmp" "$FEED_FILE"; then
                rm -f "$feed_tmp"
                FEED_TEMP_FILE=""
                warn "Failed to write $FEED_FILE. The existing feed configuration was left unchanged."
                return 1
            fi
            FEED_TEMP_FILE=""
            ;;
    esac

    FEED_ADDED=true
    line "Passwall feed" "$FEED_FILE"
    return 0
}

remove_passwall_feed() {
    local temp_conf=""
    local status=0
    local expected=0
    local written=0

    [ "$FEED_ADDED" = true ] || return 0
    FEED_ADDED=false

    case "$PACKAGE_MANAGER" in
        apk)
            rm -f "$FEED_FILE"
            ;;
        opkg)
            [ -f "$FEED_FILE" ] || return 0
            [ -n "$FEED_LINE" ] || return 0

            temp_conf="$FEED_FILE.passwall2.$$"
            FEED_TEMP_FILE="$temp_conf"
            if touch "$temp_conf" 2>/dev/null; then
                expected=$(grep -cvF "$FEED_LINE" "$FEED_FILE" 2>/dev/null)
                grep -vF "$FEED_LINE" "$FEED_FILE" > "$temp_conf" 2>/dev/null
                status=$?
                written=$(wc -l < "$temp_conf" 2>/dev/null)

                if { [ "$status" -eq 0 ] || [ "$status" -eq 1 ]; } &&
                   [ "${written:-0}" -eq "${expected:-0}" ] && mv "$temp_conf" "$FEED_FILE"; then
                    FEED_TEMP_FILE=""
                    return 0
                fi
            fi

            rm -f "$temp_conf"
            FEED_TEMP_FILE=""
            warn "Failed to edit $FEED_FILE. Remove this feed line by hand: $FEED_LINE"
            ;;
    esac
}

passwall_feed_present() {
    case "$PACKAGE_MANAGER" in
        apk) [ -s "$FEED_APK_LIST" ] ;;
        opkg) [ -f "$FEED_OPKG_CONF" ] && grep -q "passwall_packages" "$FEED_OPKG_CONF" ;;
        *) return 1 ;;
    esac
}

feed_named_in_errors() {
    local log_file="$1"
    local needle="$FEED_URL"

    [ -s "$log_file" ] || return 1
    [ -n "$needle" ] || needle="$FEED_BASE_URL"

    grep -iE "(error|warning|fail|denied|refused|not found|unavailable|unable)" "$log_file" 2>/dev/null |
        grep -qF "$needle"
}

ensure_cores() {
    local core=""
    local before=""
    local after=""
    local core_log=""
    local update_log=""
    local update_ok=true
    local feed_hint=""

    WANTED_CORES=""
    [ "$INSTALL_XRAY" = true ] && WANTED_CORES="$WANTED_CORES xray-core"
    [ "$INSTALL_SING_BOX" = true ] && WANTED_CORES="$WANTED_CORES sing-box"

    if [ -z "$WANTED_CORES" ]; then
        note "Proxy cores skipped (--no-xray and --no-sing-box)"
        return 0
    fi

    note "Checking proxy cores..."
    ensure_direct_resolver

    if [ "$USE_FEED" = true ]; then
        if ! ensure_passwall_feed; then
            remove_passwall_feed
            warn "The passwall build feed was not configured. The proxy cores will come from the official OpenWrt feeds and may be several months old."
        fi
    else
        note "Passwall build feed skipped (--no-feed)"
    fi

    update_log=$(mktemp)
    pkg_update >"$update_log" 2>&1 || update_ok=false

    if feed_named_in_errors "$update_log"; then
        print_error_log "$update_log"
        if [ "$FEED_ADDED" = true ]; then
            remove_passwall_feed
            warn "Failed to read the passwall build feed. The feed was removed. The proxy cores will come from the official OpenWrt feeds and may be several months old."
            pkg_update >/dev/null 2>&1 || true
        else
            feed_hint="$FEED_FILE"
            if [ -z "$feed_hint" ]; then
                case "$PACKAGE_MANAGER" in
                    apk) feed_hint="$FEED_APK_LIST" ;;
                    opkg) feed_hint="$FEED_OPKG_CONF" ;;
                esac
            fi
            warn "The passwall build feed configured in $feed_hint is unreachable and is the likely cause. Remove that feed line or run this script again later. The proxy cores may be installed from a stale index."
        fi
    else
        FEED_ADDED=false
        if [ "$update_ok" = false ]; then
            print_error_log "$update_log"
            warn "Failed to refresh the package lists. The proxy cores may be installed from a stale index."
        fi
    fi
    rm -f "$update_log"

    for core in $WANTED_CORES; do
        before=$(pkg_installed_version "$core")
        core_log=$(mktemp)
        if pkg_install "$core" >/dev/null 2>"$core_log"; then
            after=$(pkg_installed_version "$core")
            if [ -z "$before" ]; then
                line "$core" "installed${after:+ $after}"
            elif [ "$before" != "$after" ]; then
                line "$core" "upgraded $before -> $after"
            else
                line "$core" "already current${before:+ ($before)}"
            fi
        else
            print_error_log "$core_log"
            warn "Failed to install $core. Install a core manually if Passwall2 has none."
        fi
        rm -f "$core_log"
    done
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

show_help() {
    echo "Usage: $SCRIPT_NAME [OPTIONS] [VER]"
    echo ""
    echo "Description:"
    echo "  Install Passwall2 from GitHub releases."
    echo "  Automatically uses apk or opkg, depending on availability."
    echo "  Upstream releases no longer ship a proxy core, so xray-core and"
    echo "  sing-box are installed from the passwall build feed, which is"
    echo "  much newer than the official OpenWrt feeds. The feed stays"
    echo "  configured ($FEED_APK_LIST for apk,"
    echo "  $FEED_OPKG_CONF for opkg), so the cores can be"
    echo "  updated later without this script."
    echo ""
    echo "Options:"
    echo "  [VER]               Optional release version (e.g., 26.6.3-1)."
    echo "  -c, --clean         Clean install (remove old packages first)."
    echo "  -l, --only-luci     Install only LuCI interface (skip binaries)."
    echo "      --no-xray       Do not install xray-core."
    echo "      --no-sing-box   Do not install sing-box (~44 MB on flash)."
    echo "      --no-feed       Do not add the passwall build feed; install the"
    echo "                      cores from the feeds the router already has."
    echo "  -h, --help          Show this help message."
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME                  Install latest release"
    echo "  $SCRIPT_NAME 26.6.3-1         Install specific release"
    echo "  $SCRIPT_NAME -c               Clean install of latest release"
    echo "  $SCRIPT_NAME -l               Install only LuCI package"
    echo "  $SCRIPT_NAME --no-sing-box    Install latest release with xray-core only"
    echo "  $SCRIPT_NAME --no-feed        Install the cores from the existing feeds"
    echo ""
    exit 0
}

TARGET_VERSION=""
CLEAN_INSTALL=false
ONLY_LUCI=false
INSTALL_XRAY=true
INSTALL_SING_BOX=true
USE_FEED=true

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) show_help ;;
        -c|--clean) CLEAN_INSTALL=true; shift ;;
        -l|--only-luci) ONLY_LUCI=true; shift ;;
        --no-xray) INSTALL_XRAY=false; shift ;;
        --no-sing-box) INSTALL_SING_BOX=false; shift ;;
        --no-feed) USE_FEED=false; shift ;;
        -*) msg err "Unknown option: $1" ;;
        *)
            if [ -n "$TARGET_VERSION" ]; then
                msg err "Unknown argument: $1. Only one release version can be specified."
            fi
            TARGET_VERSION="$1"
            shift
            ;;
    esac
done

title "Passwall2 installer"

detect_package_manager

rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR" || msg err "Failed to prepare temp directory"

if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
    INTERNET_STATUS="available"
else
    msg err "No internet connection"
fi

ensure_direct_resolver

ensure_command /usr/bin/unzip unzip
ensure_command /usr/bin/curl curl
ensure_command /usr/bin/jsonfilter jsonfilter

DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown Device")

FREE_SPACE=$(df -k /tmp | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_SPACE_KB" ]; then
    msg err "Not enough space in /tmp: need ${MIN_SPACE_KB} KB, found ${FREE_SPACE} KB"
fi

ARCH=$(get_architecture)
if [ -z "$ARCH" ]; then
    msg err "Failed to detect architecture"
fi

RELEASE_VER=$(get_release_version)

section "System"
line "Device" "$DEVICE_MODEL"
[ -n "$RELEASE_VER" ] && line "OpenWrt" "$RELEASE_VER"
line "Package manager" "$PACKAGE_MANAGER"
line "Architecture" "$ARCH"
line "Internet" "$INTERNET_STATUS"
line "Free /tmp space" "$(format_kb "$FREE_SPACE")"

ensure_dnsmasq_full

for module in kmod-nft-tproxy kmod-nft-socket; do
    if ! pkg_is_installed "$module"; then
        note "Installing required kernel module: $module"
        pkg_install "$module" || msg err "Failed to install $module"
    fi
done

section "Preparing"
cd "$TEMP_DIR" || msg err "Failed to prepare temp directory"

for config_file in "$CONFIG_DIR"/passwall2*; do
    [ -f "$config_file" ] || continue
    case "$config_file" in
        *.bak*) continue ;;
    esac
    BACKUP_FILE="$config_file-$BACKUP_SUFFIX.bak"
    cp "$config_file" "$BACKUP_FILE"
    BACKUP_FILES="$BACKUP_FILES $BACKUP_FILE"
    line "Config backup" "$BACKUP_FILE"
done

if [ -z "$BACKUP_FILES" ]; then
    note "No existing Passwall2 config found"
fi

section "Release"
line "Source" "GitHub"

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
line "Version" "$RELEASE_TAG"

case "$PACKAGE_TYPE" in
    apk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2-" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
    ipk) LUCI_FILENAME=$(echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep "^luci-app-passwall2_" | grep -E "\.${PACKAGE_TYPE}$" | head -n 1) ;;
esac

ZIP_FILENAME=""

if [ "$ONLY_LUCI" = false ]; then
    SUPPORTED_ARCHS=$(pkg_print_architectures)

    for arch in $SUPPORTED_ARCHS; do
        CANDIDATE_NAME="passwall_packages_${PACKAGE_TYPE}_${arch}.zip"

        if echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep -q "^${CANDIDATE_NAME}$"; then
            ZIP_FILENAME="$CANDIDATE_NAME"
            break
        fi
    done

    if [ -z "$ZIP_FILENAME" ]; then
        warn "This release does not include a runtime archive for $ARCH."
        note "Available archives:"
        echo "$API_RESPONSE" | jsonfilter -e '@.assets[*].name' | grep ".zip" | sed 's/^/    /'
        msg err "No compatible binary package found. Use --only-luci for a LuCI-only install"
    fi
else
    line "Runtime archive" "skipped (--only-luci)"
fi

line "LuCI package" "$LUCI_FILENAME"
[ -n "$LUCI_FILENAME" ] || msg err "LuCI package not found in release assets."
[ -n "$ZIP_FILENAME" ] && line "Runtime archive" "$ZIP_FILENAME"

section "Download"

if [ -n "$LUCI_FILENAME" ]; then
    note "Downloading LuCI package..."
    curl -L -s --fail -o "$LUCI_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$LUCI_FILENAME"
    [ -s "$LUCI_FILENAME" ] || msg err "Failed to download LuCI package."
else
    msg err "LuCI package not found in release assets."
fi

if [ "$ONLY_LUCI" = false ] && [ -n "$ZIP_FILENAME" ]; then
    note "Downloading runtime archive..."
    curl -L -s --fail -o "$ZIP_FILENAME" "$BASE_DOWNLOAD_URL/$RELEASE_TAG/$ZIP_FILENAME"

    if [ -s "$ZIP_FILENAME" ]; then
        unzip -q -j "$ZIP_FILENAME" && rm "$ZIP_FILENAME"
        success "Packages downloaded"
    else
        msg err "Failed to download binary ZIP. File is empty."
    fi
fi

if [ "$CLEAN_INSTALL" = true ]; then
    section "Cleanup"
    note "Removing existing installation..."
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
    success "Existing packages removed"
fi

section "Install"

if [ "$ONLY_LUCI" = false ]; then
    note "Installing runtime packages..."
    for pkg_file in *."$PACKAGE_TYPE"; do
        [ -f "$pkg_file" ] || continue
        [ "$pkg_file" = "$LUCI_FILENAME" ] && continue

        ERROR_LOG=$(mktemp)
        if pkg_install_local "$pkg_file" >/dev/null 2>"$ERROR_LOG"; then
            RUNTIME_INSTALLED=$((RUNTIME_INSTALLED + 1))
            rm "$pkg_file"
        else
            RUNTIME_FAILED=$((RUNTIME_FAILED + 1))
            warn "Failed to install $pkg_file."
            print_error_log "$ERROR_LOG"
        fi
        rm -f "$ERROR_LOG"
    done

    if [ "$RUNTIME_FAILED" -gt 0 ]; then
        msg err "Runtime package installation failed: ${RUNTIME_FAILED} failed, ${RUNTIME_INSTALLED} installed."
    fi

    line "Runtime packages" "${RUNTIME_INSTALLED} installed"

    ensure_cores
fi

note "Installing LuCI package..."
ERROR_LOG=$(mktemp)
if pkg_install_local "$LUCI_FILENAME" >/dev/null 2>"$ERROR_LOG"; then
    rm "$LUCI_FILENAME"
    rm -f "$ERROR_LOG"
    line "LuCI package" "installed"
else
    print_error_log "$ERROR_LOG"
    rm -f "$ERROR_LOG"
    msg err "Failed to install LuCI package"
fi

if [ ! -e /usr/bin/xray ] && [ ! -e /usr/bin/sing-box ]; then
    warn "No proxy core is installed. Passwall2 will not start without xray-core or sing-box."
    note "Install one with: $SCRIPT_NAME (default), or manually: apk add xray-core (opkg install xray-core)"
fi

section "Done"
success "Passwall2 was installed successfully."
line "Version" "$RELEASE_TAG"
[ "$ONLY_LUCI" = false ] && line "Runtime packages" "${RUNTIME_INSTALLED} installed"
for backup_file in $BACKUP_FILES; do
    line "Config backup" "$backup_file"
done
note "Open LuCI and go to Services -> Passwall2."

if [ "$ONLY_LUCI" = false ] && [ -n "$WANTED_CORES" ] && passwall_feed_present; then
    note "Update the proxy cores later: $(pkg_upgrade_hint $WANTED_CORES)"
    note "A bare '$PACKAGE_MANAGER upgrade' is not recommended on OpenWrt; upgrade only the packages you need."
fi

exit 0

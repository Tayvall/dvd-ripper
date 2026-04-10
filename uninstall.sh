#!/usr/bin/env bash
# =============================================================================
#  uninstall.sh — Remove dvd-ripper and its dependencies
#  Supports: Arch/CachyOS, Ubuntu/Debian, Fedora/RHEL
#  Will NOT delete your movie library or log files unless you confirm
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dvd-ripper"
CONFIG_FILE="$CONFIG_DIR/dvd_rip.conf"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       DVD Ripper — Uninstaller           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Detect distro ─────────────────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    elif command -v pacman &>/dev/null; then echo "arch"
    elif command -v apt    &>/dev/null; then echo "ubuntu"
    elif command -v dnf    &>/dev/null; then echo "fedora"
    else echo "unknown"
    fi
}

DISTRO=$(detect_distro)
echo -e "${BOLD}Detected distro:${RESET} $DISTRO"
echo ""

# ── Load config to find user data paths ───────────────────────────────────────
MOVIES_DIR=""
RIPS_DIR=""
LOG_DIR=""

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    echo -e "${BOLD}Config found:${RESET} $CONFIG_FILE"
    echo ""
fi

# ── Confirm ───────────────────────────────────────────────────────────────────
echo -e "${YELLOW}${BOLD}This will remove:${RESET}"
echo "  - makemkvcon (binary and libraries)"
echo "  - HandBrakeCLI"
echo "  - libdvdcss"
echo "  - dvd-ripper config (~/.config/dvd-ripper/)"
echo "  - Distrobox container (media-rip) if present"
echo "  - sudoers rule (/etc/sudoers.d/dvdrip) if present"
echo ""
echo -e "${GREEN}${BOLD}This will NOT remove:${RESET}"
echo "  - Your movie library (${MOVIES_DIR:-not configured})"
echo "  - Your log files (${LOG_DIR:-not configured})"
echo "  - Your rips folder (${RIPS_DIR:-not configured})"
echo ""
echo -e "${YELLOW}Note: packages shared with other software (ffmpeg, curl etc)${RESET}"
echo -e "${YELLOW}will not be removed to avoid breaking your system.${RESET}"
echo ""
echo -en "${BOLD}Proceed with uninstall? [y/N]: ${RESET}"
read -r confirm

if [[ "${confirm,,}" != "y" ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""

# ── Helper ────────────────────────────────────────────────────────────────────
step() { echo -e "\n${CYAN}${BOLD}── $* ──${RESET}"; }
ok()   { echo -e "  ${GREEN}✔${RESET} $*"; }
skip() { echo -e "  ${YELLOW}–${RESET} $* (skipped — not found)"; }
fail() { echo -e "  ${RED}✗${RESET} $*"; }

# ── Remove MakeMKV ────────────────────────────────────────────────────────────
remove_makemkv() {
    step "Removing MakeMKV"

    case "$DISTRO" in
        arch|cachyos|endeavouros|manjaro)
            if pacman -Qi makemkv &>/dev/null; then
                sudo pacman -R --noconfirm makemkv 2>/dev/null && ok "makemkv (pacman)" || fail "pacman remove failed"
            elif command -v yay &>/dev/null && yay -Qi makemkv &>/dev/null 2>/dev/null; then
                yay -R --noconfirm makemkv 2>/dev/null && ok "makemkv (AUR)" || fail "yay remove failed"
            else
                _remove_makemkv_source_files
            fi
            ;;
        *)
            _remove_makemkv_source_files
            ;;
    esac
}

_remove_makemkv_source_files() {
    local removed=false
    local files=(
        /usr/bin/makemkvcon
        /usr/bin/makemkvgui
        /usr/bin/mmccextr
        /usr/bin/mmgplsrv
        /usr/bin/sdftool
        /usr/lib/libdriveio.so.0
        /usr/lib/libmakemkv.so.1
        /usr/lib/libmmbd.so.0
        /usr/share/MakeMKV
        /usr/share/applications/makemkv.desktop
        /usr/share/icons/hicolor/*/apps/makemkv.png
    )
    for f in "${files[@]}"; do
        # Use glob expansion
        for match in $f; do
            if [[ -e "$match" ]]; then
                sudo rm -rf "$match"
                removed=true
            fi
        done
    done
    sudo ldconfig
    $removed && ok "MakeMKV (source build files)" || skip "MakeMKV source files"
}

# ── Remove HandBrakeCLI ───────────────────────────────────────────────────────
remove_handbrake() {
    step "Removing HandBrakeCLI"

    case "$DISTRO" in
        arch|cachyos|endeavouros|manjaro)
            if pacman -Qi handbrake-cli &>/dev/null; then
                sudo pacman -R --noconfirm handbrake-cli 2>/dev/null && ok "handbrake-cli" || fail "pacman remove failed"
            else
                skip "handbrake-cli (not installed via pacman)"
            fi
            ;;
        ubuntu|debian|linuxmint|pop)
            if dpkg -l handbrake-cli &>/dev/null 2>&1; then
                sudo apt remove -y handbrake-cli 2>/dev/null && ok "handbrake-cli" || fail "apt remove failed"
            else
                skip "handbrake-cli (not installed via apt)"
            fi
            ;;
        fedora|rhel|centos|rocky)
            if rpm -q HandBrake-cli &>/dev/null; then
                sudo dnf remove -y HandBrake-cli 2>/dev/null && ok "HandBrake-cli" || fail "dnf remove failed"
            else
                skip "HandBrake-cli (not installed via dnf)"
            fi
            ;;
        *)
            if [[ -f /usr/bin/HandBrakeCLI ]]; then
                sudo rm -f /usr/bin/HandBrakeCLI && ok "HandBrakeCLI (binary)" || fail "could not remove binary"
            else
                skip "HandBrakeCLI"
            fi
            ;;
    esac
}

# ── Remove libdvdcss ──────────────────────────────────────────────────────────
remove_libdvdcss() {
    step "Removing libdvdcss"

    case "$DISTRO" in
        arch|cachyos|endeavouros|manjaro)
            if pacman -Qi libdvdcss &>/dev/null; then
                sudo pacman -R --noconfirm libdvdcss 2>/dev/null && ok "libdvdcss (pacman)" || fail "pacman remove failed"
            else
                _remove_libdvdcss_source_files
            fi
            ;;
        ubuntu|debian|linuxmint|pop)
            # Remove libdvd-pkg if installed
            if dpkg -l libdvd-pkg &>/dev/null 2>&1; then
                sudo dpkg --purge libdvd-pkg 2>/dev/null && ok "libdvd-pkg" || fail "dpkg purge failed"
            fi
            # Remove libdvdcss2 if installed as .deb
            if dpkg -l libdvdcss2 &>/dev/null 2>&1; then
                sudo dpkg --purge libdvdcss2 2>/dev/null && ok "libdvdcss2" || fail "dpkg purge failed"
            fi
            _remove_libdvdcss_source_files
            ;;
        fedora|rhel|centos|rocky)
            if rpm -q libdvdcss &>/dev/null; then
                sudo dnf remove -y libdvdcss 2>/dev/null && ok "libdvdcss (dnf)" || fail "dnf remove failed"
            else
                _remove_libdvdcss_source_files
            fi
            ;;
        *)
            _remove_libdvdcss_source_files
            ;;
    esac

    sudo ldconfig
}

_remove_libdvdcss_source_files() {
    local removed=false
    local files=(
        /usr/lib/x86_64-linux-gnu/libdvdcss.so.2.2.0
        /usr/lib/x86_64-linux-gnu/libdvdcss.so.2
        /usr/lib/x86_64-linux-gnu/libdvdcss.so
        /usr/local/lib/libdvdcss.so.2.2.0
        /usr/local/lib/libdvdcss.so.2
        /usr/local/lib/libdvdcss.so
        /usr/local/lib/libdvdcss.la
        /usr/local/lib/libdvdcss.a
        /usr/local/lib/pkgconfig/libdvdcss.pc
        /usr/local/include/dvdcss
        /usr/local/share/doc/libdvdcss
    )
    for f in "${files[@]}"; do
        if [[ -e "$f" ]]; then
            sudo rm -rf "$f"
            removed=true
        fi
    done
    $removed && ok "libdvdcss (source build files)" || skip "libdvdcss source files"
}

# ── Remove Distrobox container ────────────────────────────────────────────────
remove_distrobox() {
    step "Removing Distrobox container"

    if ! command -v distrobox &>/dev/null; then
        skip "Distrobox (not installed)"
        return
    fi

    if distrobox list 2>/dev/null | grep -q "media-rip"; then
        echo -en "  ${YELLOW}Remove Distrobox container 'media-rip'? [y/N]: ${RESET}"
        read -r db_confirm
        if [[ "${db_confirm,,}" == "y" ]]; then
            distrobox stop media-rip 2>/dev/null || true
            distrobox rm media-rip 2>/dev/null && ok "Distrobox container 'media-rip'" || fail "could not remove container"
        else
            skip "Distrobox container (skipped by user)"
        fi
    else
        skip "Distrobox container 'media-rip' (not found)"
    fi
}

# ── Remove sudoers rule ───────────────────────────────────────────────────────
remove_sudoers() {
    step "Removing sudoers rule"

    if [[ -f /etc/sudoers.d/dvdrip ]]; then
        sudo rm -f /etc/sudoers.d/dvdrip && ok "/etc/sudoers.d/dvdrip" || fail "could not remove sudoers rule"
    else
        skip "/etc/sudoers.d/dvdrip (not found)"
    fi
}

# ── Remove config ─────────────────────────────────────────────────────────────
remove_config() {
    step "Removing config"

    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR" && ok "~/.config/dvd-ripper/" || fail "could not remove config dir"
    else
        skip "~/.config/dvd-ripper/ (not found)"
    fi
}

# ── Optionally remove user data ───────────────────────────────────────────────
remove_user_data() {
    step "User data"

    local has_data=false

    for dir in "$MOVIES_DIR" "$RIPS_DIR" "$LOG_DIR"; do
        [[ -n "$dir" && -d "$dir" ]] && has_data=true
    done

    if ! $has_data; then
        skip "No user data directories found"
        return
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}The following data directories were found:${RESET}"
    [[ -n "$MOVIES_DIR" && -d "$MOVIES_DIR" ]] && echo "    $MOVIES_DIR"
    [[ -n "$RIPS_DIR"   && -d "$RIPS_DIR"   ]] && echo "    $RIPS_DIR"
    [[ -n "$LOG_DIR"    && -d "$LOG_DIR"     ]] && echo "    $LOG_DIR"
    echo ""
    echo -e "  ${YELLOW}These contain your ripped movies and logs.${RESET}"
    echo -en "  ${BOLD}Delete these directories and all their contents? [y/N]: ${RESET}"
    read -r data_confirm

    if [[ "${data_confirm,,}" == "y" ]]; then
        echo -en "  ${RED}${BOLD}Are you absolutely sure? This cannot be undone. [yes/N]: ${RESET}"
        read -r double_confirm
        if [[ "${double_confirm,,}" == "yes" ]]; then
            [[ -n "$MOVIES_DIR" && -d "$MOVIES_DIR" ]] && rm -rf "$MOVIES_DIR" && ok "Deleted $MOVIES_DIR"
            [[ -n "$RIPS_DIR"   && -d "$RIPS_DIR"   ]] && rm -rf "$RIPS_DIR"   && ok "Deleted $RIPS_DIR"
            [[ -n "$LOG_DIR"    && -d "$LOG_DIR"     ]] && rm -rf "$LOG_DIR"    && ok "Deleted $LOG_DIR"
        else
            skip "User data (skipped)"
        fi
    else
        skip "User data (kept)"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
summary() {
    echo ""
    echo -e "${CYAN}${BOLD}── Uninstall complete ──${RESET}"
    echo ""
    echo -e "  ${GREEN}dvd-ripper has been removed from your system.${RESET}"
    echo ""
    echo "  You can safely delete this repo folder now:"
    echo "    rm -rf $(pwd)"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
remove_makemkv
remove_handbrake
remove_libdvdcss
remove_distrobox
remove_sudoers
remove_config
remove_user_data
summary

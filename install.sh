#!/usr/bin/env bash
# =============================================================================
#  install.sh — Dependency installer for dvd-ripper
#  Supports: Arch/CachyOS, Ubuntu/Debian, Fedora/RHEL
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

MAKEMKV_VERSION="1.18.3"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       DVD Ripper — Installer             ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Detect distro ─────────────────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    elif command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v apt &>/dev/null; then
        echo "ubuntu"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
echo -e "${BOLD}Detected distro:${RESET} $DISTRO"
echo ""

# ── Install packages ──────────────────────────────────────────────────────────
install_packages() {
    echo -e "${BOLD}── Installing dependencies ──${RESET}"
    echo ""

    case "$DISTRO" in
        arch|cachyos|endeavouros|manjaro)
            echo "Using pacman/yay..."

            sudo pacman -Sy --needed --noconfirm \
                base-devel curl jq eject \
                handbrake-cli \
                libdvdcss \
                openssl expat ffmpeg mesa qt5-base zlib \
                python

            # Add user to optical group
            sudo usermod -a -G optical "$USER"
            echo -e "${GREEN}Added $USER to optical group — log out and back in after install.${RESET}"
            ;;

        ubuntu|debian|linuxmint|pop)
            echo "Using apt..."

            sudo apt update
            sudo apt install -y \
                build-essential pkg-config curl jq eject \
                handbrake-cli \
                libssl-dev libexpat1-dev libavcodec-dev \
                libgl1-mesa-dev qtbase5-dev zlib1g-dev \
                python3 wget

            # libdvdcss via libdvd-pkg
            sudo apt install -y libdvd-pkg
            sudo DEBIAN_FRONTEND=noninteractive TERM=xterm-256color dpkg-reconfigure libdvd-pkg || true

            # Fallback: build libdvdcss from source if pkg method fails
            if ! ldconfig -p | grep -q dvdcss; then
                echo "Building libdvdcss from source..."
                _build_libdvdcss
            fi

            sudo usermod -a -G cdrom,optical "$USER" 2>/dev/null || true
            ;;

        fedora|rhel|centos|rocky)
            echo "Using dnf..."

            sudo dnf install -y \
                gcc gcc-c++ make curl jq eject \
                HandBrake-cli \
                openssl-devel expat-devel ffmpeg-devel \
                mesa-libGL-devel qt5-qtbase-devel zlib-devel \
                python3 wget

            # libdvdcss from RPM Fusion
            sudo dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || true
            sudo dnf install -y libdvdcss || _build_libdvdcss

            sudo usermod -a -G cdrom "$USER" 2>/dev/null || true
            ;;

        *)
            echo -e "${YELLOW}Unknown distro. Installing build tools only — you may need to install some packages manually.${RESET}"
            echo "Required: HandBrakeCLI, curl, jq, eject, libdvdcss, python3"
            ;;
    esac

    echo -e "${GREEN}Packages installed.${RESET}"
    echo ""
}

# ── Build libdvdcss from source ───────────────────────────────────────────────
_build_libdvdcss() {
    echo "Building libdvdcss from source..."
    local build_dir
    build_dir=$(mktemp -d)
    cd "$build_dir" || return 1

    wget -q "https://download.videolan.org/pub/libdvdcss/1.4.3/libdvdcss-1.4.3.tar.bz2"
    tar -xjf libdvdcss-1.4.3.tar.bz2
    cd libdvdcss-1.4.3 || return 1
    ./configure --quiet
    make -s
    sudo make install -s
    sudo ldconfig
    cd ~
    rm -rf "$build_dir"
    echo -e "${GREEN}libdvdcss built and installed.${RESET}"
}

# ── Build MakeMKV from source ─────────────────────────────────────────────────
install_makemkv() {
    echo -e "${BOLD}── Installing MakeMKV v${MAKEMKV_VERSION} ──${RESET}"
    echo ""

    # Check if already installed and up to date
    if command -v makemkvcon &>/dev/null; then
        local installed_ver
        installed_ver=$(makemkvcon --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        if [[ "$installed_ver" == "$MAKEMKV_VERSION" ]]; then
            echo -e "${GREEN}MakeMKV $MAKEMKV_VERSION already installed.${RESET}"
            echo ""
            return 0
        fi
    fi

    # Check for AUR on Arch-based systems first
    if command -v yay &>/dev/null && [[ "$DISTRO" =~ arch|cachyos|endeavouros|manjaro ]]; then
        echo "Trying AUR package..."
        if yay -S --noconfirm makemkv 2>/dev/null; then
            echo -e "${GREEN}MakeMKV installed via AUR.${RESET}"
            echo ""
            return 0
        fi
        echo -e "${YELLOW}AUR install failed — building from source.${RESET}"
    fi

    echo "Building MakeMKV from source..."
    local build_dir
    build_dir=$(mktemp -d)
    cd "$build_dir" || exit 1

    echo "  Downloading sources..."
    wget -q "https://www.makemkv.com/download/makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
    wget -q "https://www.makemkv.com/download/makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

    echo "  Building OSS component..."
    tar -xzf "makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
    cd "makemkv-oss-${MAKEMKV_VERSION}" || exit 1
    ./configure --quiet
    make -s
    sudo make install -s
    cd "$build_dir" || exit 1

    echo "  Building bin component..."
    tar -xzf "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"
    cd "makemkv-bin-${MAKEMKV_VERSION}" || exit 1
    make -s
    sudo make install -s

    cd ~
    rm -rf "$build_dir"

    echo -e "${GREEN}MakeMKV $MAKEMKV_VERSION installed.${RESET}"
    echo ""
}

# ── Verify installation ───────────────────────────────────────────────────────
verify() {
    echo -e "${BOLD}── Verifying installation ──${RESET}"
    echo ""

    local ok=true

    check_tool() {
        if command -v "$1" &>/dev/null; then
            echo -e "  ${GREEN}✔${RESET} $1 — $(command -v "$1")"
        else
            echo -e "  ${RED}✗${RESET} $1 — NOT FOUND"
            ok=false
        fi
    }

    check_tool makemkvcon
    check_tool HandBrakeCLI
    check_tool curl
    check_tool jq

    if ldconfig -p | grep -q dvdcss; then
        echo -e "  ${GREEN}✔${RESET} libdvdcss — found"
    else
        echo -e "  ${RED}✗${RESET} libdvdcss — NOT FOUND"
        ok=false
    fi

    echo ""

    if $ok; then
        echo -e "${GREEN}${BOLD}All dependencies installed successfully!${RESET}"
        echo ""
        echo -e "Run ${BOLD}bash setup.sh${RESET} to configure your drives and preferences."
    else
        echo -e "${RED}Some dependencies are missing. Check the errors above.${RESET}"
        exit 1
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
install_packages
install_makemkv
verify

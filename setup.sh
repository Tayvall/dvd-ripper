#!/usr/bin/env bash
# =============================================================================
#  setup.sh — First-run configuration wizard for dvd-ripper
#  Detects DVD drives and storage, writes ~/.config/dvd-ripper/dvd_rip.conf
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
echo "  ║       DVD Ripper — Setup Wizard          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Detect optical drives ─────────────────────────────────────────────────────
detect_dvd_drives() {
    local drives=()
    while IFS= read -r dev; do
        drives+=("$dev")
    done < <(lsblk -dpno NAME,TYPE | awk '$2=="rom" {print $1}')
    echo "${drives[@]}"
}

# ── Detect large external/internal drives ────────────────────────────────────
detect_storage_drives() {
    # List drives >100GB that are not the boot drive, with their sizes
    local boot_dev
    boot_dev=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
    boot_dev="/dev/${boot_dev}"

    while IFS= read -r line; do
        local dev size
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        local mount
        mount=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1)
        if [[ "$dev" != "$boot_dev"* ]]; then
            echo "$dev ($size)${mount:+ — mounted at $mount}"
        fi
    done < <(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk" {print $1, $2}')
}

# ── Select DVD drive ──────────────────────────────────────────────────────────
echo -e "${BOLD}── Step 1: DVD Drive ──${RESET}"
echo ""

mapfile -t DVD_DRIVES < <(detect_dvd_drives)

if [[ ${#DVD_DRIVES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No optical drives detected automatically.${RESET}"
    echo -en "Enter device path manually (e.g. /dev/sr0): "
    read -r DVD_DEVICE
else
    echo "Detected optical drive(s):"
    for i in "${!DVD_DRIVES[@]}"; do
        echo "  [$i] ${DVD_DRIVES[$i]}"
    done
    echo ""
    if [[ ${#DVD_DRIVES[@]} -eq 1 ]]; then
        DVD_DEVICE="${DVD_DRIVES[0]}"
        echo -e "${GREEN}Auto-selected: $DVD_DEVICE${RESET}"
    else
        echo -en "Select drive number [0]: "
        read -r sel
        sel="${sel:-0}"
        DVD_DEVICE="${DVD_DRIVES[$sel]}"
        echo -e "${GREEN}Selected: $DVD_DEVICE${RESET}"
    fi
fi

echo ""

# ── Select storage location ───────────────────────────────────────────────────
echo -e "${BOLD}── Step 2: Movie Storage Location ──${RESET}"
echo ""
echo "Where should finished movies be saved?"
echo ""

mapfile -t STORAGE_DRIVES < <(detect_storage_drives)

if [[ ${#STORAGE_DRIVES[@]} -gt 0 ]]; then
    echo "Detected drives:"
    for i in "${!STORAGE_DRIVES[@]}"; do
        echo "  [$i] ${STORAGE_DRIVES[$i]}"
    done
    echo "  [c] Enter a custom path"
    echo ""
    echo -en "Select [c]: "
    read -r sel

    if [[ "$sel" == "c" || -z "$sel" ]]; then
        echo -en "Enter full path (e.g. /media/storage/Movies): "
        read -r MOVIES_DIR
    else
        local_dev=$(echo "${STORAGE_DRIVES[$sel]}" | awk '{print $1}')
        local_mount=$(lsblk -no MOUNTPOINT "$local_dev" 2>/dev/null | head -1)
        if [[ -n "$local_mount" ]]; then
            MOVIES_DIR="${local_mount}/Movies"
        else
            echo -e "${YELLOW}Drive not mounted. Enter mount point:${RESET}"
            echo -en "Mount point (e.g. /media/storage): "
            read -r mount_point
            MOVIES_DIR="${mount_point}/Movies"
        fi
        echo -e "${GREEN}Movies will save to: $MOVIES_DIR${RESET}"
    fi
else
    echo -en "Enter full path for movies (e.g. /media/storage/Movies): "
    read -r MOVIES_DIR
fi

# Derive rips and logs from movies dir parent
STORAGE_BASE=$(dirname "$MOVIES_DIR")
RIPS_DIR="${STORAGE_BASE}/rips"
LOG_DIR="${STORAGE_BASE}/logs"

echo ""

# ── TMDB API ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}── Step 3: TMDB API (for automatic movie naming) ──${RESET}"
echo ""
echo "A free TMDB API key enables automatic movie name detection."
echo "Get one at: https://www.themoviedb.org/settings/api"
echo ""
echo -en "Enter your TMDB API Read Access Token (or press Enter to skip): "
read -r TMDB_TOKEN

if [[ -z "$TMDB_TOKEN" ]]; then
    echo -e "${YELLOW}Skipping TMDB — manual name entry will be used.${RESET}"
    TMDB_API_KEY=""
else
    # Extract API key from token if possible, otherwise prompt
    echo -en "Enter your TMDB API Key (v3): "
    read -r TMDB_API_KEY
fi

echo ""

# ── HandBrake preset ──────────────────────────────────────────────────────────
echo -e "${BOLD}── Step 4: Encoding Quality ──${RESET}"
echo ""
echo "  [1] H.264 MKV 576p25  — Standard quality, smaller files (recommended)"
echo "  [2] H.264 MKV 720p30  — Higher quality, larger files"
echo "  [3] H.265 MKV 576p25  — Best compression, slower encode"
echo ""
echo -en "Select preset [1]: "
read -r preset_sel

case "${preset_sel:-1}" in
    2) HB_PRESET="H.264 MKV 720p30" ;;
    3) HB_PRESET="H.265 MKV 576p25" ;;
    *) HB_PRESET="H.264 MKV 576p25" ;;
esac

echo -e "${GREEN}Preset: $HB_PRESET${RESET}"
echo ""

# ── Tool paths ────────────────────────────────────────────────────────────────
MAKEMKV=$(command -v makemkvcon 2>/dev/null || echo "/usr/bin/makemkvcon")
HANDBRAKE=$(command -v HandBrakeCLI 2>/dev/null || echo "/usr/bin/HandBrakeCLI")

# ── Write config ──────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
# dvd-ripper configuration
# Generated by setup.sh on $(date)
# Edit this file or re-run setup.sh to change settings

# ── Device paths ──────────────────────────────────────────────────────────────
DVD_DEVICE="$DVD_DEVICE"

# ── Storage paths ─────────────────────────────────────────────────────────────
MOVIES_DIR="$MOVIES_DIR"
RIPS_DIR="$RIPS_DIR"
LOG_DIR="$LOG_DIR"

# ── Tool paths ────────────────────────────────────────────────────────────────
MAKEMKV="$MAKEMKV"
HANDBRAKE="$HANDBRAKE"

# ── Encoding ──────────────────────────────────────────────────────────────────
HB_PRESET="$HB_PRESET"
MIN_TITLE_SECONDS=1200

# ── TMDB (movie name lookup) ──────────────────────────────────────────────────
TMDB_API_KEY="$TMDB_API_KEY"
TMDB_TOKEN="$TMDB_TOKEN"
EOF

echo -e "${GREEN}${BOLD}Config saved to: $CONFIG_FILE${RESET}"
echo ""
echo "  DVD device:   $DVD_DEVICE"
echo "  Movies dir:   $MOVIES_DIR"
echo "  Rips dir:     $RIPS_DIR"
echo "  Preset:       $HB_PRESET"
echo ""
echo -e "${CYAN}Setup complete! Run ${BOLD}bash dvd_rip.sh${RESET}${CYAN} to start ripping.${RESET}"
echo ""

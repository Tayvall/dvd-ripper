#!/usr/bin/env bash
# =============================================================================
#  dvd_rip.sh — Continuous DVD ripper for Kodi media libraries
#  https://github.com/yourusername/dvd-ripper
#
#  Dependencies: makemkvcon, HandBrakeCLI, libdvdcss, curl, jq
#  First run:    bash setup.sh
#  Usage:        bash dvd_rip.sh
# =============================================================================

# ── Load config ───────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dvd-ripper"
CONFIG_FILE="$CONFIG_DIR/dvd_rip.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "No config found. Running setup wizard..."
    bash "$(dirname "$0")/setup.sh"
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

HB_PIDS=()
SESSION_LOG="/tmp/dvd_rip_fallback.log"

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; echo "$(date '+%H:%M:%S') [INFO]  $*" >> "$SESSION_LOG"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; echo "$(date '+%H:%M:%S') [WARN]  $*" >> "$SESSION_LOG"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; echo "$(date '+%H:%M:%S') [ERROR] $*" >> "$SESSION_LOG"; }
log_section() { echo -e "\n${CYAN}${BOLD}── $* ──${RESET}\n"; echo "$(date '+%H:%M:%S') ── $* ──" >> "$SESSION_LOG"; }

# ── Progress bar ──────────────────────────────────────────────────────────────
draw_progress() {
    local percent="$1" label="$2" width=40
    local filled=$(( width * percent / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf "\r  ${CYAN}${BOLD}[%s]${RESET} ${BOLD}%3d%%${RESET}  %s        " "$bar" "$percent" "$label"
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║         DVD Ripper — Kodi Library        ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    [[ ! -x "$MAKEMKV" ]]   && missing+=("makemkvcon (expected at $MAKEMKV)")
    [[ ! -x "$HANDBRAKE" ]] && missing+=("HandBrakeCLI (expected at $HANDBRAKE)")
    command -v curl &>/dev/null || missing+=("curl")
    command -v jq   &>/dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for t in "${missing[@]}"; do log_error "  - $t"; done
        log_error "Run: bash install.sh"
        exit 1
    fi

    if [[ ! -e "$DVD_DEVICE" ]]; then
        log_error "Optical drive not found at $DVD_DEVICE"
        log_error "Run: bash setup.sh to reconfigure"
        exit 1
    fi

    local free_gb
    free_gb=$(df -BG "$MOVIES_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    if (( free_gb < 20 )); then
        log_warn "Only ${free_gb}GB free — rips may fail!"
    else
        log_info "Disk space OK — ${free_gb}GB free"
    fi
}

# ── Create directories ────────────────────────────────────────────────────────
ensure_dirs() {
    mkdir -p "$RIPS_DIR" "$MOVIES_DIR" "$LOG_DIR"
    SESSION_LOG="${LOG_DIR}/session_$(date '+%Y%m%d_%H%M%S').log"
    touch "$SESSION_LOG"
    find "$RIPS_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete
    log_info "Session log:   $SESSION_LOG"
    log_info "Movies folder: $MOVIES_DIR"
}

# ── Wait for disc ─────────────────────────────────────────────────────────────
wait_for_disc() {
    log_info "Waiting for disc to be ready..."
    local attempts=0
    until dd if="$DVD_DEVICE" of=/dev/null bs=2048 count=1 &>/dev/null; do
        sleep 3
        (( attempts++ ))
        if (( attempts > 20 )); then
            log_error "Disc not readable after 60 seconds."
            return 1
        fi
    done
    log_info "Disc detected and readable."
}

# ── Eject disc ────────────────────────────────────────────────────────────────
eject_disc() {
    eject "$DVD_DEVICE" 2>/dev/null \
        && log_info "Disc ejected." \
        || log_warn "Could not eject — eject manually."
}

# ── Get disc title ────────────────────────────────────────────────────────────
get_disc_title() {
    local raw

    # Try distrobox host exec first (for distrobox environments)
    if command -v distrobox-host-exec &>/dev/null; then
        raw=$(distrobox-host-exec sudo blkid 2>/dev/null \
            | grep '/dev/sr' \
            | grep -o 'LABEL="[^"]*"' \
            | head -1 \
            | sed 's/LABEL="//;s/"//')
    fi

    # Native blkid fallback
    if [[ -z "$raw" ]]; then
        raw=$(sudo blkid -s LABEL -o value "$DVD_DEVICE" 2>/dev/null)
    fi

    [[ -z "$raw" ]] && echo "" && return 1

    # Strip disc number suffixes (D1, D2, DISC1, DISK2 etc)
    raw=$(echo "$raw" | sed 's/_D[0-9]*$//I;s/_DISC[0-9]*$//I;s/_DISK[0-9]*$//I')

    # Clean up formatting
    raw="${raw//_/ }"
    raw="${raw//-/ }"
    raw="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    echo "$raw"
}

# ── TMDB lookup ───────────────────────────────────────────────────────────────
tmdb_lookup() {
    local query="$1"
    local encoded_query
    encoded_query="$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))")"

    local response
    response=$(curl -s \
        --header "Authorization: Bearer ${TMDB_TOKEN}" \
        "https://api.themoviedb.org/3/search/movie?query=${encoded_query}&language=en-GB")

    local title year
    title=$(echo "$response" | jq -r '.results[0].title // empty')
    year=$(echo "$response"  | jq -r '.results[0].release_date // empty' | cut -d'-' -f1)

    [[ -z "$title" ]] && echo "" && return 1
    echo "${title} (${year})"
}

# ── Resolve movie name ────────────────────────────────────────────────────────
resolve_movie_name() {
    log_section "Identifying Disc" >&2
    log_info "Reading disc title..." >&2

    local disc_title
    disc_title=$(get_disc_title)

    if [[ -z "$disc_title" ]]; then
        log_warn "Could not read disc title — falling back to manual entry." >&2
        _manual_name_prompt
        return
    fi

    log_info "Disc title: '$disc_title'" >&2
    log_info "Looking up on TMDB..." >&2

    local tmdb_result
    tmdb_result=$(tmdb_lookup "$disc_title")

    if [[ -n "$tmdb_result" ]]; then
        echo "" >&2
        echo -e "${BOLD}  Found: ${GREEN}${tmdb_result}${RESET}" >&2
        echo -en "${BOLD}  Press Enter to accept, or type a correction: ${RESET}" >&2
        read -r override

        if [[ -n "$override" ]]; then
            local corrected
            corrected=$(tmdb_lookup "$override")
            if [[ -n "$corrected" ]]; then
                echo -e "${BOLD}  Using: ${GREEN}${corrected}${RESET}" >&2
                echo "$corrected"
            else
                log_warn "No TMDB match for '$override' — using as entered." >&2
                override="${override//[\/\\:*?\"<>|]/}"
                echo "$(echo "$override" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            fi
        else
            echo "$tmdb_result"
        fi
    else
        log_warn "No TMDB match for '$disc_title' — falling back to manual entry." >&2
        _manual_name_prompt
    fi
}

# ── Manual name fallback ──────────────────────────────────────────────────────
_manual_name_prompt() {
    local raw_name
    while true; do
        echo -en "\n${BOLD}  Enter movie name (e.g. Kung Fu Panda (2008)): ${RESET}" >&2
        read -r raw_name
        raw_name="${raw_name//[\/\\:*?\"<>|]/}"
        raw_name="$(echo "$raw_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -n "$raw_name" ]]; then
            echo "$raw_name"
            return
        fi
        echo -e "${YELLOW}[WARN]${RESET}  Name cannot be empty." >&2
    done
}

# ── Rip with MakeMKV ──────────────────────────────────────────────────────────
rip_disc() {
    local out_dir="$1"
    local makemkv_log="${LOG_DIR}/makemkv_$(date '+%H%M%S').log"

    log_section "Ripping with MakeMKV"
    log_info "Output: $out_dir"
    mkdir -p "$out_dir"

    echo ""
    log_info "Starting rip — this takes several minutes..."
    echo ""

    local last_total=0

    "$MAKEMKV" mkv disc:0 all "$out_dir" \
        --minlength="$MIN_TITLE_SECONDS" \
        --progress=-stdout \
        --noscan 2>&1 | tee "$makemkv_log" | \
    while IFS= read -r line; do
        if [[ "$line" =~ Total\ progress\ -\ ([0-9]+)% ]]; then
            local total="${BASH_REMATCH[1]}"
            if (( total != last_total )); then
                last_total=$total
                draw_progress "$total" "Ripping..."
            fi
        elif [[ "$line" =~ ^Current\ action:\ (.+) ]]; then
            printf "\r%-80s\n" " "
            log_info "  Stage: ${BASH_REMATCH[1]}"
        elif [[ "$line" =~ "was added" ]]; then
            printf "\r%-80s\n" " "
            log_info "  Found: $line"
        elif [[ "$line" =~ [Ee]rror ]]; then
            printf "\r%-80s\n" " "
            log_warn "  MakeMKV: $line"
        fi
    done

    printf "\r%-80s\r" " "

    local mkv_count
    mkv_count=$(find "$out_dir" -name "*.mkv" 2>/dev/null | wc -l)

    if [[ $mkv_count -eq 0 ]]; then
        log_error "No MKV files created — check log: $makemkv_log"
        return 1
    fi

    log_info "MakeMKV done — $mkv_count title(s) ripped."
    return 0
}

# ── Encode with HandBrake ─────────────────────────────────────────────────────
encode_titles() {
    local rip_dir="$1"
    local movie_name="$2"
    local dest_dir="${MOVIES_DIR}/${movie_name}"
    local safe_name="${movie_name// /_}"
    local hb_log="${LOG_DIR}/${safe_name}_handbrake.log"

    mkdir -p "$dest_dir"
    log_section "Queuing HandBrake encode"

    local index=0
    while IFS= read -r -d '' mkv_file; do
        (( index++ ))
        local out_name
        if [[ $index -eq 1 ]]; then
            out_name="${movie_name}.mkv"
        else
            out_name="${movie_name} - Part${index}.mkv"
        fi

        local out_path="${dest_dir}/${out_name}"
        log_info "  Input:  $(basename "$mkv_file")"
        log_info "  Output: $out_name"

        "$HANDBRAKE" \
            --input "$mkv_file" \
            --output "$out_path" \
            --preset "$HB_PRESET" \
            --audio-lang-list eng \
            --all-audio \
            --subtitle-lang-list eng \
            --all-subtitles \
            --subtitle-burned=none \
            --verbose=1 \
            >> "$hb_log" 2>&1 \
            && rm -f "$mkv_file" \
            && log_info "  ✔ Encode complete: $out_name" \
            || log_warn "  ✗ Encode failed: $out_name — see $hb_log" &

        HB_PIDS+=($!)
    done < <(find "$rip_dir" -name "*.mkv" -print0 | sort -z)

    echo ""
    log_info "HandBrake encoding in background — ${#HB_PIDS[@]} job(s) queued."
    log_info "Watch progress: tail -f $hb_log | grep '%'"
    echo ""
}

# ── Background job status ─────────────────────────────────────────────────────
show_hb_status() {
    [[ ${#HB_PIDS[@]} -eq 0 ]] && return
    echo ""
    log_section "Background Encode Status"
    local running=0 done_count=0
    for pid in "${HB_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_info "  PID $pid — encoding"; (( running++ ))
        else
            log_info "  PID $pid — finished"; (( done_count++ ))
        fi
    done
    log_info "  Running: $running  |  Done: $done_count"
}

# ── Next disc prompt ──────────────────────────────────────────────────────────
prompt_next_disc() {
    echo ""
    echo -e "${BOLD}┌─────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│  Insert next disc and press Enter to continue   │${RESET}"
    echo -e "${BOLD}│  or type  q  and press Enter to quit            │${RESET}"
    echo -e "${BOLD}└─────────────────────────────────────────────────┘${RESET}"
    echo -en "  > "
    read -r response
    [[ "${response,,}" == "q" ]] && return 1
    return 0
}

# ── Graceful exit ─────────────────────────────────────────────────────────────
finish() {
    echo ""
    log_section "Finished"
    show_hb_status
    if [[ ${#HB_PIDS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}  HandBrake still encoding — do not power off!${RESET}"
        echo -e "${YELLOW}  Movies will appear in: $MOVIES_DIR${RESET}"
    fi
    echo ""
    log_info "Session log: $SESSION_LOG"
    echo ""
}

trap 'echo ""; log_warn "Interrupted."; finish; exit 0' INT TERM

# =============================================================================
#  MAIN
# =============================================================================
banner
check_deps
ensure_dirs

disc_count=0

while true; do
    log_section "New Disc"

    if [[ $disc_count -eq 0 ]]; then
        echo -en "${BOLD}  Insert a disc and press Enter when ready... ${RESET}"
        read -r
    fi

    wait_for_disc || { log_warn "Skipping disc."; continue; }

    movie_name=$(resolve_movie_name)
    rip_dir="${RIPS_DIR}/${movie_name// /_}_rip"

    if rip_disc "$rip_dir"; then
        eject_disc
        (( disc_count++ ))
        log_info "Disc $disc_count complete: '$movie_name'"
        encode_titles "$rip_dir" "$movie_name"
    else
        log_warn "Rip failed for '$movie_name' — ejecting."
        eject_disc
    fi

    show_hb_status

    if ! prompt_next_disc; then
        log_info "Quitting. Background encodes will keep running."
        break
    fi
done

finish

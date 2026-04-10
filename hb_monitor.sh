#!/usr/bin/env bash
# =============================================================================
#  hb_monitor.sh — HandBrake encode progress monitor
#  Shows all jobs with progress bars, ETA, and fps
#  Usage: bash hb_monitor.sh
#  Keys:  Up/Down to scroll  |  Q to quit
# =============================================================================

# ── Config ────────────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dvd-ripper"
CONFIG_FILE="$CONFIG_DIR/dvd_rip.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

LOG_DIR="${LOG_DIR:-$HOME/logs}"

# ── Colours ───────────────────────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
GREY='\033[0;90m'

# ── Terminal helpers ──────────────────────────────────────────────────────────
clear_screen()   { printf '\033[2J\033[H'; }
hide_cursor()    { printf '\033[?25l'; }
show_cursor()    { printf '\033[?25h'; }
move_to()        { printf '\033[%d;%dH' "$1" "$2"; }

# ── Draw a progress bar ───────────────────────────────────────────────────────
draw_bar() {
    local percent="${1:-0}"
    local width="${2:-32}"
    local filled=$(( width * percent / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf '%s' "$bar"
}

# ── Parse a single log file ───────────────────────────────────────────────────
parse_log() {
    local log_path="$1"
    local movie_name percent eta fps status

    movie_name=$(basename "$log_path" \
        | sed 's/_handbrake\.log$//' \
        | tr '_' ' ' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Read last 100 lines for performance
    local lines
    lines=$(tail -n 100 "$log_path" 2>/dev/null)

    # Determine status
    if echo "$lines" | grep -q "Encode done!"; then
        status="done"
        percent=100
        eta=""
        fps=""
    elif echo "$lines" | grep -qiE "error.*failed|failed.*error"; then
        status="failed"
        percent=0
        eta=""
        fps=""
    else
        # Find last encoding progress line
        local progress_line
        progress_line=$(echo "$lines" | grep -E "Encoding:.*%" | tail -1)

        if [[ -n "$progress_line" ]]; then
            status="encoding"
            percent=$(echo "$progress_line" | grep -o '[0-9]*\.[0-9]*%' | head -1 | tr -d '%')
            percent=${percent%.*}  # truncate to integer
            eta=$(echo "$progress_line" | grep -oP 'ETA \K[0-9]+h[0-9]+m[0-9]+s' | head -1)
            fps=$(echo "$progress_line" | grep -oP '[0-9]+\.[0-9]+ fps' | head -1)
        else
            status="queued"
            percent=0
            eta=""
            fps=""
        fi
    fi

    # Output as pipe-delimited string
    printf '%s|%s|%s|%s|%s|%s\n' \
        "$movie_name" "$status" "${percent:-0}" "${eta:-}" "${fps:-}" "$log_path"
}

# ── Collect all jobs ──────────────────────────────────────────────────────────
collect_jobs() {
    local -n _jobs_ref=$1
    _jobs_ref=()

    local logs=()
    while IFS= read -r -d '' f; do
        logs+=("$f")
    done < <(find "$LOG_DIR" -name "*_handbrake.log" -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null \
        | tr '\n' '\0')

    if [[ ${#logs[@]} -eq 0 ]]; then
        return
    fi

    for log in "${logs[@]}"; do
        _jobs_ref+=("$(parse_log "$log")")
    done
}

# ── Check if HandBrake is running ─────────────────────────────────────────────
hb_running() {
    pgrep -x HandBrakeCLI &>/dev/null
}

# ── Render the full screen ────────────────────────────────────────────────────
render() {
    local -n _jobs=$1
    local scroll="$2"
    local total="${#_jobs[@]}"
    local running="$3"

    clear_screen

    # Header
    printf "${CYAN}${BOLD}"
    printf '  ╔══════════════════════════════════════════════════════════╗\n'
    printf '  ║              HandBrake Encode Monitor                   ║\n'
    printf '  ╚══════════════════════════════════════════════════════════╝\n'
    printf "${RESET}"
    echo ""

    # Status line
    if $running; then
        printf "  ${GREEN}${BOLD}● Encoding in progress${RESET}\n"
    else
        printf "  ${YELLOW}○ No active encode${RESET}\n"
    fi

    echo ""

    if [[ $total -eq 0 ]]; then
        printf "  ${GREY}No HandBrake logs found in: $LOG_DIR${RESET}\n"
        echo ""
        printf "  ${GREY}Logs appear here once encoding starts.${RESET}\n"
        echo ""
        printf "  ${GREY}Q to quit${RESET}\n"
        return
    fi

    # Summary line
    local done_count=0 encoding_count=0 queued_count=0 failed_count=0
    for job in "${_jobs[@]}"; do
        local st; st=$(echo "$job" | cut -d'|' -f2)
        case "$st" in
            done)     (( done_count++ ))     ;;
            encoding) (( encoding_count++ )) ;;
            queued)   (( queued_count++ ))   ;;
            failed)   (( failed_count++ ))   ;;
        esac
    done

    printf "  ${BOLD}Jobs: $total${RESET}"
    [[ $encoding_count -gt 0 ]] && printf "  ${YELLOW}Encoding: $encoding_count${RESET}"
    [[ $queued_count -gt 0 ]]   && printf "  ${BLUE}Queued: $queued_count${RESET}"
    [[ $done_count -gt 0 ]]     && printf "  ${GREEN}Done: $done_count${RESET}"
    [[ $failed_count -gt 0 ]]   && printf "  ${RED}Failed: $failed_count${RESET}"
    echo ""
    echo ""

    printf "  ${GREY}%-38s %-6s  %-32s  %s${RESET}\n" "Movie" "%" "Progress" "ETA / FPS"
    printf "  ${GREY}%s${RESET}\n" "$(printf '─%.0s' {1..72})"

    # Visible window
    local visible_jobs=("${_jobs[@]:$scroll:10}")

    for job in "${visible_jobs[@]}"; do
        IFS='|' read -r name status percent eta fps log_path <<< "$job"

        # Truncate long names
        local display_name="${name:0:36}"
        printf "  "

        case "$status" in
            done)
                printf "${GREEN}${BOLD}✔${RESET} %-37s ${GREEN}%5s%%${RESET}  " "$display_name" "100"
                printf "${GREEN}"; draw_bar 100 32; printf "${RESET}"
                printf "  ${GREEN}Complete${RESET}"
                ;;
            failed)
                printf "${RED}${BOLD}✗${RESET} %-37s ${RED}%5s%%${RESET}  " "$display_name" "ERR"
                printf "${RED}"; draw_bar 0 32; printf "${RESET}"
                printf "  ${RED}Failed${RESET}"
                ;;
            encoding)
                printf "${YELLOW}${BOLD}⟳${RESET} %-37s ${YELLOW}%5s%%${RESET}  " "$display_name" "$percent"
                printf "${YELLOW}"; draw_bar "$percent" 32; printf "${RESET}"
                local info=""
                [[ -n "$eta" ]] && info="ETA $eta"
                [[ -n "$fps" && -n "$eta" ]] && info+="  $fps"
                [[ -n "$fps" && -z "$eta" ]] && info="$fps"
                printf "  ${GREY}%s${RESET}" "$info"
                ;;
            queued)
                printf "${BLUE}${BOLD}…${RESET} %-37s ${BLUE}%5s%%${RESET}  " "$display_name" "---"
                printf "${GREY}"; draw_bar 0 32; printf "${RESET}"
                printf "  ${GREY}Queued${RESET}"
                ;;
        esac

        echo ""
    done

    echo ""

    # Scroll indicator
    if [[ $total -gt 10 ]]; then
        printf "  ${GREY}%s${RESET}\n" "$(printf '─%.0s' {1..72})"
        local showing_end=$(( scroll + 10 < total ? scroll + 10 : total ))
        local remaining=$(( total - showing_end ))
        printf "  ${GREY}Showing %d–%d of %d" $(( scroll + 1 )) "$showing_end" "$total"
        [[ $remaining -gt 0 ]] && printf "  (%d more ↓)" "$remaining"
        printf "  |  ↑/↓ to scroll${RESET}\n"
    fi

    printf "  ${GREY}%s${RESET}\n" "$(printf '─%.0s' {1..72})"
    printf "  ${GREY}Auto-refreshes every 2s  |  Q to quit${RESET}\n"
}

# ── Input handling (non-blocking) ─────────────────────────────────────────────
read_key() {
    local key
    IFS= read -r -s -n1 -t 0.1 key 2>/dev/null || true

    if [[ "$key" == $'\x1b' ]]; then
        local seq
        IFS= read -r -s -n2 -t 0.1 seq 2>/dev/null || true
        key="${key}${seq}"
    fi

    printf '%s' "$key"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
main() {
    hide_cursor
    trap 'show_cursor; clear_screen; exit 0' INT TERM EXIT

    local scroll=0
    local last_refresh=0

    while true; do
        local now
        now=$(date +%s)

        # Refresh every 2 seconds
        if (( now - last_refresh >= 2 )); then
            local jobs=()
            collect_jobs jobs
            local total="${#jobs[@]}"
            local max_scroll=$(( total > 10 ? total - 10 : 0 ))
            scroll=$(( scroll > max_scroll ? max_scroll : scroll ))
            render jobs "$scroll" "$(hb_running && echo true || echo false)"
            last_refresh=$now
        fi

        # Non-blocking key read
        local key
        key=$(read_key)

        case "$key" in
            q|Q)
                show_cursor
                clear_screen
                exit 0
                ;;
            $'\x1b[A')  # Up arrow
                (( scroll > 0 )) && (( scroll-- ))
                last_refresh=0  # force immediate redraw
                ;;
            $'\x1b[B')  # Down arrow
                local jobs=()
                collect_jobs jobs
                local max=$(( ${#jobs[@]} > 10 ? ${#jobs[@]} - 10 : 0 ))
                (( scroll < max )) && (( scroll++ ))
                last_refresh=0
                ;;
        esac
    done
}

main

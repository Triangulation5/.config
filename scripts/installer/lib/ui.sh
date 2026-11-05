# shellcheck shell=bash
# lib/ui.sh: everything that writes to the terminal. Knows nothing about
# Silhouette.
#
# Stage status tags, one per stage, fixed width so the titles line up:
#
#   [   Ok   ]  green   the stage did what it said
#   [ Failed ]  red     it did not
#   [  Warn  ]  yellow  it worked, but something needs your attention
#   [  Skip  ]  grey    nothing to do, or you asked it not to
#   [  Dry   ]  cyan    --dry-run: it would have worked, nothing was changed
#   [ Abort  ]  yellow  you said no
#
# Streams: status lines and notes go to stdout. warn and err go to stderr, so
# `install.sh >log` still shows what went wrong on the terminal.

ui_init() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
        YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
    else
        BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
    fi
    if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
        E_RED=$'\033[31m'; E_YELLOW=$'\033[33m'; E_RESET=$'\033[0m'
    else
        E_RED=""; E_YELLOW=""; E_RESET=""
    fi
}
ui_init

PROGRESS_PID=""

say()  { [ -n "$PROGRESS_PID" ] && printf '\r\033[K'; printf '%s\n' "$*"; }
note() { [ -n "$PROGRESS_PID" ] && printf '\r\033[K'; printf '    %s\n' "$*"; }
dim()  { [ -n "$PROGRESS_PID" ] && printf '\r\033[K'; printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { [ -n "$PROGRESS_PID" ] && printf '\r\033[K'; printf '%s  ! %s%s\n' "$E_YELLOW" "$*" "$E_RESET" >&2; }
err()  { [ -n "$PROGRESS_PID" ] && printf '\r\033[K'; printf '%s  x %s%s\n' "$E_RED" "$*" "$E_RESET" >&2; }

# die is for a bad invocation, before any stage has run. Exit status 2.
die()  { progress_stop; err "$*"; exit 2; }

# ui_status KIND TITLE [DETAIL]
ui_status() {
    progress_stop
    local kind="$1" title="$2" detail="${3:-}" tag color=""
    case "$kind" in
        ok)    tag="   Ok   "; color="$GREEN" ;;
        fail)  tag=" Failed "; color="$RED" ;;
        warn)  tag="  Warn  "; color="$YELLOW" ;;
        skip)  tag="  Skip  "; color="$DIM" ;;
        dry)   tag="  Dry   "; color="$CYAN" ;;
        abort) tag=" Abort  "; color="$YELLOW" ;;
        *)     tag="   ??   " ;;
    esac
    printf '[%s%s%s] %s' "$color" "$tag" "$RESET" "$title"
    if [ -n "$detail" ]; then
        printf ' %s(%s)%s' "$DIM" "$detail" "$RESET"
    fi
    printf '\n'
}

# --dry-run support. DRY_SKIPPED records that something was only announced, so
# the stage runner can report [ Dry ] instead of claiming [ Ok ].
DRY_SKIPPED=0

would_do() {
    DRY_SKIPPED=1
    printf '    %swould %s:%s %s\n' "$DIM" "$1" "$RESET" "$2"
}

# run wraps every mutating command, so --dry-run prints the same plan a real
# install would execute. A plain wrapper (not a string echo) keeps the quoting
# of the original command intact.
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        would_do run "$*"
        return 0
    fi
    "$@"
}

# ---- Progress indicators ------------------------------------------------------

# progress_start [LABEL]
# Starts an animated indeterminate progress bar in the background.
# Delays 0.3s before first draw to avoid flicker on instant tasks.
progress_start() {
    local label="${1:-Operation in progress...}"
    [ -t 1 ] || return 0
    [ -n "$PROGRESS_PID" ] && progress_stop

    (
        local bar_width=16 block_len=5 pos=0 dir=1 i bar elapsed=0
        local start_time
        start_time="$(date +%s)"

        # Sleep briefly so near-instant tasks do not flicker
        sleep 0.3 || exit 0

        # Hide cursor during progress animation
        printf '\033[?25l'

        while :; do
            elapsed=$(( $(date +%s) - start_time ))
            bar=""
            for ((i=0; i<bar_width; i++)); do
                if [ "$i" -ge "$pos" ] && [ "$i" -lt "$((pos + block_len))" ]; then
                    if [ "$dir" -eq 1 ] && [ "$i" -eq "$((pos + block_len - 1))" ]; then
                        bar="${bar}>"
                    elif [ "$dir" -eq -1 ] && [ "$i" -eq "$pos" ]; then
                        bar="${bar}<"
                    else
                        bar="${bar}="
                    fi
                else
                    bar="${bar} "
                fi
            done

            printf '\r    [%s%s%s] %s %s(%ds)%s\033[K' \
                "$CYAN" "$bar" "$RESET" "$label" "$DIM" "$elapsed" "$RESET"

            pos=$((pos + dir))
            if [ "$pos" -ge "$((bar_width - block_len))" ]; then
                dir=-1
            elif [ "$pos" -le 0 ]; then
                dir=1
            fi
            sleep 0.1
        done
    ) 2>/dev/null &
    PROGRESS_PID=$!
}

# progress_stop
# Stops the background progress bar and clears the line.
progress_stop() {
    if [ -n "$PROGRESS_PID" ]; then
        kill "$PROGRESS_PID" 2>/dev/null || true
        wait "$PROGRESS_PID" 2>/dev/null || true
        PROGRESS_PID=""
        if [ -t 1 ]; then
            printf '\r\033[K\033[?25h'
        fi
    fi
}

# progress_bar CURRENT TOTAL [LABEL]
# Renders a determinate progress bar: [=========>    ] 65% (13/20) Deploying configs
progress_bar() {
    local cur="$1" total="$2" label="${3:-Operation in progress...}"
    local width=16 filled empty pct bar="" i

    [ "$total" -gt 0 ] 2>/dev/null || return 0
    [ -t 1 ] || return 0

    pct=$(( cur * 100 / total ))
    filled=$(( cur * width / total ))
    empty=$(( width - filled ))

    for ((i=0; i<filled; i++)); do bar="${bar}="; done
    if [ "$filled" -lt "$width" ]; then
        bar="${bar}>"
        empty=$(( empty - 1 ))
    fi
    for ((i=0; i<empty; i++)); do bar="${bar} "; done

    printf '\r    [%s%s%s] %3d%% (%d/%d) %s\033[K' \
        "$CYAN" "$bar" "$RESET" "$pct" "$cur" "$total" "$label"

    if [ "$cur" -ge "$total" ]; then
        printf '\r\033[K'
    fi
}

# progress_wait PID [LABEL]
# Monitors a background PID while animating the progress bar.
progress_wait() {
    local pid="$1" label="${2:-Operation in progress...}"
    if [ ! -t 1 ]; then
        wait "$pid"
        return $?
    fi

    progress_start "$label"
    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.1
    done
    progress_stop

    wait "$pid"
    return $?
}

# progress_run LABEL COMMAND [ARGS...]
# Runs a command while showing the progress bar.
progress_run() {
    local label="$1"
    shift
    if [ "${DRY_RUN:-0}" = "1" ]; then
        would_do run "$*"
        return 0
    fi

    local log
    log="$(mktemp 2>/dev/null || echo "/tmp/silhouette-cmd.$$.log")"
    [ -n "$log" ] && temp_register "$log" 2>/dev/null || true

    "$@" > "$log" 2>&1 &
    local cmd_pid=$!
    progress_wait "$cmd_pid" "$label"
    local rc=$?

    if [ "$rc" -ne 0 ] && [ -s "$log" ]; then
        tail -n 8 "$log" | while IFS= read -r line; do
            dim "$line"
        done
    fi
    [ -n "$log" ] && rm -f -- "$log" 2>/dev/null || true
    return "$rc"
}

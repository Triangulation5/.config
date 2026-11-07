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

PROGRESS_PID=""     # the background spinner, while progress_run has one going
LOG_DIR=""          # where progress_run keeps each command's full log (set by main)
LOGS_WRITTEN=0      # 1 once a log exists, so the summary can say where they are

# Make sure no half-drawn spinner line is on screen before anything is printed.
_ui_clear() {
    if [ -n "$PROGRESS_PID" ] && [ -t 1 ]; then printf '\r\033[K'; fi
    return 0
}

say()  { _ui_clear; printf '%s\n' "$*"; }
note() { _ui_clear; printf '    %s\n' "$*"; }
dim()  { _ui_clear; printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { _ui_clear; printf '%s  ! %s%s\n' "$E_YELLOW" "$*" "$E_RESET" >&2; }
err()  { _ui_clear; printf '%s  x %s%s\n' "$E_RED" "$*" "$E_RESET" >&2; }

# die is for a bad invocation, before any stage has run. Exit status 2.
die()  { progress_stop; err "$*"; exit 2; }

# ui_status KIND TITLE [DETAIL]
ui_status() {
    progress_stop
    _ui_clear
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

# ---- Background tasks ----------------------------------------------------------
#
# A long command (a package install, a clone, an overlay sync) runs as a quiet
# background-style task: ONE spinner line that updates in place, a live one-line
# status taken from the command's own log, and no raw package-manager output on
# screen. The complete log is kept on disk; its last lines are shown only if the
# command fails.
#
#     [    ====>        ] Installing 30 packages with dnf (42s) · Installing: mpv
#
# Rules that keep it from fighting the rest of the output:
#
#   * It only ever wraps a QUIET command, so nothing else writes to the terminal
#     while it animates. It is never started around a whole stage (a stage prints
#     notes and asks questions).
#   * It is never put in front of anything that may prompt (a sudo or su
#     password). A prompt hidden behind a spinner looks exactly like a hang. Use
#     priv_progress / pm_install_quiet (distro.sh) for privileged commands.
#   * Off a terminal there is no animation and the command keeps its output.

# The newest meaningful line of a log, for the spinner's status: colour codes and
# carriage-return redraws removed, truncated to $2 characters.
_progress_tail() {
    local line
    [ -r "$1" ] || return 0
    line="$(tail -c 4096 -- "$1" 2>/dev/null | tr '\r' '\n' \
            | sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -v '^[[:space:]]*$' | tail -n 1)"
    line="${line//$'\t'/ }"
    printf '%s' "${line:0:$2}"
}

# progress_start LABEL [LOGFILE]   animate in the background. The first frame
# waits 0.3s so near-instant commands never flicker; the status line is re-read
# from LOGFILE about once a second.
progress_start() {
    local label="${1:-Working...}" log="${2:-}" parent="$$" cols
    [ -t 1 ] || return 0
    [ -z "$PROGRESS_PID" ] || progress_stop
    cols="${COLUMNS:-}"
    [ -n "$cols" ] || cols="$(tput cols 2>/dev/null || true)"
    [ -n "$cols" ] || cols=80

    (
        # Always leave the cursor visible, however this process ends.
        trap 'printf "\r\033[K\033[?25h"; exit 0' TERM HUP
        local bar_width=16 block_len=5 pos=0 dir=1 i bar elapsed frame=0
        local start="$SECONDS" status="" room

        sleep 0.3 || exit 0
        printf '\033[?25l'
        # Stop on our own if the installer is gone (SIGKILL cannot be trapped),
        # so a dead run never leaves a spinner drawing on the terminal.
        while kill -0 "$parent" 2>/dev/null; do
            elapsed=$(( SECONDS - start ))
            if [ -n "$log" ] && [ $(( frame % 10 )) -eq 0 ]; then
                room=$(( cols - bar_width - ${#label} - 20 ))
                if [ "$room" -ge 12 ]; then status="$(_progress_tail "$log" "$room")"; fi
            fi
            bar=""
            for ((i = 0; i < bar_width; i++)); do
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
            printf '\r    [%s%s%s] %s %s(%ds)%s%s\033[K' \
                "$CYAN" "$bar" "$RESET" "$label" "$DIM" "$elapsed" "$RESET" \
                "${status:+ $DIM· $status$RESET}"

            pos=$((pos + dir))
            if [ "$pos" -ge "$((bar_width - block_len))" ]; then
                dir=-1
            elif [ "$pos" -le 0 ]; then
                dir=1
            fi
            frame=$((frame + 1))
            sleep 0.1
        done
        printf '\r\033[K\033[?25h'
    ) 2>/dev/null &
    PROGRESS_PID=$!
    # Not a tracked job: bash will not print "Terminated" for it, and will not
    # complain with "No record of process" when it is reaped behind our back.
    disown "$PROGRESS_PID" 2>/dev/null || true
}

# progress_stop   stop the spinner, clear its line, restore the cursor.
progress_stop() {
    local pid="$PROGRESS_PID" n
    [ -n "$pid" ] || return 0
    PROGRESS_PID=""
    kill "$pid" 2>/dev/null || true
    # Wait until it is really gone (it is disowned, so no `wait`), so that one
    # last frame cannot land after the line has been cleared.
    for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.02
    done
    kill -9 "$pid" 2>/dev/null || true
    if [ -t 1 ]; then printf '\r\033[K\033[?25h'; fi
    return 0
}

# progress_run LABEL COMMAND [ARGS...]
# Run a quiet command as a background-style task. Output goes to a log kept in
# LOG_DIR; on failure its last 12 lines (only its own, in a shared log) are shown and the log's path is named. The
# command runs in the FOREGROUND, so Ctrl-C reaches it directly. The caller must
# not pass anything that may prompt.
progress_run() {
    local label="$1" log slug line rc=0 keep=0 from=0
    shift

    if [ "${DRY_RUN:-0}" = "1" ]; then
        would_do run "$*"
        return 0
    fi
    # No terminal (CI, a pipe, a log file): no animation, and the command's own
    # output stays in the log where a person debugging it will look.
    if [ ! -t 1 ]; then
        "$@"
        return
    fi

    if [ -n "$LOG_DIR" ] && mkdir -p -- "$LOG_DIR" 2>/dev/null; then
        # PROGRESS_LOGNAME lets a loop of small commands share ONE log (appended
        # to) instead of leaving one file per iteration.
        slug="${PROGRESS_LOGNAME:-${label//[^A-Za-z0-9._-]/_}}"
        log="$LOG_DIR/${slug:0:60}.log"
        if [ -n "${PROGRESS_LOGNAME:-}" ]; then
            printf '== %s\n' "$label" >> "$log" 2>/dev/null && keep=1
        else
            : > "$log" 2>/dev/null && keep=1
        fi
    fi
    if [ "$keep" = "0" ]; then
        if ! log="$(mktemp)"; then
            "$@"
            return
        fi
        temp_register "$log"
    else
        LOGS_WRITTEN=1
    fi

    # Where this command's own output starts in the log (it may be shared).
    from=0
    if [ "$keep" = "1" ]; then from="$(wc -l < "$log" 2>/dev/null || echo 0)"; from="${from//[[:space:]]/}"; fi

    progress_start "$label" "$log"
    if [ -n "${PROGRESS_LOGNAME:-}" ]; then
        "$@" >> "$log" 2>&1 < /dev/null || rc=$?
    else
        "$@" > "$log" 2>&1 < /dev/null || rc=$?
    fi
    progress_stop

    if [ "$rc" -ne 0 ] && [ -s "$log" ]; then
        tail -n +"$((from + 1))" "$log" | tail -n 12 | while IFS= read -r line; do dim "$line"; done
        if [ "$keep" = "1" ]; then dim "full log: $log"; fi
    fi
    if [ "$keep" = "0" ]; then rm -f -- "$log"; fi
    return "$rc"
}

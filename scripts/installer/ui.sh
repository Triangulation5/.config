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

say()  { printf '%s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
dim()  { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$E_YELLOW" "$*" "$E_RESET" >&2; }
err()  { printf '%s  x %s%s\n' "$E_RED" "$*" "$E_RESET" >&2; }

# die is for a bad invocation, before any stage has run. Exit status 2.
die()  { err "$*"; exit 2; }

# ui_status KIND TITLE [DETAIL]
ui_status() {
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

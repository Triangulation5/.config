#!/usr/bin/env bash
#
# Shared error-reporting / notification library for Silhouette scripts.
#
# Usage: source this file
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/lib-notify.sh"
#
# LOG_LEVEL can be: quiet, error, warn, info, debug (default: info)
#   quiet  - no stderr output, no notifications
#   error  - errors only
#   warn   - errors + warnings
#   info   - errors + warnings + info
#   debug  - everything (debug messages never go to the desktop)
#

# Allow overriding the notify tool; set LOG_LEVEL=quiet for test harnesses
NOTIFY_SEND="${NOTIFY_SEND:-notify-send}"
NOTIFY_APPNAME="${NOTIFY_APPNAME:-Silhouette}"
NOTIFY_ICON="${NOTIFY_ICON:-background-change}"
LOG_LEVEL="${LOG_LEVEL:-info}"

_log_level_rank() {
    case "$1" in
        quiet) echo 0 ;;
        error) echo 1 ;;
        warn)  echo 2 ;;
        info)  echo 3 ;;
        debug) echo 4 ;;
        *)     echo 3 ;;
    esac
}

_log_enabled() {
    [ "$(_log_level_rank "$LOG_LEVEL")" -ge "$(_log_level_rank "$1")" ]
}

_red()    { printf '\033[0;31m'; }
_green()  { printf '\033[0;32m'; }
_yellow() { printf '\033[1;33m'; }
_reset()  { printf '\033[0m'; }

# notify TITLE MESSAGE [URGENCY [ICON]]
notify() {
    [ "$LOG_LEVEL" = "quiet" ] && return 0
    local title message urgency icon
    title="${1:-Notification}"
    message="${2:-}"
    urgency="${3:-normal}"
    icon="${4:-$NOTIFY_ICON}"

    command -v "${NOTIFY_SEND}" >/dev/null 2>&1 || return 0
    [ -n "${message}" ] || return 0

    "${NOTIFY_SEND}" -u "${urgency}" -i "${icon}" -a "${NOTIFY_APPNAME}" \
        "${title}" "${message}" >/dev/null 2>&1 || true
}

notify_error() { # TITLE MESSAGE [ICON]
    _log_enabled error || return 0
    local title message icon
    title="${1:-Error}"
    message="${2:-}"
    icon="${3:-$NOTIFY_ICON}"

    printf '%s[ERROR]%s %s\n' "$(_red)" "$(_reset)" "$title" >&2
    if [ -n "$message" ]; then
        printf '%s         %s\n' "$(_red)" "$message" >&2
    fi

    notify "$title" "$message" critical "$icon"
    return 1
}

notify_warn() { # TITLE MESSAGE [ICON]
    _log_enabled warn || return 0
    local title message icon
    title="${1:-Warning}"
    message="${2:-}"
    icon="${3:-$NOTIFY_ICON}"

    printf '%s[WARN]%s %s\n' "$(_yellow)" "$(_reset)" "$title" >&2
    if [ -n "$message" ]; then
        printf '%s        %s\n' "$(_yellow)" "$message" >&2
    fi

    notify "$title" "$message" normal "$icon"
    return 0
}

notify_info() { # TITLE MESSAGE [ICON]
    _log_enabled info || return 0
    local title message icon
    title="${1:-Info}"
    message="${2:-}"
    icon="${3:-$NOTIFY_ICON}"

    printf '%s[INFO]%s %s\n' "$(_green)" "$(_reset)" "$title" >&2
    if [ -n "$message" ]; then
        printf '%s        %s\n' "$(_green)" "$message" >&2
    fi

    notify "$title" "$message" normal "$icon"
    return 0
}

notify_debug() { # TITLE MESSAGE
    _log_enabled debug || return 0
    printf '   [DEBUG] %s\n' "${1:-Debug}" >&2
    if [ -n "${2:-}" ]; then
        printf '           %s\n' "$2" >&2
    fi
    return 0
}

# Record a command that failed and report it. Returns the command's status.
# Usage: report_fail "Context title" command [args...]
report_fail() {
    local title="$1"
    shift
    local rc=0
    if ! "$@"; then
        rc=$?
        notify_error "$title" "Failed: $* (exit ${rc})"
        return "$rc"
    fi
    return 0
}

export -f notify notify_error notify_warn notify_info notify_debug report_fail
export LOG_LEVEL NOTIFY_SEND NOTIFY_APPNAME NOTIFY_ICON

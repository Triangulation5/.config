# shellcheck shell=bash
# lib/prompt.sh: questions.
#
# Prompts read from /dev/tty, never stdin: under `curl | bash` stdin is the
# script. With no terminal there is nobody to ask, and the rule is the same
# everywhere: a question takes its default, and the one gate that must not be
# answered by a default (confirm) says so and lets the caller refuse.
#
# --yes (ASSUME_YES=1) answers every question with its default. It never turns
# a default "no" into a "yes", so it cannot opt you into anything extra.

# Opening /dev/tty is the real test, not -r: with no controlling terminal (CI,
# a container, a pipe) the path exists but the open fails. The probe runs in a
# subshell so bash's redirection error is silenced on that subshell's stderr.
tty_available() { (exec 3</dev/tty) 2>/dev/null; }

# True when a human can be asked.
interactive() {
    [ "${ASSUME_YES:-0}" != "1" ] && tty_available
}

# ask_yn QUESTION DEFAULT(y|n)      status 0 = yes, 1 = no
ask_yn() {
    progress_stop 2>/dev/null || true
    local prompt="$1" def="${2:-n}" hint reply=""
    if ! interactive; then
        [ "$def" = y ]
        return
    fi
    if [ "$def" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '%s %s ' "$prompt" "$hint" > /dev/tty
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        [yY]*) return 0 ;;
        [nN]*) return 1 ;;
        *)     [ "$def" = y ] ;;
    esac
}

# confirm QUESTION     status 0 = yes, 1 = no, 2 = no terminal to ask on.
# --yes counts as an explicit yes: it is the "I read the plan" flag.
confirm() {
    progress_stop 2>/dev/null || true
    local reply=""
    [ "${ASSUME_YES:-0}" = "1" ] && return 0
    tty_available || return 2
    printf '%s [y/N] ' "$1" > /dev/tty
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        [yY]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ask_choice PROMPT DEFAULT KEY...    sets CHOICE to the (first letter of the)
# answer if it is one of KEY, otherwise to DEFAULT.
ask_choice() {
    progress_stop 2>/dev/null || true
    local prompt="$1" def="$2" k reply=""
    shift 2
    CHOICE="$def"
    interactive || return 0
    printf '%s ' "$prompt" > /dev/tty
    read -r reply < /dev/tty || reply=""
    reply="${reply,,}"
    for k in "$@"; do
        if [ "${reply:0:1}" = "$k" ]; then CHOICE="$k"; return 0; fi
    done
    return 0
}

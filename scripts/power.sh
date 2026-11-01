#!/usr/bin/env bash
#
# Unified power action dispatcher for Silhouette.
# Adapts seamlessly across systemd, elogind (OpenRC / Gentoo), and direct fallbacks.
#
# Usage:
#   power.sh suspend
#   power.sh reboot
#   power.sh shutdown | power.sh poweroff
#   power.sh lock
#

set -u

action="${1:-}"

# Check for active init / session managers
is_systemd() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

has_elogind() {
    # elogind provides loginctl and its daemon creates /run/systemd/seats or elogind
    command -v loginctl >/dev/null 2>&1 && { [ -d /run/elogind ] || [ ! -d /run/systemd/system ]; }
}

case "$action" in
    suspend)
        if is_systemd; then
            exec systemctl suspend
        elif has_elogind; then
            exec loginctl suspend
        elif command -v zzz >/dev/null 2>&1; then
            exec zzz
        elif command -v doas >/dev/null 2>&1 && doas -n true 2>/dev/null; then
            exec doas sh -c 'echo mem > /sys/power/state'
        elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            exec sudo sh -c 'echo mem > /sys/power/state'
        elif [ -w /sys/power/state ]; then
            echo mem > /sys/power/state
        else
            echo "power.sh: no supported suspend mechanism found" >&2
            exit 1
        fi
        ;;

    reboot)
        if is_systemd; then
            exec systemctl reboot
        elif has_elogind; then
            exec loginctl reboot
        elif command -v openrc-shutdown >/dev/null 2>&1; then
            exec openrc-shutdown -r now
        else
            exec reboot
        fi
        ;;

    shutdown|poweroff)
        if is_systemd; then
            exec systemctl poweroff
        elif has_elogind; then
            exec loginctl poweroff
        elif command -v openrc-shutdown >/dev/null 2>&1; then
            exec openrc-shutdown -p now
        else
            exec poweroff
        fi
        ;;

    lock)
        scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
        exec "$scripts_dir/lock.sh"
        ;;

    *)
        echo "usage: power.sh <suspend|reboot|shutdown|poweroff|lock>" >&2
        exit 1
        ;;
esac

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

scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if [ -n "$action" ] && [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
    # shellcheck source=lib/lib-rust.sh
    source "$scripts_dir/lib/lib-rust.sh"
    rust_bin="$scripts_dir/bin/silhouette-tools"
    if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" power --help >/dev/null 2>&1; then
        exec "$rust_bin" power "$action"
    fi
fi

# Screen wake-up animation support: capture the framebuffer before suspension so
# the shell can replay it behind the circular grow reveal on resume (see
# services/WakeAnimation.qml). Every capture this shell wants to survive a wake
# is taken here, on the way in, and a failed capture is not fatal — the marker
# still gets written and the shell falls back to a plain fade-in on the way back.
if [ "$action" = "suspend" ]; then
    flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
    wake_enabled="$(jq -r 'if .wakeAnimation == null then true else .wakeAnimation end' "$flags" 2>/dev/null || echo true)"
    if [ "$wake_enabled" = "true" ]; then
        (
            umask 077
            wake_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
            wake_marker="$wake_runtime_dir/silhouette-wake-active"
            monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
            wake_pids=()
            if [ -n "$monitors" ]; then
                for out in $monitors; do
                    [ -n "$out" ] || continue
                    rm -f "$wake_runtime_dir/silhouette-wake-$out.png"
                    grim -o "$out" "$wake_runtime_dir/silhouette-wake-$out.png" 2>/dev/null &
                    wake_pids+=("$!")
                done
                for pid in "${wake_pids[@]}"; do
                    wait "$pid" 2>/dev/null || true
                done
            fi
            printf '1\n' > "$wake_marker"
        )
        # Give Quickshell + Hyprland a moment to composite the solid black pre-wake
        # cover onto the scanout buffer before the kernel freezes userspace, so the
        # monitor does not flash the desktop when it powers back on.
        sleep 0.15
    fi
fi

# Check for active init / session managers
is_systemd() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

has_elogind() {
    # A loginctl binary can be installed without a running logind-compatible
    # service; only select it when elogind answers over the system bus.
    [ ! -d /run/systemd/system ] && command -v loginctl >/dev/null 2>&1 && \
        loginctl list-sessions --no-legend >/dev/null 2>&1
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

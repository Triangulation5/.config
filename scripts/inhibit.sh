#!/usr/bin/env bash
#
# Unified idle/sleep inhibitor for Silhouette.
# Adapts across systemd (systemd-inhibit), elogind (elogind-inhibit), and direct fallbacks.
#
# Usage:
#   inhibit.sh <command> [args...]
#

set -u

WHO="${USER:-silhouette}"
WHY="${INHIBIT_WHY:-keep awake}"

if [ -d /run/systemd/system ] && command -v systemd-inhibit >/dev/null 2>&1; then
    exec systemd-inhibit --what=idle:sleep --who="$WHO" --why="$WHY" --mode=block "$@"
elif command -v elogind-inhibit >/dev/null 2>&1; then
    exec elogind-inhibit --what=idle:sleep --who="$WHO" --why="$WHY" --mode=block "$@"
elif command -v systemd-inhibit >/dev/null 2>&1; then
    exec systemd-inhibit --what=idle:sleep --who="$WHO" --why="$WHY" --mode=block "$@"
else
    # Fallback when no logind inhibitor is available:
    # Run the target command directly (e.g. sleep infinity).
    # Hyprland DPMS is already paused by the Wayland IdleInhibitor surface in PillRoot.
    exec "$@"
fi

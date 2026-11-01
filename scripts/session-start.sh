#!/usr/bin/env bash
#
# Session startup coordinator for Silhouette on Hyprland.
# Invoked by hypr/modules/autostart.lua to establish environment and user daemons.
#
# Adapts cleanly across systemd and OpenRC.
#

set -u

scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

# 1. Update D-Bus and systemd session activation environment
if [ -d /run/systemd/system ] && command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null || true
elif command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null || true
fi

# 2. Audio stack (PipeWire / WirePlumber) on non-systemd / OpenRC
if [ ! -d /run/systemd/system ]; then
    if command -v gentoo-pipewire-launcher >/dev/null 2>&1; then
        pgrep -x pipewire >/dev/null 2>&1 || gentoo-pipewire-launcher &
    elif command -v pipewire >/dev/null 2>&1; then
        if ! pgrep -x pipewire >/dev/null 2>&1; then
            pipewire &
            command -v wireplumber >/dev/null 2>&1 && wireplumber &
            command -v pipewire-pulse >/dev/null 2>&1 && pipewire-pulse &
        fi
    fi
fi

# 3. Idle manager (hypridle)
if [ -f "$scripts_dir/user-service.sh" ]; then
    "$scripts_dir/user-service.sh" start hypridle
fi

# 4. Blue light filter (hyprsunset) if configured
sunset_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"
if [ -f "$sunset_conf" ] && [ -f "$scripts_dir/user-service.sh" ]; then
    "$scripts_dir/user-service.sh" start hyprsunset
fi

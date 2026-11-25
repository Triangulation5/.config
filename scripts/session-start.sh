#!/usr/bin/env bash
#
# Session startup coordinator for Silhouette on Hyprland.
# Invoked by hypr/modules/autostart.lua to establish environment and user daemons.
#
# Adapts cleanly across systemd and OpenRC.
#

set -u

scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

# Session startup errors should be visible on the desktop, not buried in the
# session log. Nothing here aborts the session: a missing idle manager is
# annoying, not fatal.
source "${scripts_dir}/lib/lib-notify.sh"
source "${scripts_dir}/lib/lib-rust.sh"

# 0. Adapt to Rust toolchain availability: expose ~/.cargo/bin and ensure
# native binaries are compiled in the background when Rust is installed, or
# select the Bash/Python fallbacks cleanly when it is not.
if has_rust_toolchain; then
    if rust_pref_enabled; then
        [ -x "$scripts_dir/build-rust-tools.sh" ] && "$scripts_dir/build-rust-tools.sh" --ensure >/dev/null 2>&1 &
        rust_bin="$scripts_dir/bin/silhouette-tools"
        if [ -x "$rust_bin" ] && "$rust_bin" session-start --help >/dev/null 2>&1; then
            exec "$rust_bin" session-start
        fi
    fi
else
    export SILHOUETTE_NO_NATIVE=1
    export SILHOUETTE_FORCE_SHELL=1
    export SILHOUETTE_FORCE_PYTHON=1
fi

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
    "$scripts_dir/user-service.sh" start hypridle \
        || notify_error "Session start" "hypridle start command failed"
    # user-service.sh exits 0 even when the binary is missing, so verify the
    # process really exists before deciding the idle manager is armed.
    sleep 0.5
    pgrep -x hypridle >/dev/null 2>&1 \
        || notify_error "Session start" "hypridle is not running after start (idle timeouts may not arm)"
fi

# 4. Blue light filter (hyprsunset) if configured
sunset_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"
if [ -f "$sunset_conf" ] && [ -f "$scripts_dir/user-service.sh" ]; then
    "$scripts_dir/user-service.sh" start hyprsunset \
        || notify_error "Session start" "hyprsunset start command failed"
    sleep 0.5
    pgrep -x hyprsunset >/dev/null 2>&1 \
        || notify_error "Session start" "hyprsunset is not running after start (night light disabled)"
fi

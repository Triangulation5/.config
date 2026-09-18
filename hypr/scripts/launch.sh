#!/usr/bin/env bash
#
# Launch SilhouetteShell with jemalloc decay tuning.
#
# quickshell links jemalloc (verify: ldd "$(command -v qs)" | grep jemalloc). By
# default the allocator parks freed pages at the session's high-water mark, so
# RSS climbs toward whatever the busiest moment of the session was and stays
# there. The shell's own docs/development/memory.md measures exactly that:
# opening every surface once leaves ~+73 MB that never comes back, only 2-7 MB
# return during the idle reclaim, and a restart is named "the release valve".
# Background-thread decay hands those pages back to the OS as the shell churns,
# which is what removes the need for that restart.
#
# Start the shell through this script - autostart.lua, reload.sh, or by hand -
# so every launch gets the tuning. Calling quickshell/qs directly skips it.
#
# Env:
#   SILHOUETTE_SHELL_DIR  config dir to run
#                         (default ~/.config/quickshell/silhouette-shell)
#
set -u

# background_thread + 100ms decay. 100ms is a deliberate compromise: low enough
# that the shell gives pages back instead of parking at its peak, high enough
# that it is not returning them mid-morph and immediately re-faulting them in.
export MALLOC_CONF="background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100"

shell_dir="${SILHOUETTE_SHELL_DIR:-$HOME/.config/quickshell/silhouette-shell}"
shell_dir="${shell_dir%/}"

if [ ! -f "$shell_dir/shell.qml" ]; then
    echo "launch.sh: no quickshell config at $shell_dir" >&2
    exit 1
fi

# `qs` first, not `quickshell`: pkill/pgrep patterns elsewhere (reload.sh's
# `pkill qs`, leak-probe.sh) match the executable name, which the kernel takes
# from the path actually exec'd. Both names point at the same binary here.
if command -v qs >/dev/null 2>&1; then
    qs_bin=qs
elif command -v quickshell >/dev/null 2>&1; then
    qs_bin=quickshell
else
    echo "launch.sh: quickshell not found in PATH" >&2
    exit 127
fi

# Idempotent. quickshell does not guard against a second instance of the same
# config, and a duplicate stacks another layer surface on the monitor and fights
# it for keyboard focus (scripts/watchdog.sh works around the same hazard). This
# also makes the script safe to call on a Hyprland config reload, not only at
# session start, so nothing has to pkill the shell first.
name="$(basename "$shell_dir")"
if "$qs_bin" -c "$name" ipc show >/dev/null 2>&1; then
    exit 0
fi

exec "$qs_bin" -p "$shell_dir" "$@"

#!/usr/bin/env bash
#
# Build Silhouette's Rust binaries when a Rust toolchain is installed and
# `useRustTools` is enabled.
#
# Modes:
#   build-rust-tools.sh            Build `scripts/bin/silhouette-tools` (exit 1 if cargo missing).
#   build-rust-tools.sh --ensure   Session-startup ensure pass: quietly exit 0 when Rust is
#                                  absent or disabled; otherwise build any missing or outdated
#                                  Rust binaries (`silhouette_watchers`, `sysmon_sampler`,
#                                  `framepump`, and `silhouette-tools`), notify the running
#                                  shell, and hand supervision over from `watchdog-fallback.sh`.
#

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/lib-rust.sh
source "$here/lib/lib-rust.sh"

project="$here/rust-tools"
tools_bin="$here/bin/silhouette-tools"
config_root="$(cd "$here/.." && pwd)"
shell_root="${SILHOUETTE_SHELL_DIR:-$config_root/quickshell/silhouette-shell}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
ready_marker="$runtime_dir/silhouette-rust-ready"

mode="build"
if [ "${1:-}" = "--ensure" ]; then
    mode="ensure"
fi

if ! rust_pref_enabled; then
    echo "Rust tools are disabled; leaving shell fallbacks active." >&2
    exit 0
fi

install_tools_bin() {
    local src="$1"
    mkdir -p "$here/bin"
    local tmp="$tools_bin.tmp.$$"
    install -m 0755 "$src" "$tmp"
    mv -f "$tmp" "$tools_bin"
}

mark_rust_ready() {
    local tmp="$ready_marker.tmp.$$"
    if printf '%s\n' "$$" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$ready_marker" 2>/dev/null || rm -f "$tmp"
    fi
}

needs_rebuild() {
    local bin_path="$1"
    local src_dir="$2"
    [ -x "$bin_path" ] || return 0
    [ -d "$src_dir" ] || return 1
    if [ -n "$(find "$src_dir" -path '*/target' -prune -o \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' \) -newer "$bin_path" -print -quit 2>/dev/null)" ]; then
        return 0
    fi
    return 1
}

if [ "$mode" = "build" ]; then
    if ! has_cargo_toolchain; then
        echo "Rust/Cargo is not installed; shell fallbacks remain active." >&2
        exit 1
    fi
    cargo build --release --manifest-path "$project/Cargo.toml"
    install_tools_bin "$project/target/release/silhouette-tools"
    mark_rust_ready
    exit 0
fi

# --ensure mode: non-fatal startup pass used by Hyprland autostart / session-start.sh.
if ! has_rust_toolchain; then
    exit 0
fi

if command -v flock >/dev/null 2>&1; then
    exec 8>"$runtime_dir/silhouette-rust-build.lock"
    flock -n 8 || exit 0
else
    exec 8>/dev/null
fi

arch="$(uname -m)"
built=0

# 1. Zero-dependency shell helpers first (~1s build time, works with rustc or cargo).
for helper in \
    "watchers:silhouette_watchers" \
    "sysmon:sysmon_sampler" \
    "recording:framepump"
do
    sub="${helper%%:*}"
    bin_name="${helper#*:}"
    helper_dir="$shell_root/utils/$sub"
    helper_bin="$helper_dir/bin/${bin_name}-${arch}"
    if [ -x "$helper_dir/build.sh" ] && needs_rebuild "$helper_bin" "$helper_dir"; then
        if "$helper_dir/build.sh" 8>&- >/dev/null 2>&1; then
            built=1
        fi
    fi
done

# 2. Shared `silhouette-tools` CLI (watchdog, polkit-agent, privacy-watch, wallcolors, etc.).
if has_cargo_toolchain && [ -f "$project/Cargo.toml" ]; then
    if needs_rebuild "$tools_bin" "$project" || ! "$tools_bin" watchdog --help >/dev/null 2>&1; then
        if cargo build --release --manifest-path "$project/Cargo.toml" 8>&- >/dev/null 2>&1; then
            install_tools_bin "$project/target/release/silhouette-tools"
            built=1
        fi
    fi
fi

if [ "$built" -eq 1 ]; then
    mark_rust_ready
fi

# Hand shell supervision over from the POSIX fallback to the zero-fork Rust watchdog
# once `silhouette-tools` is available. Killing `watchdog-fallback.sh` releases the
# watchdog flock without disturbing the detached `qs` shell instance.
if [ -x "$tools_bin" ] &&
   "$tools_bin" watchdog --help >/dev/null 2>&1 &&
   pgrep -f "watchdog-fallback\\.sh silhouette-shell" >/dev/null 2>&1; then
    pkill -f "watchdog-fallback\\.sh silhouette-shell" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "watchdog-fallback\\.sh silhouette-shell" >/dev/null 2>&1 || break
        sleep 0.05
    done
    "$tools_bin" watchdog silhouette-shell --scripts-dir "$here" 8>&- >/dev/null 2>&1 &
    disown || true
fi

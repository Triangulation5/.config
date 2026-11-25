#!/bin/sh
# Watch for clipboard changes and auto-start cliphist storage.

scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
    # shellcheck source=lib/lib-rust.sh
    . "$scripts_dir/lib/lib-rust.sh"
    rust_bin="$scripts_dir/bin/silhouette-tools"
    if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" cliphist-watch --help >/dev/null 2>&1; then
        exec "$rust_bin" cliphist-watch
    fi
fi

start_watcher() {
    selection_type=$1
    pattern="^wl-paste --type $selection_type --watch cliphist store$"
    if ! pgrep -f -- "$pattern" >/dev/null 2>&1; then
        wl-paste --type "$selection_type" --watch cliphist store >/dev/null 2>&1 &
    fi
}

start_watcher text
start_watcher image

exit 0
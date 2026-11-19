#!/bin/sh
# Watch for clipboard changes and auto-start cliphist storage.

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
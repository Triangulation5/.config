#!/bin/sh
# Watch for clipboard changes and auto-start cliphist storage.

# Use more specific pgrep patterns to avoid matching related process chains
# --list-all shows command path explicitly, --list-known restricts to known processes
# (portable approach across systems)

pgrep -f '^wl-paste --type (text|image) --watch cliphist --list-known' >/dev/null 2>&1 || {
    wl-paste --type text --watch cliphist >/dev/null 2>&1 &
}

pgrep -f '^wl-paste --type (text|image) --watch cliphist --list-known' >/dev/null 2>&1 || {
    wl-paste --type image --watch cliphist >/dev/null 2>&1 &
}

exit 0
#!/usr/bin/env bash
#
# A rejected live monitor change must fail and restore the saved layout without
# arming the detached rollback timer.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
out="SilhouetteAudit-$$"
old_file="/tmp/silhouette-display-$out.old"
pending_file="/tmp/silhouette-display-$out.pending"
trap 'rm -rf -- "$tmp"; rm -f -- "$old_file" "$pending_file"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/hyprctl" <<'SH'
#!/bin/sh
case "$1" in
    monitors)
        printf '[{"name":"%s","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1}]\n' "$TEST_MONITOR"
        ;;
    eval)
        printf '%s\n' "$2" >> "$TEST_LOG"
        case "$2" in
            *'mode = "1280x720@60"'*) exit 1 ;;
        esac
        ;;
    *)
        exit 2
        ;;
esac
SH
chmod +x "$tmp/bin/hyprctl"

if PATH="$tmp/bin:$PATH" TEST_MONITOR="$out" TEST_LOG="$tmp/evals" \
    sh "$here/display-apply.sh" apply "$out" 1280x720@60 0x0 1; then
    echo "failed monitor apply unexpectedly succeeded" >&2
    exit 1
fi

[ ! -e "$old_file" ] && [ ! -e "$pending_file" ]
[ "$(wc -l < "$tmp/evals")" -eq 2 ]
grep -q 'mode = "1920x1080@60"' "$tmp/evals"

printf '%s\n' ok

#!/usr/bin/env bash
#
# A nonblocking search must not wait behind a thumbnail request holding the
# shared Wallhaven pacing lock.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
export HOME="$tmp/home"
mkdir -p "$HOME"

# Load only function definitions; the script's command dispatcher is not part
# of this test.
source <(sed '/^case "\${1:-}"/,$d' "$here/wallpaper-search.sh")
base="$(wh_state)"
(
    exec 9>"$base/wh-window.lock"
    flock 9
    : > "$tmp/lock-held"
    sleep 2
) &
holder=$!
for _ in {1..100}; do
    [ -e "$tmp/lock-held" ] && break
    sleep 0.01
done

start="$(date +%s%N)"
if wh_gate --nowait; then
    echo "nonblocking gate unexpectedly acquired a held lock" >&2
    exit 1
fi
elapsed_ms="$(( ($(date +%s%N) - start) / 1000000 ))"
wait "$holder"
[ "$elapsed_ms" -lt 1000 ] || {
    echo "nonblocking gate waited ${elapsed_ms}ms behind the lock" >&2
    exit 1
}

printf '%s\n' ok

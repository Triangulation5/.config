#!/usr/bin/env bash
# leak-probe.sh — sample the running shell's memory over time and stress the
# lazy-loader destroy/recreate path to expose component leaks.
#
# Usage:
#   leak-probe.sh [quiet|stress]          (mode; default stress)
#
# Env knobs:
#   QS_INTERVAL   sample period, seconds (default 2)
#   QS_DURATION   quiet-mode length, seconds (default 60)
#   QS_CYCLES     open/close cycles per surface (default 2)
#   QS_HOLD       seconds to wait after each close (default 20 — must exceed
#                 the 12s surface idle timeout plus a 10s cleaner tick, so the
#                 reclaimer actually destroys the component before the next
#                 open re-creates it)
#   QS_SURFACES   space-separated surface names to cycle (default the heavy,
#                 asynchronously-built ones)
#   QS_SHELL_PATH path the shell runs from (default ~/.config/quickshell/
#                 silhouette-shell/)
#
# A per-cycle RSS step that never comes back down = a leak in the load/unload
# path. A steady upward slope during quiet periods = a slow leak (timers,
# connections, caches). Everything samples to <script dir>/leak-probe.log and a
# summary (baseline/peak/end + least-squares trend) prints at the end.
set -u

MODE="${1:-stress}"
INTERVAL="${QS_INTERVAL:-2}"
DURATION="${QS_DURATION:-60}"
CYCLES="${QS_CYCLES:-2}"
HOLD="${QS_HOLD:-20}"
SHELL_PATH="${QS_SHELL_PATH:-$HOME/.config/quickshell/silhouette-shell/}"
SURFACES="${QS_SURFACES:-calendar launcher clipboard wallpaper settings sysmon}"

LOG="$(dirname "$0")/leak-probe.log"
QS_PID="$(pgrep -f 'qs -p .*silhouette-shell' | head -1)"
[ -n "$QS_PID" ] || { echo "no running shell (qs -p ...) found" >&2; exit 1; }

: > "$LOG"

# Background sampler: writes "sec rss_kb anon_kb" lines.
(
    start_ns=$(date +%s%N)
    while :; do
        sec=$(( ($(date +%s%N) - start_ns) / 1000000000 ))
        rss=$(awk '/VmRSS/{print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
        anon=$(awk '/RssAnon/{print $2}' "/proc/$QS_PID/status" 2>/dev/null || echo 0)
        printf '%s %s %s\n' "$sec" "$rss" "$anon" >> "$LOG"
        sleep "$INTERVAL"
    done
) &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT

echo "# leak-probe pid=$QS_PID mode=$MODE started $(date +%F\ %T)"
echo "# log: $LOG"

open()  { qs -p "$SHELL_PATH" ipc call pill "$1" "" >/dev/null 2>&1; }
close() { qs -p "$SHELL_PATH" ipc call pill hide >/dev/null 2>&1; }

if [ "$MODE" = "quiet" ]; then
    echo "# quiet: sampling $DURATION s idle"
    sleep "$DURATION"
else
    echo "# stress: $CYCLES cycle(s) x [$SURFACES], hold ${HOLD}s after each close"
    for s in $SURFACES; do
        for ((c = 1; c <= CYCLES; c++)); do
            echo "#   open $s ($c/$CYCLES)"
            open "$s"
            sleep 3
            close
            echo "#   closed $s ($c/$CYCLES) — holding ${HOLD}s for reclaimer"
            sleep "$HOLD"
        done
    done
    echo "# quiet tail: sampling ${DURATION}s after the workload"
    sleep "$DURATION"
fi

kill "$SAMPLER" 2>/dev/null
trap - EXIT

awk '
    { t=$1; rss=$2
      if (NR==1) { b=rss; bt=t }
      if (rss>max) { max=rss; maxt=t }
      last=rss; lt=t
      n++; sx+=t; sy+=rss; sxy+=t*rss; sxx+=t*t }
    END {
        printf "\n==== summary ====\n"
        printf "baseline:  %.1f MB (t=%ss)\n", b/1024, bt
        printf "peak:      %.1f MB (t=%ss)\n", max/1024, maxt
        printf "end:       %.1f MB (t=%ss)\n", last/1024, lt
        printf "net:       %+.1f MB over %ss\n", (last-b)/1024, lt-bt
        denom = n*sxx - sx*sx
        if (n > 1 && denom != 0) {
            slope = (n*sxy - sx*sy) / denom   # KB per second
            printf "trend:     %+.1f MB / minute (least squares)\n", slope*60/1024
        }
    }' "$LOG"

echo "# pid now: $(pgrep -f 'qs -p .*silhouette-shell' | head -1)"

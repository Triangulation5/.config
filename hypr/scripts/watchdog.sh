#!/bin/sh
name="$1"
# launch.sh sits beside this script and is the launcher every start is supposed
# to go through; resolve it from this script's own location so the config tree
# stays relocatable.
scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

# Woken, not killed: USR1 is how reload.sh asks this loop to re-check now instead
# of at its next tick, which is what keeps Super+R from waiting the sleep below
# out. Two properties matter, both easy to get wrong:
#
#   - the handler must be a command (`:`), not `trap '' USR1`. An *ignored*
#     signal cannot interrupt `wait` either, so the poke would do nothing at all;
#     a script with no handler yet is worse — the default action for USR1 is
#     termination, so the poke would take the supervisor down with the shell.
#   - it is installed here, before the flock and the loop, so there is no window
#     where a poke can arrive unhandled.
#
# It is harmless wherever it lands: during the launch poll below it only cuts
# one second of waiting short, and `launch()` is idempotent against a running
# shell because it waits for IPC rather than assuming it started one.
trap ':' USR1

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/${name}-watchdog.lock"
flock -n 9 || exit 0

# Bring up a fresh instance, then wait for it to actually answer IPC before
# handing back to the liveness loop. quickshell does not guard against a second
# instance of the same config, so a slow cold start under boot load must not be
# read as a dead shell and respawned, or the duplicates stack up and fight over
# the layer surface and keyboard focus. The wait is capped so a launch that
# never comes up still falls back to the normal retry cadence.
launch() {
    # Through launch.sh, not a bare `qs -c`: it carries the jemalloc decay tuning
    # (MALLOC_CONF), which quickshell otherwise launches without, and the
    # once-per-session state migration, and its own comment asks that every start
    # go through it. It ends by exec'ing the shell, so what this loop waits on is
    # qs itself. `-d` detaches it from the watchdog so the poll below is not
    # blocked by a foreground shell, and `9>&-` keeps it from inheriting the
    # watchdog lock fd — a shell holding that lock would stop any replacement
    # watchdog from ever coming up.
    bash "$scripts_dir/launch.sh" -d 9>&- >/dev/null 2>&1 &
    i=0
    while [ "$i" -lt 30 ]; do
        qs -c "$name" ipc show >/dev/null 2>&1 && return
        sleep 1
        i=$((i + 1))
    done
}

while true; do
    qs -c "$name" ipc show >/dev/null 2>&1 || launch
    # A backgrounded child plus `wait`, not a plain `sleep`: this is the portable
    # shape that lets the USR1 trap above cut the nap short. A plain `sleep` keeps
    # running to the full five seconds before the trap is serviced, which is
    # exactly the tick a reload would still be waiting on. The interrupted sleep
    # is left to expire on its own — one per poke at most, bounded by the same
    # five seconds, so there is nothing to reap.
    sleep 5 &
    wait $!
done

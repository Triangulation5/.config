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
#   - the handler must be a command, not `trap '' USR1`. An *ignored* signal
#     cannot interrupt `wait` either, so the poke would do nothing at all; a
#     script with no handler yet is worse — the default action for USR1 is
#     termination, so the poke would take the supervisor down with the shell.
#   - it is installed here, before the flock and the loop, so there is no window
#     where a poke can arrive unhandled.
#
# A poke also skips the cheap check and goes straight to the full probe: a restart
# was asked for, so answer it with the most thorough question available, and a
# shell whose process is alive can still be wedged behind it.
poked=0
trap 'poked=1' USR1

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/${name}-watchdog.lock"
flock -n 9 || exit 0

# Every child below is spawned with the lock fd closed (`9>&-`), and this is not
# tidiness: a child outlives the process that spawned it. `sleep 5 &` is the one
# that bites — kill this script while it is napping and the orphaned sleep still
# holds the lock, so the replacement started to take over finds it taken and exits
# silently, leaving the session with no supervisor at all. (The shell itself is
# launched with the fd closed for the same reason, and more so: it outlives this
# script by design.)
runtime="${XDG_RUNTIME_DIR:-/tmp}"

# Liveness is asked one of two questions, at two prices:
#
#   cheap — is the instance's process still there (`kill -0`)? A shell builtin,
#       so it costs nothing at all: no process, no probe, no fork. It answers the
#       case that actually happens, a shell that is gone.
#   full — `qs -c "$name" ipc show`. ~54 ms of CPU and a transient 45 MB, because
#       it is a whole quickshell startup just to ask. It is the only check that
#       notices a shell still alive but no longer answering, and it is what
#       decides a restart, so it runs on the ceiling tick below and whenever the
#       cheap check fails.
#
# This started as a socket check (`nc -U -z`, ~5 ms) and changed because the
# connect was not the cost: an in-loop fork+exec measured ~10 ms, more than half
# the full probe's startup between them. Asking the kernel about the pid instead
# is free, and the shell's own pid turns out to be available in the runtime dir it
# already publishes (see resolve below).
#
# Measured here: a full probe every 5 s cost 1.26% of one core; this costs ~0.1%.
# The tick itself is deliberately left at 5 s: it is also how long a session stays
# uncovered after a shell dies *while locked*, since the in-process lock dies with
# it, so it is worth more than the CPU it saves.
ceiling=12                  # ticks between full probes: 12 x 5 s = 60 s
sock=""
shell_pid=""

connect_ok() {
    nc -U -z -w1 "$1" 9>&- >/dev/null 2>&1
}

# True while the instance we are watching is still running. `kill -0` succeeds for
# any process we may signal, and it is a builtin, so the common case — a healthy
# shell — costs this loop nothing per tick.
alive() {
    [ -n "$shell_pid" ] && kill -0 "$shell_pid" 2>/dev/null
}

# Identify the running instance and remember its pid. quickshell publishes an
# index in both directions, and neither is derivable from the config name this
# script is given: by-path/<config hash>/<instance>/ipc.sock names the instance's
# socket, and by-pid/<pid> is a link to that same instance directory. So: find the
# instance whose socket accepts a connection (instances pile up there for the life
# of a session, newest tried first — the case this exists for is a socket gone
# stale behind a shell that has just been replaced), then read its pid back off
# the by-pid index by comparing directories with `-ef`, another builtin.
#
# A wrong answer here cannot cost correctness: it costs one wasted full probe,
# because that probe decides whether to restart and launch.sh asks the same
# question again before starting anything. If the index is ever missing, nothing
# resolves and the loop falls back to probing every tick — the old behaviour, not
# a broken one.
resolve() {
    sock=""
    shell_pid=""
    for s in $(ls -1t "$runtime"/quickshell/by-path/*/*/ipc.sock 2>/dev/null 9>&-); do
        [ -S "$s" ] || continue
        connect_ok "$s" || continue
        dir="${s%/ipc.sock}"
        for p in "$runtime"/quickshell/by-pid/*; do
            if [ "$p" -ef "$dir" ]; then
                sock="$s"
                shell_pid="${p##*/}"
                return
            fi
        done
    done
}

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
        qs -c "$name" ipc show >/dev/null 2>&1 9>&- && return
        sleep 1
        i=$((i + 1))
    done
}

i=0
while true; do
    if [ "$poked" = 0 ] && [ "$((i % ceiling))" -ne 0 ] && alive; then
        :                                   # cheap path: the process is still there
    else
        poked=0
        qs -c "$name" ipc show >/dev/null 2>&1 9>&- || launch
        # Keep what we have while the cheap check still agrees with the full one;
        # otherwise identify again, which is also what picks up the instance a
        # launch above just started.
        alive || resolve
    fi
    # A backgrounded child plus `wait`, not a plain `sleep`: this is the portable
    # shape that lets the USR1 trap above cut the nap short. A plain `sleep` keeps
    # running to the full five seconds before the trap is serviced, which is
    # exactly the tick a reload would still be waiting on. The interrupted sleep
    # is left to expire on its own — one per poke at most, bounded by the same
    # five seconds, so there is nothing to reap.
    sleep 5 9>&- &
    wait $!
    i=$((i + 1))
done

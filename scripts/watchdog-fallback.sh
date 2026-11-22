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

# The lock's own state, as a file the lock writes on every transition ("1"/"0",
# see LockRoot.reportLockState), so the tick below can be read without asking
# logind: this is read every tick, and a gdbus round trip per tick would cost more
# than the supervision it serves. A read here is ~0.02 ms and needs no fork.
lock_marker="$runtime/silhouette-locked"

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
# Measured here: a full probe every 5 s cost 1.26% of one core; asking the kernel
# instead costs ~0.1%, and what is left per tick is the napper — `sleep 0` in this
# loop's shape measured 1.2 ms of fork+exec+wait. The tick is chosen against that
# price, because it is also the latency a dead shell is noticed at, and the two
# states the loop runs in do not want the same number:
#
#   unlocked  1 s     ~0.12% of one core. The tick used to be 5 s in both states,
#                    which was the wrong side of a trade this session had already
#                    settled: the systemd unit it ran carried `RestartSec=1`, and
#                    dropping that unit for this watchdog quietly turned a
#                    one-second recovery into five.
#   locked    0.1 s   ~1.2%, and nobody is waiting on that core. A shell that dies
#                    *while the session is locked* takes the in-process
#                    WlSessionLock down with it, so the session is open — desktop,
#                    windows, whatever was on screen — until a replacement mounts
#                    and re-locks (LockRoot.checkRelock). This tick is the floor
#                    under that whole window, which is what buys the short one:
#                    the tick is now a tenth of the shell's own cold start, so
#                    what is left to wait on is the start itself.
#
# The full probe keeps its 60 s cadence in both states; only the cheap check speeds
# up. A shell that is alive but wedged still takes up to a minute to catch, because
# catching it costs a whole quickshell startup (see `full` above) — and a wedged
# shell still holds the lock it drew, so that window is not the exposed one.
#
# The locked state is not just a shorter sleep on the same path: see the loop
# below, where a dead shell found while locked skips the full probe entirely. That
# probe is a whole quickshell startup spent learning what `kill -0` already said,
# and while locked it is the one question there is no time to ask twice.
tick=1                      # seconds per cheap check, session unlocked
tick_locked=0.1             # ...and while it is locked
ceiling=60                  # ticks between full probes, unlocked: 60 x 1 s = 60 s
ceiling_locked=600          # ...and locked: 600 x 0.1 s = the same 60 s
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

# True while the session is locked, read off the lock's own marker. A missing or
# unreadable marker reads as unlocked: that is the slower tick, not a broken loop,
# and it is what a session whose lock predates this marker looks like.
locked=0
read_lock() {
    locked=0
    [ -f "$lock_marker" ] || return
    lock_value=""
    read -r lock_value <"$lock_marker"
    [ "$lock_value" = 1 ] && locked=1
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
# the layer surface and keyboard focus. The wait is capped, and — more to the
# point — it ends as soon as the launch it is waiting on is itself gone, so a
# launch that never happened costs a tick rather than the whole cap.
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
    child=$!
    # Poll at the tick this pass is running at, so the wait costs the locked state
    # nothing: a 1 s nap here would put a second of pure sleep back on the critical
    # path the tick above was shortened to get out from under.
    i=0
    while [ "$i" -lt "$poll_ticks" ]; do
        qs -c "$name" ipc show >/dev/null 2>&1 9>&- && return
        # Give up the moment the launch itself is gone. launch.sh ends by exec'ing
        # the shell, so this pid is the shell (or launch.sh, for the instant before
        # that exec) — and if it has exited with nothing answering, no shell is
        # coming: launch.sh's own idempotency probe can land on a socket the dead
        # shell has not released yet and exit 0 without starting anything. Waiting
        # the whole budget for a shell that was never started is the one failure
        # this wait must not have, because it is the same open-session seconds the
        # locked tick exists to cut — measured at 33 s of it, against a 0.1 s tick.
        # Handing back at once costs nothing: the caller's next tick relaunches.
        kill -0 "$child" 2>/dev/null || return
        sleep "$step"
        i=$((i + 1))
    done
}

i=0
while true; do
    # Which tick this pass runs at, and how many of them make up the 60 s between
    # full probes. Both follow the lock, so the two move together and the probe
    # cadence does not depend on which state won.
    read_lock
    if [ "$locked" = 1 ]; then
        step="$tick_locked"
        span="$ceiling_locked"
        poll_ticks=150                  # 150 x 0.1 s = 15 s
    else
        step="$tick"
        span="$ceiling"
        poll_ticks=15                   # 15 x 1 s = 15 s
    fi

    if [ "$poked" = 0 ] && [ "$((i % span))" -ne 0 ] && alive; then
        :                                   # cheap path: the process is still there
    elif [ "$locked" = 1 ] && ! alive; then
        # Dead, and the session is locked: skip the full probe. That probe is a
        # whole quickshell startup (~50 ms and a transient 45 MB) spent learning
        # what `kill -0` just said, and it is here — with the desktop covered by
        # nothing but a lock that died with the process — that the milliseconds are
        # the whole point. launch.sh asks the same question again before it starts
        # anything, so the duplicate-shell guard is not lost, only moved to the
        # caller that is about to need it.
        poked=0
        launch
        resolve
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
    # running to the end of the tick before the trap is serviced, which is exactly
    # the tick a reload would still be waiting on. The interrupted sleep is left to
    # expire on its own — one per poke at most, bounded by the same tick, so there
    # is nothing to reap.
    sleep "$step" 9>&- &
    wait $!
    i=$((i + 1))
done

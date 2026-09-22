#!/bin/bash

# Restart the shell. Super+R lands here (hypr/modules/binds.lua).
#
# Two things can bring a killed shell back, and which one applies is decided by
# whether a supervisor is running at all:
#
#   supervisor up — hypr/scripts/watchdog.sh, started by hypr/modules/autostart.lua
#       Killing the shell is the whole request: the watchdog notices IPC stop
#       answering and returns one through launch.sh, tuning and migration
#       included. This script waits for that respawn rather than launching a
#       second shell on top of it, because a duplicate stacks another layer
#       surface on the monitor and fights the first for keyboard focus.
#
#       Waiting is not left to the watchdog's tick: it is poked awake (USR1) so
#       the wait is the shell's start time rather than that plus up to five
#       seconds of liveness sleep. See the poke below for why that signal is safe
#       to send at any moment.
#
#   no supervisor — a session older than the watchdog, or one whose watchdog
#       died, since nothing watches the watcher
#       This script installs one rather than doing its job by hand. The watchdog
#       takes a flock before it does anything, so starting it here is free when
#       one is already up and harmless on a config reload — and from then on the
#       session is supervised like any other, including this restart. A direct
#       launch is still the last resort below, for the case where the supervisor
#       cannot be started at all.

name=silhouette-shell

pkill qs

# Wait for the process to actually be gone before probing anything. SIGTERM lands
# in a few ms, but the socket can answer for a moment after, and a probe that
# reads the dying shell as a live one concludes the reload already happened and
# skips the launch — leaving no shell at all. Capped so a shell that refuses to
# die still falls through to the launch below.
i=0
while [ "$i" -lt 50 ] && pgrep -x qs >/dev/null 2>&1; do
    sleep 0.1
    i=$((i + 1))
done

if pgrep -f "watchdog.sh $name" >/dev/null 2>&1; then
    # Wake the supervisor out of its liveness sleep so it re-checks now. Without
    # this, Super+R could sit on a dead bar for however much of the five-second
    # tick was left. The signal is safe to send at any point in the watchdog's
    # loop because it installs a no-op USR1 handler before it does anything else;
    # a poke that lands during its launch wait only shortens that wait, and one
    # that lands during the sleep makes the next check happen immediately.
    pkill -USR1 -f "watchdog.sh $name" >/dev/null 2>&1
else
    # Start one. Detached, because it outlives this script by design, and quiet:
    # the flock inside it decides whether this instance is the supervisor or just
    # a no-op that exits.
    bash ~/.config/hypr/scripts/watchdog.sh "$name" >/dev/null 2>&1 & disown
fi

# One wait for both cases: whichever supervisor is in charge brings the shell
# back through launch.sh.
for _ in $(seq 1 20); do
    qs -c "$name" ipc show >/dev/null 2>&1 && exit 0
    sleep 0.5
done

# Nothing came back. Launch directly only when there is genuinely no supervisor:
# a second launch beside a running one is the duplicate-shell hazard, so a
# supervisor that is merely slow gets to finish on its own cadence instead.
if pgrep -f "watchdog.sh $name" >/dev/null 2>&1; then
    echo "reload.sh: supervisor has not returned the shell yet; leaving it to do so" >&2
    exit 0
fi

bash ~/.config/hypr/scripts/launch.sh & disown

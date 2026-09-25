pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.lock

/**
 * Lock daemon root. Owns the WlSessionLock surface, the PAM auth, the shared
 * password state, and the pill-to-lock reveal. A touch file (silhouette-lock-trigger)
 * fires the lock fast off the critical path, debounced and primed so the daemon
 * never locks itself on startup.
 */

ShellRoot {
    id: root

    readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    /** Shared password state bridged between the auth input and the lock root. */
    property QtObject pw: QtObject {
        property string text: ""
    }

    /** Drives the pill-to-lock reveal. Kept off while the surface first mounts so the mask starts as the pill, then flipped on to grow it open; flipped back to collapse it before the session actually unlocks. */
    property bool revealed: false

    Auth {
        id: pamAuth
        user: root.currentUser
        onSucceeded: {
            root.revealed = false;
            collapse.restart();
        }
    }

    Timer {
        id: collapse
        interval: 640
        onTriggered: {
            sessionLock.locked = false;
            Cava.enabled = false;
            root.pw.text = "";
            root.clearGrabs();
            root.reportLockState(false);
        }
    }

    /** Fires as soon as the event loop frees after the lock surfaces are built, which is the earliest the grow can start without the fresh output dropping its first frames. */
    Timer {
        id: reveal
        interval: 1
        onTriggered: root.revealed = true
    }

    function doLock(): void {
        /**
         * Already locked: hypridle can re-run lock_cmd a beat after a wake
         * (its idle clock survives the sleep), which lands as a fresh trigger
         * while the lock is still up. Honoring it would replay the reveal and
         * look like the lockscreen reopening itself, so a *stably* locked
         * session just absorbs the trigger and stays put.
         *
         * But if we're mid-unlock (collapse pending after a successful auth),
         * a fresh trigger is a genuine new lock request racing the unlock
         * animation, not a duplicate. Dropping it here would let collapse
         * finish on schedule and unlock anyway, silently eating the request -
         * so cancel the collapse and relock instead.
         */
        if (sessionLock.locked && !collapse.running)
            return;
        collapse.stop();
        root.pw.text = "";
        root.revealed = false;
        sessionLock.locked = true;
        /** Lite mode never starts the lock's cava run; the glow that reads it is
          * dropped with the blur layers (see components/effects/GlowField.qml). */
        Cava.enabled = Flags.lockViz && !Flags.liteMode;
        reveal.restart();
        root.reportLockState(true);
    }

    /**
     * Drop the desktop grabs the lock backdrop was built from — one full-resolution
     * screenshot per output, written by the lock script as silhouette-lock-<output>.png
     * under XDG_RUNTIME_DIR on the way in. Both layers of every lock surface have
     * read them long before the session is unlocked, and nothing removed them after
     * that, so the last thing on screen — its windows, whatever was open — stayed
     * readable in the runtime dir until logout. The sweep belongs on the unlock and
     * nowhere earlier: a cancelled collapse relocks against the same grabs, and the
     * surfaces read the file again every time they mount, so a sweep at lock start
     * or at shell startup would race the script that is writing them. A shell that
     * is killed while locked never reaches the unlock, so its grabs outlive it —
     * XDG_RUNTIME_DIR being wiped at logout is the backstop for that one. The glob
     * is why this is an `rm` in a shell rather than a FileView.
     */
    function clearGrabs(): void {
        /** Reset first, so a sweep that is somehow still in flight re-runs rather than being ignored. */
        grabCleaner.running = false;
        grabCleaner.command = ["sh", "-c", "rm -f \"$1\"/silhouette-lock-*.png", "sh",
            Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"];
        grabCleaner.running = true;
    }
    Process { id: grabCleaner }

    /**
     * Tell logind what the lock is doing, because nothing else on the machine can
     * see it. The shell hosts the lock in-process, so logind's LockedHint only ever
     * got set as a side effect of a lock *asked for through logind* (hypridle's
     * before_sleep calling lock-session) — a lock raised the ordinary way, by the
     * touch-file trigger or the IPC handler, left the hint saying "unlocked" while
     * the screen was covered. Outside readers act on that wrong answer: utils/soak.py
     * is the one in the tree, and it refuses to restart the shell while the session
     * is locked, so a lagging hint lets a relaunch land on top of a live lock. The
     * same hint is read back on start — that is checkRelock below. Best-effort by
     * design: if the call cannot be made, the lock itself is unaffected.
     */
    function reportLockState(locked: bool): void {
        lockedHint.command = ["gdbus", "call", "--system",
            "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1/session/auto",
            "--method", "org.freedesktop.login1.Session.SetLockedHint",
            locked ? "true" : "false"];
        lockedHint.running = true;
    }
    Process { id: lockedHint }

    /**
     * Re-lock on start when the session was locked as the previous shell died. The
     * lock is in-process, so a crash takes the WlSessionLock down with it and leaves
     * the session open; whatever brings a shell back — a supervisor, or reload.sh by
     * hand — starts one that has no idea it was ever locked. The LockedHint written
     * on every transition is that memory: `true` on record means the last lock was
     * never followed by an unlock, so this process locks again at once and covers the
     * same screens. `false` (a fresh login, or a shell that died unlocked) means
     * there is nothing to restore.
     *
     * That is why the hint is read before anything writes it: the report calls in
     * doLock and in the unlock would clear the evidence on the way in. A failed or
     * unreadable query does nothing rather than reporting `false`, so a hint that did
     * say `true` is never erased by a shell that could not check it.
     *
     * The reveal still has an image to open onto, because the grabs the dead lock was
     * built from are exactly the ones the unlock-time sweep cannot reach — see
     * clearGrabs. The re-lock therefore comes up on the desktop as it was when the
     * session was first locked, never on a live capture.
     */
    function checkRelock(): void {
        lockedQuery.command = ["gdbus", "call", "--system",
            "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1/session/auto",
            "--method", "org.freedesktop.DBus.Properties.Get",
            "org.freedesktop.login1.Session", "LockedHint"];
        lockedQuery.running = true;
    }

    /** gdbus prints the property as one line: `(<true>,)` or `(<false>,)`. */
    Process {
        id: lockedQuery
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("<true>") >= 0)
                    root.doLock();
            }
        }
    }

    Component.onCompleted: root.checkRelock()

    /**
     * Fast lock trigger. Spawning a fresh `qs ipc call` client to ask for the lock
     * cost a quarter second of Qt startup on the critical path; instead lock.sh just
     * touches this file and the watch fires the lock, shaving that off the delay.
     * The IPC handler stays as a fallback for any other caller.
     *
     * An external write lands as a burst of change events, so the fire is debounced
     * into one; primed gates out the startup events (including the file's own
     * creation) so the daemon never locks itself on launch.
     */
    property bool triggerPrimed: false
    Timer {
        interval: 800
        running: true
        onTriggered: root.triggerPrimed = true
    }
    Timer {
        id: triggerFire
        interval: 60
        onTriggered: if (root.triggerPrimed)
            root.doLock()
    }
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/silhouette-lock-trigger"
        watchChanges: true
        printErrors: false
        onLoadFailed: setText("0")
        onFileChanged: triggerFire.restart()
    }

    /**
     * The other two ways in, both from logind and both watched by the shell's one
     * logind monitor (services/SuspendWatch — the same monitor the pill's calendar
     * re-anchors off): a `Lock` over the session, which is `loginctl
     * lock-session`, and the sleep half of PrepareForSleep, for a suspend that
     * never passes through hypridle at all (a bare `systemctl suspend`, or a lid
     * close logind handles itself). The hypridle config this shell writes makes
     * its before_sleep_cmd exactly that lock-session call, and without a listener
     * the request stopped at logind: the machine could suspend with the session
     * wide open and come back the same way. Both signals are just more callers of
     * the same doLock the trigger file and the IPC handler use, so the pair a
     * single suspend produces is absorbed by doLock's own already-locked check.
     */
    Connections {
        target: SuspendWatch
        function onLockRequested() { root.doLock(); }
        function onSuspending() { root.doLock(); }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            id: lockSurface
            color: "#160f0a"

            LockSurface {
                anchors.fill: parent
                s: lockSurface.screen ? lockSurface.screen.height / 1080 : 1
                screenName: lockSurface.screen ? lockSurface.screen.name : ""
                auth: pamAuth
                pw: root.pw
                active: root.revealed
            }
        }
    }

    /**
     * IPC: the lock daemon owns its own trigger. The fast path is the touch
     * file watch above; this handler stays as a fallback for any other caller.
     */
    IpcHandler {
        target: "lock"
        function lock(): void { root.doLock(); }
    }

}

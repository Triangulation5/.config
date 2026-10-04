pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The tiling layout of each workspace, for the minimal bar's layout symbol — the
 * `[]=` that dwm draws between the tags and the title.
 *
 * Like Workspacerules this reads hyprctl rather than Quickshell's
 * `Hyprland.workspaces` model, which cannot be trusted on this stack (every
 * workspace parses as id 0, see Workspacerules). `hyprctl workspaces -j` carries
 * each workspace's own `tiledLayout`, so a workspace pinned to another layout by a
 * workspace rule reads as that layout rather than as the global one. The global
 * `general:layout` is read in the same shell spawn as the fallback for a
 * workspace the list does not describe (or a Hyprland that omits the field), so a
 * tick costs one process either way.
 *
 * Results are keyed by workspace *name*, the same key the tags use to decide
 * which one is lit, so the bar never has to translate between two notions of
 * "the active workspace".
 *
 * Hyprland has no raw event for a layout change — `hyprctl keyword` or a
 * `layoutmsg` bind moves the layout without announcing it — so the events below
 * only cover the changes that *are* announced (a window opening in a monocle
 * changes its count, a workspace switch changes which layout is shown) and a slow
 * poll catches the rest. Both are gated on `active`, which the bar root claims
 * when the bar is built and releases when it is torn down, so nothing is read
 * while the pill is the shell on screen.
 *
 * Everything below `refresh()` exists because this symbol used to break on a
 * reload and stay broken: it came back only after the bar was switched off and on
 * again. `hyprctl` itself is reliable across a reload — measured, the workspaces
 * and `general:layout` come back identical either side of one — so the failure was
 * always this service losing a read, and it lost them for one specific reason.
 *
 * `Process.running` was doing duty as "a read is in flight". It cannot. Setting
 * `running = false` only marks the process for termination; the property keeps
 * reading `true` until the process is actually reaped, which is milliseconds for
 * a plain exit but unbounded when what is being killed is a `hyprctl` blocked on a
 * compositor that is busy. So in that window `refresh()` took the "already
 * reading" branch and queued the read in `pending` — and `pending` had exactly one
 * servicer, `onStreamFinished`. Quickshell emits `streamFinished` from the same
 * handler that runs when a process exits, but *not* when one fails to start, and
 * not when the kill is the thing that ended the read. A queue whose only servicer
 * can be skipped is a queue that is never emptied: from then on every refresh saw
 * `running === true`, queued another, and nothing ever read. The symbol stayed
 * blank for the life of the process, and only a bar rebuild that happened to land
 * after the stuck read had been reaped let it start again — which is the "switch
 * dwm style off and on to make it appear" symptom, arrived at by timing rather
 * than by design.
 *
 * The rules below replace that with an arrangement that cannot wedge:
 *
 *   - The in-flight flag is ours (`reading`), not `Process.running`. It is set
 *     when a read is asked for and cleared by the read itself finishing — not by
 *     the state of a property that means something else.
 *   - `start()` is the only way to read. It forces a real rising edge on
 *     `running`, so a `running` left `true` with nothing behind it (a kill still
 *     winding down) cannot swallow the start.
 *   - A queued read is never a latch. The watchdog flushes `pending` whenever
 *     nothing is in flight, so a lost completion costs half a second rather than
 *     the rest of the session.
 *   - A read that hangs is restarted. Nothing here times out on its own, so the
 *     watchdog counts a read that has outlived its welcome and starts a new one.
 *     The same count also covers the opposite case: a read asked for while the
 *     engine is still assembling the config cannot start at all until the reload
 *     settles, and the watchdog is what picks it up when that happens.
 *   - A read that returns nothing usable never overwrites what is already known,
 *     and schedules a fast retry. An empty workspace list is truthy, so a list
 *     that is merely *present* used to blank every workspace at once.
 *   - `layoutOf` falls through to `lastLayout`, the last layout anything actually
 *     reported, so a transient gap reads as the layout that was there rather than
 *     as nothing. The symbol hides only before the very first read has landed.
 */
Singleton {
    id: root

    /**
     * The bar tree currently holding this service, as a token it was handed by
     * `claim()`, or 0 when nobody holds it. A token rather than a plain bool
     * because this singleton outlives the tree that drives it: on an in-place
     * config reload the outgoing bar's `Component.onDestruction` can run *after*
     * the incoming bar has already claimed, and a bare `active = false` there
     * would switch off the poll and the event refresh out from under a bar that
     * is on screen and using them. `release()` ignores a token that is no longer
     * the holder, so a late teardown is a no-op instead of a regression.
     */
    property int claimer: 0
    property int nextToken: 0

    /** True while a bar tree is driving this service. Derived, never assigned. */
    readonly property bool active: root.claimer !== 0

    /** Poll cadence in ms: short enough that a layout-cycle bind feels immediate. */
    property int intervalMs: 1000

    /** workspace name -> { layout, windows }. */
    property var byName: ({})

    /** The global `general:layout`, for a workspace with no layout of its own. */
    property string fallback: ""

    /** The last layout anything actually reported; the floor under `layoutOf`. */
    property string lastLayout: ""

    /**
     * True from the moment a read is asked for until that read's output has been
     * parsed. Ours rather than `Process.running`, which reads `true` for as long
     * as a killed process is still being reaped — the window in which reads used
     * to be queued against something that was not going to answer.
     */
    property bool reading: false

    /** A read asked for while another was in flight; see the watchdog. */
    property bool pending: false

    /** Consecutive watchdog ticks the current read has been in flight. */
    property int stuckTicks: 0

    /**
     * Take the service for a bar tree, returning the token that releases it.
     * Reads immediately: a bar that comes up mid-session should not wait out a
     * poll tick to draw its symbol, and neither should one that comes up across
     * a reload.
     */
    function claim() {
        root.claimer = ++root.nextToken;
        root.refresh();
        return root.claimer;
    }

    /** Give it back — unless a newer bar already has it, which is a reload. */
    function release(token) {
        if (root.claimer !== token)
            return;
        root.claimer = 0;
        root.reading = false;
        root.pending = false;
        root.stuckTicks = 0;
        proc.running = false;
    }

    /** Only the announced events that can change what the symbol shows. */
    readonly property var refreshEvents: ({
        workspace: true, workspacev2: true,
        createworkspacev2: true, destroyworkspacev2: true,
        moveworkspacev2: true, focusedmonv2: true,
        openwindow: true, closewindow: true, movewindowv2: true,
        configreloaded: true
    })

    /** The layout name behind a workspace, or "" when nothing is known yet. */
    function layoutOf(wsName) {
        var w = byName[wsName];
        if (w && w.layout.length > 0)
            return w.layout;
        if (fallback.length > 0)
            return fallback;
        return lastLayout;
    }

    /** How many windows a workspace holds; monocle shows it, dwm-style. */
    function windowsOf(wsName) {
        var w = byName[wsName];
        return w ? w.windows : 0;
    }

    /**
     * dwm's own symbols where dwm has the layout: `[]=` is its tile, which is
     * what Hyprland's master layout is, `[M]` its monocle, and `|||` its column
     * layout, which is the closest thing dwm has to a scrolling strip. Dwindle is
     * the fibonacci patch's `[\]`, the binary-tree split bspwm is known for. As
     * in dwm, a monocle shows how many windows are stacked in it, `[3]`, and
     * falls back to `[M]` on an empty workspace.
     *
     * A layout this does not know yet is its initial in brackets rather than
     * nothing, so a new Hyprland layout shows up as itself instead of vanishing.
     */
    function glyph(layout, windows) {
        switch (layout) {
        case "":
            return "";
        case "master":
            return "[]=";
        case "dwindle":
            return "[\\]";
        case "scrolling":
            return "|||";
        case "monocle":
            return windows > 0 ? "[" + windows + "]" : "[M]";
        }
        return "[" + layout.charAt(0).toUpperCase() + "]";
    }

    /** Ask for a read, coalescing onto the one already running. */
    function refresh() {
        if (!root.active)
            return;
        if (root.reading) {
            root.pending = true;
            return;
        }
        root.start();
    }

    /**
     * The only way to read. The two-step write is deliberate: `running` reads
     * `true` both while a process is genuinely alive and in the window after one
     * was killed but not yet reaped, and a plain `running = true` in that window
     * is swallowed — Quickshell only starts a process on a rising edge with no
     * process behind it. Driving it down first makes the next write a real edge,
     * so this either starts a read now or leaves `targetRunning` set for the
     * process wrapper to act on when the old one is finally reaped. Neither way
     * can the request be dropped.
     */
    function start() {
        root.pending = false;
        root.reading = true;
        root.stuckTicks = 0;
        proc.running = false;
        proc.running = true;
    }

    Process {
        id: proc
        /** Two documents, one spawn: the workspaces, a marker line, the global layout. */
        command: ["sh", "-c",
            "hyprctl -j workspaces; printf '\\n@@\\n'; hyprctl -j getoption general:layout"]
        /**
         * A read is over the moment its output has been handled, whether or not
         * that output was any use. Clearing it here rather than only on a good
         * parse is what keeps a bad read from becoming a stuck one.
         */
        onExited: {
            root.reading = false;
            root.stuckTicks = 0;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.reading = false;
                root.stuckTicks = 0;

                /** Nothing usable came back: keep what we know and come back fast. */
                var usable = false;

                var parts = this.text.split("\n@@\n");

                var list = null;
                try {
                    list = JSON.parse(parts[0]);
                } catch (e) {
                    list = null;
                }
                /**
                 * A list with something in it, not merely a list: `[]` is truthy
                 * and used to blank every workspace on screen, which is how the
                 * symbol disappeared on a reload that answered with an empty
                 * body rather than with no body at all.
                 */
                if (list && list.length > 0) {
                    var map = {};
                    for (var i = 0; i < list.length; i++) {
                        var w = list[i];
                        if (!w || w.name === undefined)
                            continue;
                        map[String(w.name)] = {
                            layout: w.tiledLayout ? String(w.tiledLayout) : "",
                            windows: w.windows ? w.windows : 0
                        };
                    }
                    if (Object.keys(map).length > 0) {
                        root.byName = map;
                        usable = true;
                    }
                }

                try {
                    var opt = JSON.parse(parts[1] || "");
                    /** Only a layout that names one; anything else keeps the old. */
                    if (opt && opt.str && String(opt.str).length > 0) {
                        root.fallback = String(opt.str);
                        usable = true;
                    }
                } catch (e2) {
                }

                /**
                 * The floor, from either half. Recorded only from a real reading,
                 * so `layoutOf` always has something to answer with once the first
                 * read has landed — a workspace missing from the list, or one
                 * reported without a layout, reads as the last layout seen rather
                 * than as nothing at all.
                 */
                if (root.fallback.length > 0)
                    root.lastLayout = root.fallback;
                else {
                    for (var k in root.byName) {
                        if (root.byName[k].layout.length > 0) {
                            root.lastLayout = root.byName[k].layout;
                            break;
                        }
                    }
                }

                if (!usable)
                    retry.restart();

                if (root.pending)
                    root.start();
            }
        }
    }

    /**
     * A read that answered with nothing usable is usually a compositor that is
     * busy rather than one that has nothing to say, so try again well before the
     * next poll tick.
     */
    Timer {
        id: retry
        interval: 300
        repeat: false
        onTriggered: if (root.active) root.refresh()
    }

    /**
     * The wedge guard, and the reason a lost read can no longer be fatal.
     *
     * Two cases, and both of them are cases where nothing else would ever act
     * again:
     *
     *   - Nothing is in flight and something was asked for. A read was queued
     *     against a process that then ended without answering — a failed start, or
     *     a kill that was the thing that finished it — so the completion that was
     *     supposed to drain the queue never came. Start it now.
     *   - Something has been in flight for too long. Nothing here times out on its
     *     own: a `hyprctl` blocked on a busy compositor never returns, and a read
     *     asked for while the engine is still assembling the config cannot start
     *     until the reload settles. Either way `stuckTicks` reaching the limit
     *     means nothing else is going to, so start a new read.
     */
    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: {
            if (!root.reading) {
                root.stuckTicks = 0;
                if (root.pending)
                    root.start();
                return;
            }
            root.stuckTicks++;
            if (root.stuckTicks >= 6)
                root.start();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(event) {
            if (root.refreshEvents[event.name])
                root.refresh();
        }
    }

    Timer {
        interval: root.intervalMs
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }
}
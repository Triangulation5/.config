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
 * Everything below the glyph table exists because this symbol used to break on a
 * reload and stay broken. `hyprctl` itself is reliable across a reload — measured,
 * the workspaces and `general:layout` come back identical either side of one — so
 * the failure was always this service refusing to read again or throwing away what
 * it had. Four rules, each answering one of those:
 *
 *   - A read that returns nothing usable never overwrites what is already known.
 *     An empty workspace list used to pass `if (list)` (an empty array is
 *     truthy) and blank every workspace at once; a `general:layout` with no `str`
 *     used to clear the fallback. A bad read now leaves the last good value alone.
 *   - A read that returns nothing usable schedules a fast retry, so the symbol
 *     comes back in a third of a second instead of waiting out the poll.
 *   - `layoutOf` falls through to `lastLayout`, the last layout anything actually
 *     reported, so a transient gap reads as the layout that was there rather than
 *     as nothing. The symbol hides only before the very first read has landed.
 *   - A read that hangs cannot wedge the service. `proc.running` true means
 *     "refreshing" everywhere else in this file, so a single `hyprctl` that never
 *     returned — which is what a compositor mid-reload looks like — used to mean
 *     no read was ever attempted again. The watchdog counts a read that outlives
 *     its welcome and restarts it.
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

    property bool pending: false

    /** Consecutive watchdog ticks the current read has been in flight. */
    property int stuckTicks: 0

    /** Set by the watchdog, acted on by the next tick (see `watchdog`). */
    property bool restart: false

    /**
     * Take the service for a bar tree, returning the token that releases it.
     * Reads immediately: a bar that comes up mid-session should not wait out a
     * poll tick to draw its symbol.
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
        root.stuckTicks = 0;
        root.restart = false;
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

    function refresh() {
        if (!proc.running)
            proc.running = true;
        else
            pending = true;
    }

    Process {
        id: proc
        /** Two documents, one spawn: the workspaces, a marker line, the global layout. */
        command: ["sh", "-c",
            "hyprctl -j workspaces; printf '\\n@@\\n'; hyprctl -j getoption general:layout"]
        stdout: StdioCollector {
            onStreamFinished: {
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

                if (root.pending) {
                    root.pending = false;
                    proc.running = true;
                }
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
     * The wedge guard. Nothing here times out on its own — a `hyprctl` blocked on a
     * compositor that is mid-reload never returns, and `running` staying true is
     * this file's way of saying "a read is in flight", so every later `refresh()`
     * quietly did nothing. Count a read that is still going after a few ticks and
     * start a new one; `restart` is applied on the following tick rather than by
     * reassigning `running` twice in one handler, so the kill and the respawn are
     * two separate property writes the process wrapper can see separately.
     */
    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: {
            if (root.restart) {
                root.restart = false;
                root.stuckTicks = 0;
                proc.running = false;
                proc.running = true;
                return;
            }
            if (!proc.running) {
                root.stuckTicks = 0;
                return;
            }
            root.stuckTicks++;
            if (root.stuckTicks >= 6)
                root.restart = true;
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
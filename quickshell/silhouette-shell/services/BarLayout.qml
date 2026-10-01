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
 * poll catches the rest. Both are gated on `active`, which the bar root sets when
 * the bar is built and clears when it is torn down, so nothing is read while the
 * pill is the shell on screen.
 */
Singleton {
    id: root

    /** True while the bar is on screen; the poll and the event refresh are gated on it. */
    property bool active: false

    /** Poll cadence in ms: short enough that a layout-cycle bind feels immediate. */
    property int intervalMs: 1000

    /** workspace name -> { layout, windows }. */
    property var byName: ({})

    /** The global `general:layout`, for a workspace with no layout of its own. */
    property string fallback: ""

    property bool pending: false

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
        return fallback;
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

    onActiveChanged: {
        if (active)
            refresh();
    }

    Process {
        id: proc
        /** Two documents, one spawn: the workspaces, a marker line, the global layout. */
        command: ["sh", "-c",
            "hyprctl -j workspaces; printf '\\n@@\\n'; hyprctl -j getoption general:layout"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.split("\n@@\n");

                var list = null;
                try {
                    list = JSON.parse(parts[0]);
                } catch (e) {
                    list = null;
                }
                if (list) {
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
                    root.byName = map;
                }

                try {
                    var opt = JSON.parse(parts[1] || "");
                    if (opt && opt.str)
                        root.fallback = String(opt.str);
                } catch (e2) {
                }

                if (root.pending) {
                    root.pending = false;
                    proc.running = true;
                }
            }
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

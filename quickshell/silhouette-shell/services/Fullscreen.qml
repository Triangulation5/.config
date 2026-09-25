pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * Per-monitor fullscreen state for the pill.
 *
 * The pill retracts off the top edge while a fullscreen client owns a monitor,
 * and a workspace flash yields to it instead of lingering over the content.
 *
 * Two sources are read, cheapest first:
 *
 *   1. `Quickshell.Wayland`'s ToplevelManager — the compositor's own
 *      wlr-foreign-toplevel list. Every toplevel that reports `fullscreen`
 *      marks each screen it sits on, and the property is notified by the
 *      compositor, so a toggle lands on the next frame with no process and no
 *      polling. This is the normal path: nothing below it runs.
 *
 *   2. `hyprctl monitors -j` for each monitor's active workspace *name*, plus
 *      `hyprctl workspaces -j` for each workspace's `hasfullscreen`, joined
 *      into monitorName -> bool. This exists because Quickshell 0.3.1's
 *      Hyprland workspace model is unusable here: Hyprland 0.56 dropped the
 *      `id` field from the `activeWorkspace` object, and the model keys on that
 *      field, so `activeWorkspace.lastIpcObject.hasfullscreen` never reflects
 *      the real state. It is also the fallback for a compositor without the
 *      foreign-toplevel protocol — `Hyprland.toplevels` still works, so a
 *      toplevel list that stays empty while Hyprland reports windows is the
 *      signal that the protocol is missing.
 *
 * The fallback is read on the events that can change it (a fullscreen toggle, a
 * workspace switch, a window opening/closing, a monitor hotplug, a config
 * reload) with a short debounce so window churn cannot spawn a process storm,
 * and it is not started at all while the toplevel protocol is answering.
 */
Singleton {
    id: root

    /** monitorName -> true while that monitor holds a fullscreen toplevel (protocol path). */
    readonly property var tmByMonitor: {
        var out = {};
        var list = ToplevelManager.toplevels.values;
        for (var i = 0; i < list.length; i++) {
            var t = list[i];
            if (!t || !t.fullscreen || !t.screens)
                continue;
            for (var j = 0; j < t.screens.length; j++) {
                var sc = t.screens[j];
                if (sc && sc.name)
                    out[sc.name] = true;
            }
        }
        return out;
    }

    /** True while the foreign-toplevel protocol is handing us a window list. */
    readonly property bool tmUsable: ToplevelManager.toplevels.values.length > 0
    /** Latched once the protocol has ever listed a window, so the fallback does
      * not re-arm just because the last window closed. */
    property bool tmSeen: false

    /** Whether the protocol path is the one to trust. */
    readonly property bool useToplevels: root.tmSeen || root.tmUsable

    onTmUsableChanged: {
        if (root.tmUsable) {
            root.tmSeen = true;
        } else if (!root.tmSeen) {
            /** Never worked — ask the fallback to pick the state up. */
            root.request();
        }
    }

    /** monitorName -> true while that monitor's active workspace is fullscreen (fallback). */
    property var byMonitor: ({})

    /** monitorName -> active workspace name, straight from `monitors -j`. */
    property var activeByMonitor: ({})
    /** workspaceName -> hasfullscreen, straight from `workspaces -j`. */
    property var fullscreenWorkspaces: ({})
    property bool dirty: false

    function isFullscreen(name) {
        return root.useToplevels ? (root.tmByMonitor[name] === true)
                                 : (root.byMonitor[name] === true);
    }

    function rebuild() {
        var out = {};
        for (var mon in root.activeByMonitor)
            out[mon] = root.fullscreenWorkspaces[root.activeByMonitor[mon]] === true;
        root.byMonitor = out;
    }

    /** Coalesce a burst of events into one read of both sources. */
    function request() {
        /** The protocol has the state live; spawning hyprctl would be pure cost. */
        if (root.useToplevels)
            return;
        root.dirty = true;
        debounce.restart();
    }

    function run() {
        if (root.useToplevels)
            return;
        if (monProc.running || wsProc.running) {
            debounce.restart();
            return;
        }
        root.dirty = false;
        monProc.running = true;
        wsProc.running = true;
    }

    Timer {
        id: debounce
        interval: 90
        onTriggered: root.run()
    }

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = null;
                try {
                    mons = JSON.parse(this.text);
                } catch (e) {
                    mons = null;
                }
                if (mons) {
                    var map = {};
                    for (var i = 0; i < mons.length; i++) {
                        var o = mons[i];
                        var aw = o.activeWorkspace;
                        if (aw && aw.name)
                            map[o.name] = aw.name;
                    }
                    root.activeByMonitor = map;
                    root.rebuild();
                }
                if (root.dirty && !wsProc.running)
                    debounce.restart();
            }
        }
    }

    Process {
        id: wsProc
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var list = null;
                try {
                    list = JSON.parse(this.text);
                } catch (e) {
                    list = null;
                }
                if (list) {
                    var fs = {};
                    for (var i = 0; i < list.length; i++)
                        fs[list[i].name] = !!list[i].hasfullscreen;
                    root.fullscreenWorkspaces = fs;
                    root.rebuild();
                }
            }
        }
    }

    Connections {
        target: Hyprland
        /** Only the events that can flip a monitor's fullscreen state. */
        function onRawEvent(event) {
            switch (event.name) {
            case "fullscreen":
            case "workspacev2":
            case "activewindowv2":
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "monitoraddedv2":
            case "monitorremoved":
            case "configreloaded":
                root.request();
                break;
            }
        }
    }

    /**
     * The startup probe belongs to the fallback alone, and is delayed so the
     * toplevel protocol has a frame to answer first: on a session where it
     * works, this never runs and no process is ever spawned.
     */
    Timer {
        interval: 1500
        running: true
        onTriggered: if (!root.useToplevels) root.run()
    }
}

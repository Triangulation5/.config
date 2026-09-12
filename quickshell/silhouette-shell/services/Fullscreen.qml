pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Per-monitor fullscreen state for the pill.
 *
 * The pill retracts off the top edge while a fullscreen client owns a monitor,
 * and a workspace flash yields to it instead of lingering over the content.
 * Neither can read that from Quickshell's Hyprland models on this stack:
 * Hyprland 0.56 dropped the `id` field from the `activeWorkspace` object in
 * `hyprctl monitors -j`, while Quickshell 0.3.1 keys its workspace model on
 * that field — so a monitor's `activeWorkspace.lastIpcObject.hasfullscreen`
 * never reflects the real state and the retract silently never fires.
 *
 * So this singleton reads the two hyprctl sources that are still accurate:
 *   - `hyprctl monitors -j` — each monitor's active workspace *name*.
 *   - `hyprctl workspaces -j` — `hasfullscreen` for each existing workspace.
 * `byMonitor` joins them into monitorName -> bool and is re-read on the events
 * that can change it (a fullscreen toggle, a workspace switch, a window
 * opening/closing, a monitor hotplug, a config reload) with a short debounce so
 * window churn can't spawn a process storm.
 */
Singleton {
    id: root

    /** monitorName -> true while that monitor's active workspace is fullscreen. */
    property var byMonitor: ({})

    /** monitorName -> active workspace name, straight from `monitors -j`. */
    property var activeByMonitor: ({})
    /** workspaceName -> hasfullscreen, straight from `workspaces -j`. */
    property var fullscreenWorkspaces: ({})
    property bool dirty: false

    function isFullscreen(name) {
        return root.byMonitor[name] === true;
    }

    function rebuild() {
        var out = {};
        for (var mon in root.activeByMonitor)
            out[mon] = root.fullscreenWorkspaces[root.activeByMonitor[mon]] === true;
        root.byMonitor = out;
    }

    /** Coalesce a burst of events into one read of both sources. */
    function request() {
        root.dirty = true;
        debounce.restart();
    }

    function run() {
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

    Component.onCompleted: run()
}

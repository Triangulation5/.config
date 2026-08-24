import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.launcher
import "../../utils/launcher/fuzzy.js" as Fuzzy

/**
 * Launcher window root. Shows the launcher on the target monitor with a
 * full-screen overlay, backed by the fuzzy-ranked desktop entries and a persisted
 * usage map (launcher-usage.json) so frequent apps rise to the top; launching an
 * entry executes it and closes.
 */

ShellRoot {
    id: root

    property string query: ""
    property var usage: ({})
    property bool shown: false
    property string targetMonitor: ""

    /**
     * Usage map loads asynchronously so startup never blocks on disk; the first
     * ranking pass sees an empty map and re-ranks the moment it lands. Writes
     * are fire-and-forget (atomicWrites), so launching an app never waits on IO.
     */
    FileView {
        id: usageStore
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/launcher-usage.json"
        atomicWrites: true
        printErrors: false
        onLoaded: parseUsage(usageStore.text())
        onLoadFailed: parseUsage("")
    }

    function parseUsage(raw) {
        try {
            root.usage = raw && raw.length ? JSON.parse(raw) : ({});
        } catch (e) {
            root.usage = ({});
        }
    }

    readonly property var allEntries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay) out.push(src[i]);
        return out;
    }

    readonly property int totalCount: allEntries.length
    readonly property var results: Fuzzy.rank(allEntries, query, usage)

    function run(entry) {
        if (entry) {
            if (entry.id) {
                root.usage[entry.id] = (root.usage[entry.id] || 0) + 1;
                /** Fire-and-forget: the FileView write is async, so launch never blocks on disk. */
                usageStore.setText(JSON.stringify(root.usage));
            }
            entry.execute();
        }
        root.shown = false;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.shown && root.targetMonitor === modelData.name

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "launcher"

            anchors { top: true; left: true; right: true; bottom: true }

            MouseArea {
                anchors.fill: parent
                onClicked: root.shown = false
            }

            Loader {
                id: launcherLoader
                anchors.fill: parent

                active: root.shown && root.targetMonitor === modelData.name

                /**
                 * Focus once the item exists. The window's visible and the
                 * loader's active flip from the same binding, so onVisibleChanged
                 * can fire before the item is built; focusing here instead is
                 * race-free. The item is recreated fresh per open, so query and
                 * selection reset by construction.
                 */
                onItemChanged: if (item) Qt.callLater(item.focusField)

                sourceComponent: Launcher {
                    entries: root.results
                    total: root.totalCount

                    onLaunch: (entry) => root.run(entry)
                    onQuit: root.shown = false
                }
            }

            Connections {
                target: launcherLoader.item
                function onQueryChanged() {
                    root.query = launcherLoader.item.query;
                    launcherLoader.item.selectedIndex = 0;
                }
            }
        }
    }

    /**
     * IPC: the standalone launcher owns its show/hide/toggle surface. Opening
     * builds the whole launcher UI (search + ranked lists), so show/toggle defer
     * the visible flip a tick — the IPC dispatch returns immediately and the
     * surface is constructed off the IPC hot path. Hide stays immediate.
     */
    IpcHandler {
        target: "launcher"
        function show(mon: string): void {
            root.targetMonitor = mon;
            Qt.callLater(function() { root.shown = true; });
        }
        function hide(): void { root.shown = false; }
        function toggle(mon: string): void {
            Qt.callLater(function() {
                if (root.shown) { root.shown = false; return; }
                root.targetMonitor = mon;
                root.shown = true;
            });
        }
    }
}

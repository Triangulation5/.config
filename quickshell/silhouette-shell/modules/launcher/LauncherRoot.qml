import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
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

    FileView {
        id: usageStore
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/launcher-usage.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        var raw = usageStore.text();
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
                usageStore.setText(JSON.stringify(root.usage));
                usageStore.waitForJob();
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
     * IPC: the standalone launcher owns its show/hide/toggle surface.
     */
    IpcHandler {
        target: "launcher"
        function show(mon: string): void { root.targetMonitor = mon; root.shown = true; }
        function hide(): void { root.shown = false; }
        function toggle(mon: string): void {
            if (root.shown) { root.shown = false; return; }
            root.targetMonitor = mon;
            root.shown = true;
        }
    }
}

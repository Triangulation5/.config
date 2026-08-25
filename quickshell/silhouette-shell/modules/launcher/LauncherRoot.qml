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
            /**
             * The launcher appears only once its item is actually built, so
             * the async build never shows a blank window. `status` flips to
             * Ready when the asynchronous load completes, then visible lands.
             */
            visible: root.shown && root.targetMonitor === modelData.name && launcherLoader.status === Loader.Ready

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

            /**
             * Built asynchronously in frame gaps so opening the launcher never
             * blocks the UI thread (the whole ranked entry list instantiates
             * here). Quickshell's LazyLoader can't host this: it is a non-Item
             * window loader, and the launcher content must fill the window as
             * a visual child — so this stays a Qt Loader, just async.
             */
            Loader {
                id: launcherLoader
                anchors.fill: parent

                active: root.shown && root.targetMonitor === modelData.name
                asynchronous: true

                /**
                 * Focus once the item exists. The window's visible gates on
                 * the loader's Ready status rather than onVisibleChanged, so
                 * focus lands after the build completes. The item is recreated
                 * fresh per open, so query and selection reset by construction.
                 */
                onItemChanged: if (item) Qt.callLater(item.focusField)

                sourceComponent: Launcher {
                    entries: root.results
                    total: root.totalCount

                    onLaunch: (entry) => root.run(entry)
                    onQuit: root.shown = false

                    /**
                     * Push the live query up so `root.results` re-ranks as the
                     * user types, and reset the row selection on every change.
                     * Wired here instead of a Connections on the loader's item,
                     * which would touch `.item` from a binding and defeat the
                     * async load.
                     */
                    onQueryChanged: { root.query = query; selectedIndex = 0; }
                }
            }
        }
    }

    /**
     * IPC: the standalone launcher owns its show/hide/toggle surface. The
     * launcher UI builds asynchronously in frame gaps (see launcherLoader), so
     * show/toggle flip `shown` immediately — the IPC dispatch returns without
     * blocking and the window appears the moment the build lands. Hide stays
     * immediate.
     */
    IpcHandler {
        target: "launcher"
        function show(mon: string): void {
            root.targetMonitor = mon;
            root.shown = true;
        }
        function hide(): void { root.shown = false; }
        function toggle(mon: string): void {
            if (root.shown) { root.shown = false; return; }
            root.targetMonitor = mon;
            root.shown = true;
        }
    }
}

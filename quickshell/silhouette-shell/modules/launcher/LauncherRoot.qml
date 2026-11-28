import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.launcher
import "../../utils/launcher/fuzzy.js" as Fuzzy

/**
 * Launcher window root. Shows the launcher on the target monitor with a
 * full-screen overlay, backed by `AppLauncher` and `LauncherMatch`.
 */
ShellRoot {
    id: root

    property string query: ""
    property bool shown: false
    property string targetMonitor: ""

    readonly property var allEntries: AppLauncher.allEntries
    readonly property int totalCount: AppLauncher.total
    readonly property var results: {
        if (!root.shown)
            return [];
        void LauncherMatch.lastSeq;
        var rust = LauncherMatch.resolve(allEntries);
        return rust !== null ? rust : Fuzzy.rank(allEntries, query, AppLauncher.usage);
    }

    Connections {
        target: AppLauncher
        function onAllEntriesChanged() {
            if (root.shown)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
        function onUsageChanged() {
            if (root.shown)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
    }

    onShownChanged: {
        if (!root.shown)
            root.query = "";
        LauncherMatch.setConsumer("overlay", root.shown);
        if (root.shown)
            LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
    }
    onQueryChanged: if (root.shown) LauncherMatch.sendQuery(query)

    function run(entry) {
        if (entry)
            AppLauncher.launchAndRecord(entry);
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
             * blocks the UI thread.
             */
            Loader {
                id: launcherLoader
                anchors.fill: parent

                active: root.shown && root.targetMonitor === modelData.name
                asynchronous: true

                onItemChanged: if (item) Qt.callLater(item.focusField)

                sourceComponent: Launcher {
                    entries: root.results
                    total: root.totalCount

                    onLaunch: (entry) => root.run(entry)
                    onQuit: root.shown = false

                    onQueryChanged: { root.query = query; selectedIndex = 0; }
                }
            }
        }
    }

    /**
     * IPC: the standalone launcher owns its show/hide/toggle surface.
     * While `Flags.barEnabled` is true, these calls drive `BarLauncher` instead.
     */
    IpcHandler {
        target: "launcher"
        function show(mon: string): void {
            if (Flags.barEnabled) {
                BarLauncher.show(mon);
                return;
            }
            root.targetMonitor = mon;
            root.shown = true;
        }
        function hide(): void {
            root.shown = false;
            if (Flags.barEnabled)
                BarLauncher.hide();
        }
        function toggle(mon: string): void {
            if (root.shown) { root.shown = false; return; }
            if (Flags.barEnabled) {
                BarLauncher.toggle(mon);
                return;
            }
            root.targetMonitor = mon;
            root.shown = true;
        }
    }
}

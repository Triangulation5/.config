pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.quicksettings

/**
 * Standalone settings window. A separate PanelWindow (overlay layer, exclusive
 * keyboard focus, dim backdrop) that hosts the searchable settings panel —
 * completely decoupled from the pill: no morph, no surface host, no shared
 * mode ladder. One window per screen, shown only on the target monitor, built
 * on first open via a lazy Loader and torn down when hidden, so an unused
 * panel costs nothing at runtime. Toggled over its own IPC surface
 * (`qs ipc call settings toggle`) or from anywhere in QML through `shown`.
 *
 * Rip-out: delete modules/quicksettings/ and the single SettingsRoot line in
 * shell.qml.
 */
ShellRoot {
    id: root

    property bool shown: false
    property string targetMonitor: ""

    /**
     * Show the panel on `mon` ("" = focused monitor, resolved at call time).
     * Shared by the IPC handlers so toggle/show stay one code path.
     */
    function open(mon: string): void {
        targetMonitor = (mon && mon.length > 0)
            ? mon
            : (Hyprland.focusedMonitor
                ? Hyprland.focusedMonitor.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""));
        shown = true;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            /**
             * Appear only once the panel item is actually built, so the async
             * load never shows a blank window; teardown on hide frees the
             * rows entirely.
             */
            visible: root.shown && root.targetMonitor === modelData.name && panelLoader.status === Loader.Ready

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:settings"

            anchors { top: true; left: true; right: true; bottom: true }

            /** Dim backdrop; clicking it closes, like the launcher. */
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
                opacity: root.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.shown = false
                }
            }

            /**
             * Built asynchronously in frame gaps so opening the panel never
             * blocks the UI thread. The item is recreated fresh per open, so
             * query and focus reset by construction.
             */
            Loader {
                id: panelLoader
                anchors.centerIn: parent
                active: root.shown && root.targetMonitor === modelData.name
                asynchronous: true
                sourceComponent: SettingsPanel {
                    onRequestClose: root.shown = false
                }

                onLoaded: if (item) {
                    item.reset();
                    Qt.callLater(item.focusSearch);
                }
            }

            /** Escape closes the whole panel from anywhere. */
            Item {
                id: escCatcher
                focus: root.shown
                Keys.onEscapePressed: root.shown = false
            }
        }
    }

    /**
     * IPC: the standalone settings window owns its own surface, exactly like
     * the launcher. `toggle`/`show` take a monitor name ("" = focused),
     * resolved at call time against Hyprland's focused monitor.
     */
    IpcHandler {
        target: "settings"
        function show(mon: string): void { root.open(mon); }
        function hide(): void { root.shown = false; }
        function toggle(mon: string): void {
            if (root.shown) { root.shown = false; return; }
            root.open(mon);
        }
    }
}

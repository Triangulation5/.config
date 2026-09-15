import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

import "./modules"
import "./config"

/**
 * Silhouette Settings — a standalone dark, macOS-System-Settings-inspired
 * control panel for the shell. A FloatingWindow (a real compositor-managed
 * floating window, not a panel/overlay) hosting the sidebar + content
 * layout; every control reads and writes the shell's flags.json through the
 * Store singleton, which the running shell watches, so changes apply live.
 *
 * Launch: `qs -p ~/.config/quickshell/silhouette-shell-settings` — or bind:
 * `qs -c silhouette-shell-settings ipc call settings toggle`.
 */
ShellRoot {
    id: root

    property bool shown: false

    FloatingWindow {
        id: window
        visible: root.shown
        implicitWidth: 900
        implicitHeight: 560
        color: "transparent"
        title: "Silhouette Settings"

        Item {
            id: panel
            anchors.fill: parent

            scale: 0.98
            opacity: 0

            Component.onCompleted: {
                scale = 1
                opacity = 1
            }

            Behavior on scale { NumberAnimation { duration: Theme.animWindow; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.animWindow } }

            // Fill + clip live on their own rectangle, separate from the
            // border, so the border's stroke never interacts with the
            // content clip mask.
            Rectangle {
                id: background
                x: 0
                y: 0
                width: Math.floor(parent.width)
                height: Math.floor(parent.height)
                radius: Theme.radiusWindow
                color: Theme.window
                antialiasing: true
                clip: true

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Sidebar {
                        id: sidebar
                        Layout.preferredWidth: 260
                        Layout.fillHeight: true
                    }

                    ContentArea {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        pageIndex: sidebar.currentIndex
                    }
                }
            }

            // Unclipped, drawn on top: a crisp, uniform 1px outline with no
            // seam artifacts from the content clip beneath it.
            Rectangle {
                anchors.fill: background
                radius: Theme.radiusWindow
                color: "transparent"
                border.width: 1
                border.color: Theme.border
                antialiasing: true
            }

            focus: true
            Keys.onEscapePressed: root.shown = false
        }
    }

    /**
     * IPC surface. `toggle` is deliberately zero-arg: keybinds exec it bare
     * and quickshell's IPC rejects calls with fewer arguments than declared.
     */
    IpcHandler {
        target: "settings"
        function show(): void { root.shown = true; }
        function hide(): void { root.shown = false; }
        function toggle(): void { root.shown = !root.shown; }
    }
}

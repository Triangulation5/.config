import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.components
import qs.modules.settingsapp.modules.sidebar
import qs.modules.settingsapp.modules.content

/**
 * Silhouette Settings, as the shell hosts it: the settings dialog and nothing
 * else. A FloatingWindow (a compositor-managed floating window, not a panel or
 * an overlay) hosting the chrome over the rail and the content column; the rail
 * owns the selection and the content area follows it. Every control reads and
 * writes the shell's flags.json through the Store singleton, which is the same
 * file the host shell's Flags service watches, so changes apply live: no reload,
 * no IPC round trip.
 *
 * This was the app's own `shell.qml` while it was a config in its own right. It
 * is an `Item` now, not a `ShellRoot`: there is exactly one root per process and
 * it belongs to the shell, so this is a component the host declares rather than
 * a second root. Nothing else changed — the window, the chrome, the IPC surface
 * and the file it writes are the same.
 *
 * The untouched standalone app is still at `~/.config/quickshell/silhouette-shell-settings`
 * (`qs -p …`); this tree is the copy being folded into the shell.
 *
 * Show it: `qs -c silhouette-shell ipc call settings toggle`.
 */
Item {
    id: root

    /** Whether the dialog is open. The host shell drives this. */
    property bool shown: false

    FloatingWindow {
        id: window

        visible: root.shown
        // This window is a dialog, not a tile, and the compositor is what decides
        // that: a toplevel can ask for nothing. `~/.config/hypr/modules/window-rules.lua`
        // carries a `settings-dialog` rule matching this class and title, which
        // floats it, sizes it and centres it. The size is repeated there because a
        // floating toplevel otherwise keeps whatever size the layout gave it — the
        // two numbers below are what that rule writes, and what the layout is
        // designed around.
        implicitWidth: 900
        implicitHeight: 560
        color: "transparent"
        title: "Silhouette Settings"

        Panel {
            anchors.fill: parent
            open: root.shown
            focus: true

            Keys.onEscapePressed: root.shown = false

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Sidebar {
                    id: sidebar
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true

                    // A page row opens the page; a hit opens the page *and*
                    // names the setting to show. Both go through the rail's own
                    // selection rather than assigning to the content area's
                    // bound `pageIndex`, which would break that binding for
                    // good. Opening a page by name deliberately clears the
                    // target, so a ring can never outlive the search that made
                    // it.
                    onPageSelected: function(pageIndex) {
                        sidebar.currentIndex = pageIndex;
                        content.targetKey = "";
                    }
                    onRowRequested: function(pageIndex, rowKey) {
                        sidebar.currentIndex = pageIndex;
                        content.targetKey = rowKey;
                    }
                }

                ContentArea {
                    id: content
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // The rail owns the selection: the chevrons ask it to move
                    // rather than assigning the index themselves, which would
                    // break this binding for good.
                    pageIndex: sidebar.currentIndex
                    onNavigate: function(step) {
                        sidebar.currentIndex += step;
                        content.targetKey = "";
                    }
                }
            }
        }
    }

    /**
     * IPC surface. `toggle` is deliberately zero-arg: keybinds exec it bare and
     * quickshell's IPC rejects calls with fewer arguments than declared.
     */
    IpcHandler {
        target: "settings"
        function show(): void { root.shown = true; }
        function hide(): void { root.shown = false; }
        function toggle(): void { root.shown = !root.shown; }
    }
}

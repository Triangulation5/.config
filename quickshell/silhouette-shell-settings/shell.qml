import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.modules.sidebar
import qs.modules.content

/**
 * Silhouette Settings entry point — a pure composition root, like the shell's
 * own `shell.qml`. A FloatingWindow (a compositor-managed floating window, not a
 * panel or an overlay) hosting the chrome over the rail and the content column;
 * the rail owns the selection and the content area follows it. Every control
 * reads and writes the shell's flags.json through the Store singleton, which the
 * running shell watches, so changes apply live: no reload, no IPC round trip.
 *
 * Launch: `qs -p ~/.config/quickshell/silhouette-shell-settings` — which opens
 * the window, because running this config *is* how the standalone app is
 * launched. To drive a running instance instead:
 * `qs -c silhouette-shell-settings ipc call settings hide` (show / hide /
 * toggle). `SUPER+comma` no longer targets this config: the shell hosts a copy of
 * the app and the bind talks to the shell's `settings` target, which is always
 * alive. `qs ipc call` reaches a running instance only — it never starts one.
 */
ShellRoot {
    id: root

    /**
     * Whether the dialog is open. Starts open here and closed in the shell's copy
     * (`modules/settingsapp/SettingsApp.qml`): running this config is the launch,
     * so the window should appear rather than wait for an IPC call nobody made,
     * while the shell decides for itself when its dialog is shown.
     */
    property bool shown: true

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

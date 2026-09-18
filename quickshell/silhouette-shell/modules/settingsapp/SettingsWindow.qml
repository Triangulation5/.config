import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.settingsapp.components
import qs.modules.settingsapp.modules.sidebar
import qs.modules.settingsapp.modules.content

/**
 * The settings dialog's window: a FloatingWindow (a compositor-managed floating
 * window, not a panel or an overlay) hosting the chrome over the rail and the
 * content column. The rail owns the selection and the content area follows it.
 * Every control reads and writes the shell's flags.json through the Store
 * singleton, which is the same file the host shell's Flags service watches, so
 * changes apply live: no reload, no IPC round trip.
 *
 * This is the half of the app that only exists while it is on screen, split out
 * of `SettingsApp.qml` so the controller can build it with a Loader and drop it
 * again. Nothing here decides when that happens: the host sets `open`, and a
 * close (Escape, or the controller's own toggle) is reported back as
 * `closeRequested` rather than acted on, because the host owns the lifecycle.
 *
 * The size is repeated in `~/.config/hypr/modules/window-rules.lua`'s
 * `settings-dialog` rule — matching this class and title — because a floating
 * toplevel otherwise keeps whatever size the layout gave it; the two numbers
 * below are what that rule writes, and what the layout is designed around.
 */
FloatingWindow {
    id: window

    /** Whether the dialog should be on screen. The host owns this. */
    property bool open: false

    /** Ask the host to close: Escape, which is the dialog's own dismiss. */
    signal closeRequested()

    visible: window.open
    implicitWidth: 900
    implicitHeight: 560
    color: "transparent"
    title: "Silhouette Settings"

    Panel {
        anchors.fill: parent
        open: window.open
        focus: true

        Keys.onEscapePressed: window.closeRequested()

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

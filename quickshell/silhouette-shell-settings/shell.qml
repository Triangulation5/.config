import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
 * `qs -c silhouette-shell-settings ipc call settings hide` (open / hide /
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

    /**
     * Whether the dialog is drawn on the workspace you are looking at.
     *
     * Hyprland decides where a window lives, not the app, so `shown` on its own
     * can lie: a dialog left open while you moved elsewhere is still `shown`
     * while being invisible, and the toggle would then flip the flag for a window
     * nobody can see — read as the key doing nothing, and needing a second press.
     * The dialog's own toplevel answers it, matched on the title the window rule
     * matches on too. That title is what identifies the window from out here —
     * Quickshell's own toplevels carry no pid — which is why this copy's title is
     * not the shell one's (see `title` below).
     *
     * No toplevel yet reads as `true`: it is on its way, and a window maps on the
     * focused workspace.
     */
    readonly property bool onFocusedWorkspace: {
        var focused = Hyprland.focusedWorkspace;
        if (!focused)
            return true;
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            if (toplevels[i] && toplevels[i].title === window.title)
                return !!toplevels[i].workspace && toplevels[i].workspace.name === focused.name;
        }
        return true;
    }

    /**
     * Bring the dialog to the workspace you are on, keeping what it was showing:
     * hiding and showing again re-maps the window, and the map lands where the
     * focus is. A hidden window is still a live item tree, so nothing inside is
     * torn down by the hide — the rail keeps the page it was on and the search
     * keeps its text.
     */
    function summon(): void {
        root.shown = false;
        Qt.callLater(function () { root.shown = true; });
    }

    /** Open it where you are, or bring it here if it was left elsewhere. */
    function open(): void {
        if (!root.shown)
            root.shown = true;
        else if (!root.onFocusedWorkspace)
            root.summon();
    }

    function hide(): void {
        root.shown = false;
    }

    /** Open if closed or out of sight, close if it is right in front of you. */
    function toggle(): void {
        if (root.shown && root.onFocusedWorkspace)
            root.hide();
        else
            root.open();
    }

    FloatingWindow {
        id: window

        visible: root.shown
        // This window is a dialog, not a tile, and the compositor is what decides
        // that: a toplevel can ask for nothing. `~/.config/hypr/modules/window-rules.lua`
        // carries a `settings-dialog` rule matching this class and title, which
        // floats it, sizes it and centres it — deliberately *not* pinned, since a
        // pinned dialog is drawn over every workspace you switch to. Hyprland maps
        // a window on whichever workspace is focused when it maps, so opening it
        // always lands it in front of you, and a dialog left open while you moved
        // elsewhere is what `open` handles. The size is repeated in the rule because
        // a floating toplevel otherwise keeps whatever size the layout gave it — the
        // two numbers below are what that rule writes, and what the layout is
        // designed around.
        implicitWidth: 900
        implicitHeight: 560
        color: "transparent"
        // Deliberately not the shell copy's title: the title is how a copy finds
        // its own window in the compositor's toplevel list (see
        // onFocusedWorkspace), and the two copies are otherwise windows of the
        // same class with the same name. The window rule in
        // `~/.config/hypr/modules/window-rules.lua` matches
        // "Silhouette Settings.*" for this reason — Hyprland anchors rule regexes,
        // so the suffixed title needs that wildcard to keep its shape.
        title: "Silhouette Settings (standalone)"

        Panel {
            anchors.fill: parent
            open: root.shown
            focus: true

            Keys.onEscapePressed: root.hide()

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
     *
     * Opening is `open`, not `show`: `qs ipc` has a `show` subcommand of its own
     * and swallows the word — `ipc call settings show` prints the target list
     * rather than reaching here — so the call that opens the dialog has to be
     * named something else. `hide` and `toggle` are unaffected and do reach the
     * app, which is what the keybind runs.
     */
    IpcHandler {
        target: "settings"
        function open(): void { root.open(); }
        function hide(): void { root.hide(); }
        function toggle(): void { root.toggle(); }
    }
}

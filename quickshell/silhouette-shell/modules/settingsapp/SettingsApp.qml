import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

/**
 * Silhouette Settings, as the shell hosts it: the dialog's controller and
 * nothing else. It owns the window's lifecycle and the IPC surface; the window
 * itself — the chrome, the rail, the content column — is `SettingsWindow.qml`,
 * which this file builds on demand and drops again.
 *
 * Nothing of the dialog exists until it is asked for. A settings window is not
 * something a session should boot with, and a window tree that is only ever
 * hidden is still a window tree: a rail of eighteen pages, a search model and
 * every page singleton stay resident for the whole session so that a dialog
 * opened once can be reopened quickly. Here the tree is destroyed instead —
 * `built` goes false and the Loader takes the whole item graph with it, five
 * seconds after the close, so the memory goes back to the session and the next
 * open builds a fresh dialog. The cost of that is that the rail does not keep
 * the page or the search it was left on; the window comes back as it was
 * designed, on the first page.
 *
 * The delay is deliberate. It covers the case the window does *not* want to be
 * destroyed: close it, and change your mind — the dialog is still there to be
 * reopened instantly, keeping what it was showing, because nothing has been
 * torn down yet.
 *
 * Show it: `qs -c silhouette-shell ipc call settings toggle` (which is what
 * `SUPER+comma` runs). The call has to reach this process, and `qs ipc call`
 * reaches a running instance only — it never starts one.
 */
Item {
    id: root

    /** Whether the dialog is open. The host shell drives this. */
    property bool shown: false

    /** Whether the dialog's window tree exists at all. */
    property bool built: false

    /** The live window, or null while nothing is built. */
    readonly property var window: win.item

    /**
     * How long a closed dialog is kept before its tree is torn down. Long
     * enough that closing and immediately reopening keeps the dialog you had,
     * short enough that a window opened once does not stay with the session.
     */
    readonly property int teardownMs: 5000

    /**
     * Whether the dialog is drawn on the workspace you are looking at.
     *
     * Hyprland decides where a window lives, not the app, so `shown` on its own
     * can lie: a dialog left open while you moved elsewhere is still `shown`
     * while being invisible, and the toggle would then flip the flag for a window
     * nobody can see — read as the key doing nothing, and needing a second press.
     * The dialog's own toplevel answers it, matched on the title the window rule
     * matches on too. That title is what identifies the window from out here —
     * Quickshell's own toplevels carry no pid, so the title is the only handle on them
     * (see `SettingsWindow.qml`).
     *
     * No window at all — nothing built yet, or nothing left after a teardown —
     * reads as `true`: there is no invisible dialog to correct, and a window maps
     * on the focused workspace when it is built.
     */
    readonly property bool onFocusedWorkspace: {
        if (!root.window)
            return true;
        var focused = Hyprland.focusedWorkspace;
        if (!focused)
            return true;
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            if (toplevels[i] && toplevels[i].title === root.window.title)
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
        teardown.stop();
        root.built = true;
        if (!root.shown)
            root.shown = true;
        else if (!root.onFocusedWorkspace)
            root.summon();
    }

    function hide(): void {
        if (!root.shown)
            return;
        root.shown = false;
        teardown.restart();
    }

    /** Open if closed or out of sight, close if it is right in front of you. */
    function toggle(): void {
        if (root.shown && root.onFocusedWorkspace)
            root.hide();
        else
            root.open();
    }

    /**
     * The window, built on the first open and destroyed by `teardown` after a
     * close. Built asynchronously, the way the pill builds its heavy surfaces:
     * the first open is the only one that pays for the rail's eighteen pages and
     * the content column, and it pays off the GUI thread rather than stalling
     * every other surface in the shell while it compiles.
     *
     * `onItemChanged` rather than `onLoaded`, because what this wires — the
     * `open` it should draw and the `closeRequested` its Escape key raises — is
     * about the item, not about the load finishing.
     */
    Loader {
        id: win
        active: root.built
        asynchronous: true
        source: Qt.resolvedUrl("SettingsWindow.qml")

        onItemChanged: {
            if (!win.item)
                return;
            win.item.open = Qt.binding(function () { return root.shown; });
            win.item.closeRequested.connect(root.hide);
        }
    }

    /** Runs from the close to the teardown: after this, nothing of it is left. */
    Timer {
        id: teardown
        interval: root.teardownMs
        onTriggered: root.built = false
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

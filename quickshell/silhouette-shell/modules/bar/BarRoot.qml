import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services
import qs.modules.bar

/**
 * Minimal DWM-style bar root. One strip per monitor, built only while
 * `Flags.barEnabled` is set — shell.qml keeps the bar and the pill in
 * LazyLoaders and builds whichever of the two the flag names, so this whole
 * module is absent, not merely hidden, while the pill is the shell on screen.
 *
 * The bar is a readout, so the only state it owns is the two things a readout
 * needs to stay honest: the Hyprland models it draws from, and the vitals
 * sampler. The pill root normally refreshes those models on compositor events;
 * with the pill unloaded the bar has to do it itself, which is why the event set
 * below is the pill's own list rather than a second, narrower one.
 *
 * The `bar` IPC target is not here: it lives on the shell root, because a target
 * inside this module would be absent in exactly the state a bind needs it — the
 * bar is built only while `Flags.barEnabled` is set, so the one thing an IPC
 * surface for the bar must outlive is the bar. It flips the same flag the
 * settings app writes, so a keybind or script and the toggle stay one source of
 * truth.
 *
 * The launcher's IPC target (`barlauncher`) *is* here, for the opposite reason: it
 * only means something while the bar is up, since the launcher is drawn inside
 * the strip. A call made while the pill is the shell finds no such target, which
 * is the honest answer — there is no bar to open it in. It opens on the focused
 * output. The opener is `open` rather than `show` because `qs ipc` has a `show`
 * subcommand of its own and swallows the word; `toggle` is zero-arg for the same
 * reason the settings app's is, so a keybind can exec it bare:
 *
 *     qs -c silhouette-shell ipc call barlauncher toggle
 *
 * The power list's target (`barpower`) is here for exactly the same reason and on
 * the same terms.
 *
 * The launcher's usual bind is the pill's own call, `qs ipc call pill launcher`,
 * and with the pill unbuilt that target does not exist, so the bind would land
 * nowhere. While the bar is the shell this module therefore answers to `pill`
 * for `launcher` and `power`, opening the in-strip version of each on the output
 * the bind names (an empty name means the focused one, as it does for the pill).
 * The standalone `launcher` target reaches the same launcher too (LauncherRoot
 * routes it), so whichever of the two binds is in use needs no change;
 * `barlauncher` is the explicit route that works on its own.
 *
 * Two handlers must never hold the name `pill` at once, and the pill's own is
 * built and torn down by shell.qml's loaders on the same flag that builds this
 * module. So the stand-in is armed a moment *after* the bar is up, by which time
 * the pill is gone, and is dropped the instant the flag goes off, before the
 * pill's handler comes back for the name. See `pillShim`.
 */
ShellRoot {
    id: root

    /**
     * Only these raw events can change what the strip renders — the active
     * workspace, the focused window, monitor hotplug. Window-title spam must not
     * trigger the model refresh, which costs three Hyprland IPC round trips.
     */
    readonly property var refreshEvents: ({
        workspace: true, workspacev2: true,
        createworkspace: true, createworkspacev2: true,
        destroyworkspace: true, destroyworkspacev2: true,
        moveworkspace: true, moveworkspacev2: true,
        renameworkspace: true, activespecial: true,
        focusedmon: true, focusedmonv2: true,
        openwindow: true, closewindow: true,
        movewindow: true, movewindowv2: true,
        fullscreen: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    /** The output the launcher opens on: the focused one, or the first if none is. */
    function focusedName() {
        if (Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    Component.onCompleted: {
        root.refresh();
        BarStatus.active = true;
        root.layoutClaim = BarLayout.claim();
    }

    /**
     * The launcher lives in a singleton, which outlives this tree. Closing it on
     * the way out keeps a bar built later — after the flag is flipped off and on
     * again — from coming up with a launcher already open on it.
     */
    Component.onDestruction: {
        root.pillShim = false;
        BarStatus.active = false;
        BarLayout.release(root.layoutClaim);
        BarLauncher.hide();
        BarPower.hide();
    }

    /**
     * The token this tree holds on `BarLayout`, released on the way out. The
     * layout service outlives this tree, so a plain bool cannot express "this bar
     * is done with it" — on an in-place reload the outgoing bar's destruction can
     * land after the incoming bar has already claimed, and switching the service
     * off there would strand the symbol with no poll and no events behind it. See
     * `BarLayout.claim`.
     */
    property int layoutClaim: 0

    /**
     * Whether this module is answering to the pill's IPC name. False from the
     * moment the bar is built until the timer below arms it, and false again the
     * instant `Flags.barEnabled` goes off — both ends of the window the pill's own
     * handler can overlap with.
     */
    property bool pillShim: false

    Timer {
        interval: 250
        running: true
        onTriggered: root.pillShim = Flags.barEnabled
    }

    Connections {
        target: Flags
        function onBarEnabledChanged() {
            if (!Flags.barEnabled)
                root.pillShim = false;
        }
    }

    /**
 * The pill's launcher and power calls, answered by the bar. Only those two are
 * stood in for: they are the two the strip has a version of. The other pill
 * surfaces (mixer, calendar, ...) are the pill's own and have nothing to open on
     * a bar — a call naming one while the bar is up finds no such function, which
     * is the honest answer rather than a silently wrong surface.
     */
    IpcHandler {
        target: "pill"
        enabled: root.pillShim

        function launcher(mon: string): void { BarLauncher.toggle(mon); }
        function power(mon: string): void { BarPower.toggle(mon); }
    }

    IpcHandler {
        target: "barlauncher"

        function open(): void { BarLauncher.show(root.focusedName()); }
        function hide(): void { BarLauncher.hide(); }
        function toggle(): void { BarLauncher.toggle(root.focusedName()); }
    }

    IpcHandler {
        target: "barpower"

        function open(): void { BarPower.show(root.focusedName()); }
        function hide(): void { BarPower.hide(); }
        function toggle(): void { BarPower.toggle(root.focusedName()); }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.refreshEvents[event.name])
                root.refresh();
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {}
    }
}

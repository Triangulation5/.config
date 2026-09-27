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

    Component.onCompleted: {
        root.refresh();
        BarStatus.active = true;
    }
    Component.onDestruction: BarStatus.active = false

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

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The Hyprland plumbing the config services share: one reload path and one
 * place a failed reload is reported from. A reload is debounced because a
 * settings change is usually a burst (a drag writes several times) and
 * `hyprctl reload` re-reads every file the compositor owns.
 *
 * Services must not grow dependencies on the app's own modules to use this —
 * it knows about Hyprland and nothing else.
 */
Singleton {
    id: root

    /** Non-empty when the last reload failed; surfaces read it as a note. */
    property string note: ""

    /** Queue a reload. Safe to call on every keystroke of a drag. */
    function reload() {
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 250
        repeat: false
        onTriggered: reloadProc.running = true
    }

    Process {
        id: reloadProc
        command: ["sh", "-c", "sleep 0.3; hyprctl reload"]
        onExited: function (exitCode) {
            root.note = exitCode === 0 ? "" : "Hyprland reload failed. The change is saved but not applied.";
        }
    }
}

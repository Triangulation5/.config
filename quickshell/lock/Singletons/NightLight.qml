pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Night Light service for hyprsunset integration.
 */
Singleton {
    id: root

    property bool enabled: false

    function setEnabled(on) {
        root.enabled = on;
        if (on) {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", "4000"]);
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
    }
}

pragma Singleton
import QtQuick
import Quickshell

/**
 * System power management singleton following project conventions.
 */
Singleton {
    id: root

    function suspend() {
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    function reboot() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function shutdown() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Bluetooth integration singleton for power status and control.
 */
Singleton {
    id: root

    property bool bluetoothActive: true

    function setBluetooth(on) {
        root.bluetoothActive = on;
        Quickshell.execDetached(["bluetoothctl", "power", on ? "on" : "off"]);
    }
}

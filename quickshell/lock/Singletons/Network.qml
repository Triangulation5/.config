pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * NetworkManager integration singleton for Wi-Fi status and control.
 */
Singleton {
    id: root

    property bool wifiEnabled: true
    property string currentNetwork: "Connected"

    function setWifiEnabled(on) {
        root.wifiEnabled = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
    }

    Process {
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(":");
                    if (parts[0] === "yes" && parts.length > 1) {
                        root.currentNetwork = parts[1];
                        return;
                    }
                }
            }
        }
    }
}

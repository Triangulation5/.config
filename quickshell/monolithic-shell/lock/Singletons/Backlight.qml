pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Backlight service for lockscreen brightness control using brightnessctl / sysfs.
 */
Singleton {
    id: root

    property real brightness: 0.85
    property bool present: false

    function setBrightness(val) {
        var pct = Math.max(1, Math.min(100, Math.round(val * 100)));
        root.brightness = pct / 100.0;
        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
    }

    Process {
        command: ["sh", "-c", "dev=$(ls /sys/class/backlight 2>/dev/null | head -n1); [ -n \"$dev\" ] || exit 0; max=$(cat /sys/class/backlight/$dev/max_brightness); cur=$(cat /sys/class/backlight/$dev/brightness); echo \"$(( cur * 100 / max ))\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim(), 10);
                if (!isNaN(v)) {
                    root.brightness = Math.max(0.01, Math.min(1.0, v / 100.0));
                    root.present = true;
                }
            }
        }
    }
}

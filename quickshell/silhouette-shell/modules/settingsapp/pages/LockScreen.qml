pragma Singleton

import QtQuick

/**
 * Lock Screen: the three idle timeouts the shell writes into hypridle.conf (0
 * turns a stage off) and the password bead animation.
 */
QtObject {
    readonly property string name: "Lock Screen"
    readonly property string icon: "\u25A1"

    readonly property var groups: [
        { card: "Idle", rows: [
            { key: "idleLockMin", type: "slider", label: "Auto-lock", min: 0, max: 15, step: 1, unit: "min",
              caption: "Lock the screen after idle (0 = off)", reset: 3 },
            { key: "idleScreenOffMin", type: "slider", label: "Screen off", min: 0, max: 15, step: 1, unit: "min",
              caption: "Blank the display after idle (0 = off)", reset: 0 },
            { key: "idleSuspendMin", type: "slider", label: "Suspend", min: 0, max: 60, step: 1, unit: "min",
              caption: "Sleep the machine after idle (0 = off)", reset: 0 }
        ]},
        { card: "Password", rows: [
            { key: "lockDotsMode", type: "segmented", label: "Dots animation",
              caption: "Password bead entrance on the lock screen",
              options: ["drop", "pulse", "gpixel"], names: ["Drop", "Pulse", "GPixel"], reset: "gpixel" }
        ]}
    ]
}

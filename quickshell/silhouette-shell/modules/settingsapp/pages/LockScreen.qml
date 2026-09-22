pragma Singleton

import QtQuick

/**
 * Lock Screen: the three idle timeouts the shell writes into hypridle.conf (0
 * turns a stage off), what the lock screen may show before it is unlocked, the box
 * the password field is drawn in, the backdrop's blur, and the password bead
 * animation.
 *
 * The three timeouts are flags that the shell turns into a whole file — see the
 * shell's IdleLock surface — so they are settings, not config edits. The sizes
 * and the bead timeline used to be constants in `modules/lock/`.
 */
QtObject {
    readonly property string name: "Lock Screen"
    readonly property string icon: "\u25A1"
    readonly property string keywords: "lock idle dim dpms suspend timeout password avatar backdrop blur bead animation screen privacy private hide redact media music ssid wifi network name"

    readonly property var groups: [
        { card: "Idle", rows: [
            { key: "idleLockMin", type: "slider", label: "Auto-lock", min: 0, max: 15, step: 1, unit: "min",
              caption: "Lock the screen after idle (0 = off)", reset: 3 },
            { key: "idleScreenOffMin", type: "slider", label: "Screen off", min: 0, max: 15, step: 1, unit: "min",
              caption: "Blank the display after idle (0 = off)", reset: 0 },
            { key: "idleSuspendMin", type: "slider", label: "Suspend", min: 0, max: 60, step: 1, unit: "min",
              caption: "Sleep the machine after idle (0 = off)", reset: 0 }
        ]},
        { card: "Privacy", rows: [
            { key: "lockPrivacy", type: "toggle", label: "Hide private info",
              caption: "Keep the now-playing card, the wifi name and your real name off the lock", reset: false }
        ]},
        { card: "Surface", rows: [
            { key: "lockPillW", type: "slider", label: "Field width",
              min: 120, max: 320, step: 4, unit: "px",
              caption: "How wide the password field is drawn", reset: 176 },
            { key: "lockPillH", type: "slider", label: "Field height",
              min: 28, max: 80, step: 2, unit: "px", reset: 42 },
            { key: "lockAvatarSize", type: "slider", label: "Avatar",
              min: 60, max: 220, step: 4, unit: "px",
              caption: "Size of the user picture above the field", reset: 120 }
        ]},
        { card: "Backdrop", rows: [
            { key: "lockBlurSpread", type: "slider", label: "Blur spread",
              min: 0, max: 6, step: 0.2, unit: "",
              caption: "How far the wallpaper blur reaches behind the lock", reset: 2.4 }
        ]},
        { card: "Password", rows: [
            { key: "lockDotsMode", type: "segmented", label: "Dots animation",
              caption: "Password bead entrance on the lock screen",
              options: ["drop", "pulse", "gpixel"], names: ["Drop", "Pulse", "GPixel"], reset: "gpixel" },
            { key: "lockBeadMs", type: "slider", label: "Bead timeline",
              min: 100, max: 900, step: 25, unit: "ms",
              caption: "One bead's flourish and delete, phases and all", reset: 350 }
        ]}
    ]
}

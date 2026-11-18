pragma Singleton

import QtQuick

/**
 * Lock Screen: the three idle timeouts the shell writes into hypridle.conf (0
 * turns a stage off), what the lock screen may show before it is unlocked, the box
 * the password field is drawn in, the backdrop's blur and grade, the password bead
 * animation, and what too many wrong passwords does.
 *
 * The three timeouts are flags that the shell turns into a whole file — see the
 * shell's IdleLock surface — so they are settings, not config edits. The sizes
 * and the bead timeline used to be constants in `modules/lock/`.
 *
 * The failed-attempts group is read by the lock's own auth daemon
 * (`modules/lock/Auth.qml`): the timed lockout it has always had is tuned by the
 * three `lockout*` rows, and on top of it the streak escalates to ending the
 * session — logging the user out by default, so a keyboard left in front of a
 * locked screen does not simply keep guessing.
 */
QtObject {
    readonly property string name: "Lock Screen"
    readonly property string icon: "\u25A1"
    readonly property string keywords: "lock idle dim dpms suspend timeout password avatar backdrop blur darken saturation vignette grain bead animation screen privacy private hide redact media music ssid wifi network name failed failure attempt attempts tries escalate escalation logout log out sign out shutdown shut down poweroff power off reboot restart lockout player glow visualizer cava content card clock battery network glance"

    readonly property var groups: [
        { card: "Idle", rows: [
            { key: "idleLockMin", type: "slider", label: "Auto-lock", min: 0, max: 15, step: 1, unit: "min",
              caption: "Lock after idle. 0 disables.", reset: 3 },
            { key: "idleScreenOffMin", type: "slider", label: "Screen off", min: 0, max: 15, step: 1, unit: "min",
              caption: "Blank screen after idle. 0 disables.", reset: 0 },
            { key: "idleSuspendMin", type: "slider", label: "Suspend", min: 0, max: 60, step: 1, unit: "min",
              caption: "Suspend system after idle. 0 disables.", reset: 0 }
        ]},
        { card: "Privacy", rows: [
            { key: "lockPrivacy", type: "toggle", label: "Hide private info",
              caption: "Redact now-playing, wifi, and name on lock.", reset: false }
        ]},
        { card: "Content", rows: [
            { key: "lockClock", type: "toggle", label: "Clock",
              caption: "Show time/date on lock.", reset: true },
            { key: "lockMedia", type: "toggle", label: "Now-playing card",
              caption: "Show media when playing.", reset: true },
            { key: "lockViz", type: "toggle", label: "Music glow",
              caption: "Audio-reactive glow effect.", reset: true },
            { key: "lockBattery", type: "toggle", label: "Battery glance",
              caption: "Battery indicator in top-right.", reset: true },
            { key: "lockLink", type: "toggle", label: "Network glance",
              caption: "Wifi/bluetooth in bottom-right.", reset: true }
        ]},
        { card: "Failed attempts", rows: [
            { key: "lockFailAction", type: "segmented", label: "After too many tries",
              caption: "Action to take after reaching streak limit.",
              options: ["none", "logout", "reboot", "shutdown"],
              names: ["Nothing", "Log out", "Restart", "Shut down"], reset: "logout" },
            { key: "lockFailLimit", type: "slider", label: "Allowed failures",
              min: 1, max: 20, step: 1, unit: "",
              caption: "Consecutive password failures allowed.", reset: 10 },
            { key: "lockoutThreshold", type: "slider", label: "Lockout after",
              min: 1, max: 20, step: 1, unit: "",
              caption: "Failures before temporary field lockout.", reset: 5 },
            { key: "lockoutSeconds", type: "slider", label: "First lockout wait",
              min: 5, max: 300, step: 5, unit: "s",
              caption: "Duration of first lockout. Doubles per repeat.", reset: 30 },
            { key: "lockoutMax", type: "slider", label: "Longest lockout wait",
              min: 30, max: 1800, step: 30, unit: "s",
              caption: "Maximum lockout duration.", reset: 600 }
        ]},
        { card: "Surface", rows: [
            { key: "lockPillW", type: "slider", label: "Field width",
              min: 120, max: 320, step: 4, unit: "px",
              caption: "Password field width.", reset: 176 },
            { key: "lockPillH", type: "slider", label: "Field height",
              min: 28, max: 80, step: 2, unit: "px", reset: 42 },
            { key: "lockAvatarSize", type: "slider", label: "Avatar",
              min: 60, max: 220, step: 4, unit: "px",
              caption: "Size of user picture.", reset: 120 }
        ]},
        { card: "Backdrop", rows: [
            { key: "lockBlurSpread", type: "slider", label: "Blur spread",
              min: 0, max: 6, step: 0.2, unit: "",
              caption: "Blur intensity.", reset: 2.4 },
            { key: "lockBlurDarken", type: "slider", label: "Darken",
              min: 0, max: 1, step: 0.02, unit: "%", displayScale: 100,
              caption: "Backdrop dimming.", reset: 0.62 },
            { key: "lockBlurSaturation", type: "slider", label: "Saturation",
              min: 0, max: 2, step: 0.05, unit: "%", displayScale: 100,
              caption: "Backdrop color vibrancy.", reset: 1.0 },
            { key: "lockBlurVignette", type: "slider", label: "Vignette",
              min: 0, max: 1, step: 0.02, unit: "%", displayScale: 100,
              caption: "Edge darkening.", reset: 0.14 },
            { key: "lockBlurGrain", type: "slider", label: "Grain",
              min: 0, max: 0.05, step: 0.002, unit: "", displayScale: 1000,
              caption: "Add film grain.", reset: 0.012 }
        ]},
        { card: "Password", rows: [
            { key: "lockDotsMode", type: "segmented", label: "Dots animation",
              caption: "Animation for password bead entrance.",
              options: ["drop", "pulse", "gpixel"], names: ["Drop", "Pulse", "GPixel"], reset: "gpixel" },
            { key: "lockBeadMs", type: "slider", label: "Bead timeline",
              min: 100, max: 900, step: 25, unit: "ms",
              caption: "Bead entrance/exit duration.", reset: 350 }
        ]}
    ]
}

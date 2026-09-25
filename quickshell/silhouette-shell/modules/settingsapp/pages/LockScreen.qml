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
        { card: "Content", rows: [
            { key: "lockClock", type: "toggle", label: "Clock",
              caption: "The big time and date on the lock; clicking them still expands the full date layout", reset: true },
            { key: "lockMedia", type: "toggle", label: "Now-playing card",
              caption: "Show the media card on the lock while a player is active; Hide private info still redacts its details", reset: true },
            { key: "lockViz", type: "toggle", label: "Music glow",
              caption: "Glow that reacts to the audio, with its own capture independent of the pill's visualizer", reset: true },
            { key: "lockBattery", type: "toggle", label: "Battery glance",
              caption: "The battery capsule in the lock's top-right corner", reset: true },
            { key: "lockLink", type: "toggle", label: "Network glance",
              caption: "The wifi and bluetooth capsule in the lock's bottom-right corner", reset: true }
        ]},
        { card: "Failed attempts", rows: [
            { key: "lockFailAction", type: "segmented", label: "After too many tries",
              caption: "What the lock does once the wrong-password streak below is reached. Nothing keeps just the timed lockout",
              options: ["none", "logout", "reboot", "shutdown"],
              names: ["Nothing", "Log out", "Restart", "Shut down"], reset: "logout" },
            { key: "lockFailLimit", type: "slider", label: "Allowed failures",
              min: 1, max: 20, step: 1, unit: "",
              caption: "Consecutive wrong passwords before that action runs; a successful unlock resets the streak", reset: 10 },
            // The timed lockout under the escalation: after this many failures the
            // field locks for the first wait below, doubling per repeat. It applies
            // whether or not the escalation above is armed.
            { key: "lockoutThreshold", type: "slider", label: "Lockout after",
              min: 1, max: 20, step: 1, unit: "",
              caption: "Consecutive failures before the field is locked out", reset: 5 },
            { key: "lockoutSeconds", type: "slider", label: "First lockout wait",
              min: 5, max: 300, step: 5, unit: "s",
              caption: "How long the first lockout lasts; each repeat doubles it", reset: 30 },
            { key: "lockoutMax", type: "slider", label: "Longest lockout wait",
              min: 30, max: 1800, step: 30, unit: "s",
              caption: "Ceiling on the doubling wait", reset: 600 }
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
              caption: "How far the wallpaper blur reaches behind the lock", reset: 2.4 },
            { key: "lockBlurDarken", type: "slider", label: "Darken",
              min: 0, max: 1, step: 0.02, unit: "%", displayScale: 100,
              caption: "How much the backdrop is darkened (100 % leaves it as it is)", reset: 0.62 },
            { key: "lockBlurSaturation", type: "slider", label: "Saturation",
              min: 0, max: 2, step: 0.05, unit: "%", displayScale: 100,
              caption: "Colour in the backdrop (0 % is greyscale, 100 % is untouched)", reset: 1.0 },
            { key: "lockBlurVignette", type: "slider", label: "Vignette",
              min: 0, max: 1, step: 0.02, unit: "%", displayScale: 100,
              caption: "Darkness that gathers at the backdrop's edges", reset: 0.14 },
            { key: "lockBlurGrain", type: "slider", label: "Grain",
              min: 0, max: 0.05, step: 0.002, unit: "", displayScale: 1000,
              caption: "Film grain mixed into the backdrop (0 = clean)", reset: 0.012 }
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

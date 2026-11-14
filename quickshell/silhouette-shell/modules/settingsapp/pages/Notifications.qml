pragma Singleton

import QtQuick

/**
 * Notifications: the session-wide silencer, and how far it reaches.
 */
QtObject {
    readonly property string name: "Notifications"
    readonly property string icon: "\u25C8"
    readonly property string keywords: "do not disturb dnd silence silent mute popup notification alert critical urgent duplicate collapse repeat sound blip"

    readonly property var groups: [
        { card: "Notifications", rows: [
            { key: "dnd", type: "toggle", label: "Do not disturb", caption: "Notifications stay silent", reset: false },
            { key: "dndCritical", type: "toggle", label: "Critical notifications",
              caption: "Let a critical-urgency notification pop even while do not disturb is on", reset: true },
            { key: "notifSecs", type: "segmented", label: "Show for",
              caption: "How long a new notification card stays in the pill",
              options: [3, 4, 6, 8, 12], names: ["3 s", "4 s", "6 s", "8 s", "12 s"], reset: 4 },
            { key: "notifDedupe", type: "toggle", label: "Collapse repeats",
              caption: "A repeat of a notification already on screen bumps its count instead of stacking a second popup", reset: true },
            { key: "notifSound", type: "toggle", label: "Notification sound",
              caption: "Play a blip for each notification shown", reset: false }
        ]},
        { card: "Pill Flashes", rows: [
            { key: "osdTime", type: "segmented", label: "How long they stay",
              caption: "Scales every flash duration, the song card included",
              options: [0.5, 0.75, 1.0, 1.5, 2.0], names: ["0.5×", "0.75×", "1×", "1.5×", "2×"], reset: 1.0 }
        ]}
    ]
}

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
            { key: "notifDedupe", type: "toggle", label: "Collapse repeats",
              caption: "A repeat of a notification already on screen bumps its count instead of stacking a second popup", reset: true },
            { key: "notifSound", type: "toggle", label: "Notification sound",
              caption: "Play a blip for each notification shown", reset: false }
        ]}
    ]
}

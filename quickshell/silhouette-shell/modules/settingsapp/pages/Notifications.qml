pragma Singleton

import QtQuick

/**
 * Notifications: the session-wide silencer.
 */
QtObject {
    readonly property string name: "Notifications"
    readonly property string icon: "\u25C8"
    readonly property string keywords: "do not disturb dnd silence silent mute popup notification alert"

    readonly property var groups: [
        { card: "Notifications", rows: [
            { key: "dnd", type: "toggle", label: "Do not disturb", caption: "Notifications stay silent", reset: false }
        ]}
    ]
}

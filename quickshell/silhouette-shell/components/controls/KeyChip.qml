pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Compact key/command chip — the rounded frameBg tag holding a shortcut combo
 * or workspace key. `focused` lights a verm tint and cream text for the row
 * under the keyboard cursor (keybind rows); plain rows leave it off.
 */
Rectangle {
    id: chip

    property real s: 1.1
    property string text: ""
    property bool focused: false

    width: label.implicitWidth + 16 * chip.s
    height: label.implicitHeight + 8 * chip.s
    radius: 7 * chip.s
    color: chip.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.frameBg
    border.width: 1
    border.color: chip.focused ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.focused ? Theme.cream : Theme.subtle
        font.family: Theme.font
        font.pixelSize: 11 * chip.s
        font.weight: Font.Bold
        font.letterSpacing: 0.3 * chip.s
    }
}

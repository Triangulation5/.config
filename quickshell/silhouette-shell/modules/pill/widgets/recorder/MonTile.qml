pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One monitor tile in the screen recorder's display picker: shows the output
 * name and resolution. Clicking selects it via pickMonitor.
 */
Rectangle {
    id: monTile

    property var surface: null
    required property var modelData
    required property int index

    readonly property real s: surface ? surface.s : 1
    readonly property bool focused: surface ? surface.monFocus === monTile.index : false

    width: 152 * s
    height: parent ? parent.height : 0
    radius: 9 * s
    color: monArea.containsMouse || monTile.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
    border.width: 1
    border.color: monArea.containsMouse || monTile.focused ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    HoverHandler {
        onHoveredChanged: if (hovered && surface) surface.monFocus = monTile.index
    }

    Column {
        anchors.centerIn: parent
        spacing: 2 * s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: monTile.modelData.name
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * s
            font.weight: Font.Bold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: monTile.modelData.w + " × " + monTile.modelData.h
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * s
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: monArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (surface) surface.pickMonitor(monTile.modelData.name)
    }
}

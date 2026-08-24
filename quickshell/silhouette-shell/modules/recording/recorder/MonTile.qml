pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One monitor tile in the screen recorder's display picker. All data
 * (s, name, w, h, index) is passed from the delegate body where both
 * root and the ListView model data are directly accessible.
 */
Rectangle {
    id: monTile

    property var surface: null
    property real s: 1
    property string monName: ""
    property int monW: 0
    property int monH: 0
    property int rowIndex: -1

    readonly property bool focused: surface ? surface.monFocus === monTile.rowIndex : false

    width: 152 * s
    height: parent ? parent.height : 0
    radius: 9 * s
    color: monArea.containsMouse || monTile.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
    border.width: 1
    border.color: monArea.containsMouse || monTile.focused ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    HoverHandler {
        onHoveredChanged: if (hovered && surface) surface.monFocus = monTile.rowIndex
    }

    Column {
        anchors.centerIn: parent
        spacing: 2 * s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: monTile.monName
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * s
            font.weight: Font.Bold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: monTile.monW + " × " + monTile.monH
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
        onClicked: if (surface) surface.pickMonitor(monTile.monName)
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * One workspace navigation row in the workspaces hub. All data is passed
 * from the delegate body.
 */
Item {
    id: wrow

    property var surface: null
    property real s: 1
    property string wsName: ""
    property string wsNote: ""
    property string wsKey: ""
    property string wsNavSurface: ""

    readonly property bool nav: wrow.wsNavSurface.length > 0
    readonly property bool focused: wrow.nav && surface ? surface.focusIndex === 0 : false

    width: parent ? parent.width : 0
    height: 50 * s

    HoverTile {
        anchors.fill: parent
        anchors.topMargin: 3 * s
        anchors.bottomMargin: 3 * s
        radius: 10 * s
        hovered: navHover.hovered
        focused: wrow.focused
        edge: Theme.frameBorder
    }

    HoverHandler { id: navHover; enabled: wrow.nav }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 12 * s
        anchors.right: rightRow.left
        anchors.rightMargin: 10 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * s

        Text {
            width: parent.width
            text: wrow.wsName
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: wrow.wsNote
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * s
            elide: Text.ElideRight
        }
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 12 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * s

        KeyChip {
            anchors.verticalCenter: parent.verticalCenter
            s: s
            text: wrow.wsKey
        }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: wrow.nav
            width: 16 * s
            height: 16 * s
            name: "chevron-right"
            color: navHover.hovered ? Theme.cream : Theme.iconDim
            stroke: 2.2
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: wrow.nav
        cursorShape: Qt.PointingHandCursor
        onClicked: if (surface) surface.requestSurface(wrow.wsNavSurface)
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hairSoft
    }
}

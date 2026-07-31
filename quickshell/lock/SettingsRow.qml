pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Reusable setting row: icon, name, optional subtitle, and control slot on the right.
 */
Item {
    id: srow

    property var surface: null
    property real s: 1.1
    property string icon: ""
    property string name: ""
    property string sub: ""
    property bool last: false
    signal clicked()
    default property alias control: controlSlot.data

    width: parent ? parent.width : 0
    height: Math.max(textCol.implicitHeight, controlSlot.childrenRect.height) + 16 * srow.s

    HoverHandler {
        id: srowHover
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2 * srow.s
        anchors.bottomMargin: 2 * srow.s
        radius: 8 * srow.s
        color: srowHover.hovered ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    GlyphIcon {
        id: ri
        anchors.left: parent.left
        anchors.leftMargin: 10 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        visible: srow.icon.length > 0
        width: 16 * srow.s
        height: 16 * srow.s
        name: srow.icon
        color: srowHover.hovered ? Theme.cream : Theme.dim
        stroke: 1.8

        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Column {
        id: textCol
        anchors.left: ri.visible ? ri.right : parent.left
        anchors.leftMargin: ri.visible ? 10 * srow.s : 10 * srow.s
        anchors.right: controlSlot.left
        anchors.rightMargin: 10 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * srow.s

        Text {
            text: srow.name
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * srow.s
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: srow.sub.length > 0
            text: srow.sub
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * srow.s
            wrapMode: Text.WordWrap
            lineHeight: 1.1
        }
    }

    Item {
        id: controlSlot
        anchors.right: parent.right
        anchors.rightMargin: 10 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            srow.clicked();
            if (srow.surface) srow.surface.activateRow(srow);
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10 * srow.s
        anchors.rightMargin: 10 * srow.s
        height: 1
        color: Theme.hairSoft
        visible: !srow.last
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Item {
    id: row

    property var surface: null

    property string icon: ""
    property string name: ""
    property string sub: ""

    property bool last: false

    readonly property real s: surface ? surface.s : 1
    readonly property bool focused:
        surface ? surface.focusRowItem === row : false

    default property alias control: controlSlot.data

    width: parent ? parent.width : 0
    height: Math.max(
        textColumn.implicitHeight,
        controlSlot.childrenRect.height
    ) + 18 * s


    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (row.surface)
                row.surface.reportRowHover(row, hovered)
        }
    }


    Rectangle {
        anchors.fill: parent

        anchors.topMargin: 2 * s
        anchors.bottomMargin: 2 * s

        radius: 9 * s

        color: (hover.hovered || row.focused)
            ? Theme.frameBg
            : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }


    MouseArea {
        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (row.surface)
                row.surface.activateRow(row)
        }
    }


    GlyphIcon {
        anchors.left: parent.left
        anchors.leftMargin: 12 * s

        anchors.verticalCenter: parent.verticalCenter

        width: 17 * s
        height: 17 * s

        visible: row.icon.length > 0

        name: row.icon

        color: row.focused
            ? Theme.cream
            : Theme.subtle

        stroke: 1.8
    }


    Column {
        id: textColumn

        anchors.left: parent.left
        anchors.leftMargin: 40 * s

        anchors.right: controlSlot.left
        anchors.rightMargin: 10 * s

        anchors.verticalCenter: parent.verticalCenter

        spacing: 3 * s


        Text {
            text: row.name

            color: Theme.cream

            font.family: Theme.font
            font.pixelSize: 12 * s
            font.weight: Font.DemiBold

            elide: Text.ElideRight
        }


        Text {
            visible: row.sub.length > 0

            text: row.sub

            color: Theme.faint

            font.family: Theme.font
            font.pixelSize: 10 * s

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }


    Item {
        id: controlSlot

        anchors.right: parent.right
        anchors.rightMargin: 12 * s

        anchors.verticalCenter: parent.verticalCenter

        width: childrenRect.width
        height: childrenRect.height
    }


    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: 1

        color: Theme.hairSoft

        visible: !row.last
    }
}

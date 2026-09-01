pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * One workspace rule row in the workspaces hub. All data is passed
 * from the delegate body.
 */
Item {
    id: crow

    property var surface: null
    property real s: 1
    property int rowIndex: -1
    property string wsName: ""
    property string wsDesc: ""
    property string wsKey: ""
    property string wsId: ""

    readonly property bool last: crow.rowIndex === Spaces.list.length - 1
    readonly property bool focused: surface ? surface.focusIndex === 1 + crow.rowIndex : false

    width: parent ? parent.width : 0
    height: 50 * s

    HoverTile {
        anchors.fill: parent
        anchors.topMargin: 3 * s
        anchors.bottomMargin: 3 * s
        radius: 10 * s
        hovered: cHover.hovered
        focused: crow.focused
        edge: Theme.frameBorder
    }

    HoverHandler { id: cHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Spaces.editing = crow.wsId;
            if (surface) surface.requestSurface("spaceapps");
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 12 * s
        anchors.right: cRightRow.left
        anchors.rightMargin: 10 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * s

        Text {
            width: parent.width
            text: crow.wsName
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: crow.wsDesc.length > 0
            text: crow.wsDesc
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * s
            elide: Text.ElideRight
        }
    }

    Row {
        id: cRightRow
        anchors.right: parent.right
        anchors.rightMargin: 12 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * s

        Rectangle {
            id: cRemove
            anchors.verticalCenter: parent.verticalCenter
            width: 24 * s
            height: 24 * s
            radius: 7 * s
            opacity: cHover.hovered ? 1 : 0
            color: cRemoveArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            GlyphIcon {
                anchors.centerIn: parent
                width: 12 * s
                height: 12 * s
                name: "close"
                color: cRemoveArea.containsMouse ? Theme.vermLit : Theme.iconDim
                stroke: 2
            }

            MouseArea {
                id: cRemoveArea
                anchors.fill: parent
                enabled: cHover.hovered
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Spaces.removeSpace(crow.wsId)
            }
        }

        KeyChip {
            anchors.verticalCenter: parent.verticalCenter
            s: s
            text: crow.wsKey
        }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * s
            height: 16 * s
            name: "chevron-right"
            color: cHover.hovered ? Theme.cream : Theme.iconDim
            stroke: 2.2
        }
    }
}

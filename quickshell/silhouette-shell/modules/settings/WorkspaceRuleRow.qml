pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * One workspace rule row: space name, description, keybinding chip, and a
 * remove button (visible on hover). Clicking opens the space-apps editor.
 * Extracted from WorkspacesSurface.qml's second Repeater delegate.
 */
Item {
    id: crow

    property var surface: null
    required property var modelData
    required property int index

    readonly property bool last: crow.index === Spaces.list.length - 1
    readonly property bool focused: surface ? surface.focusIndex === 1 + crow.index : false
    readonly property real s: surface ? surface.s : 1

    width: parent ? parent.width : 0
    height: 50 * s

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3 * s
        anchors.bottomMargin: 3 * s
        radius: 10 * s
        color: cHover.hovered || crow.focused ? Theme.frameBg : "transparent"
        border.width: 1
        border.color: cHover.hovered || crow.focused ? Theme.frameBorder : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    HoverHandler { id: cHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Spaces.editing = crow.modelData.id;
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
            text: crow.modelData.name
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: crow.modelData.desc.length > 0
            text: crow.modelData.desc
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
                onClicked: Spaces.removeSpace(crow.modelData.id)
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: cKeyText.implicitWidth + 16 * s
            height: cKeyText.implicitHeight + 8 * s
            radius: 7 * s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.hairSoft

            Text {
                id: cKeyText
                anchors.centerIn: parent
                text: crow.modelData.key
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * s
                font.weight: Font.Bold
                font.letterSpacing: 0.3 * s
            }
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

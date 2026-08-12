pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One keybind row: a rounded combo-chip on the left with the chord, the bind
 * label on the right, and the raw command revealed on hover. The host binds
 * `surface` to the Keybinds surface for scale and focus state.
 */
Item {
    id: brow

    /** Reference to the Keybinds surface. */
    property var surface: null
    /** Per-row data from the filtered binds list. */
    required property var modelData
    required property int index

    readonly property bool focused: surface ? surface.focusIndex === brow.index : false
    readonly property real s: surface ? surface.s : 1

    width: ListView.view ? ListView.view.width : 0
    height: 38 * s

    onFocusedChanged: {
        if (focused && surface && surface.bindList) surface.bindList.focusRowItem = brow;
    }

    HoverHandler {
        id: rowHover
        onHoveredChanged: if (hovered && surface && !surface.listening) surface.focusIndex = brow.index
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3 * s
        anchors.bottomMargin: 3 * s
        radius: 9 * s
        color: (rowHover.hovered || brow.focused) ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        id: comboChip
        anchors.left: parent.left
        anchors.leftMargin: 12 * s
        anchors.verticalCenter: parent.verticalCenter
        width: comboText.implicitWidth + 16 * s
        height: comboText.implicitHeight + 8 * s
        radius: 7 * s
        color: brow.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.frameBg
        border.width: 1
        border.color: brow.focused ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Text {
            id: comboText
            anchors.centerIn: parent
            text: surface ? surface.comboPretty(brow.modelData.combo) : brow.modelData.combo
            color: brow.focused ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 11 * s
            font.weight: Font.Bold
            font.letterSpacing: 0.3 * s
        }
    }

    Column {
        anchors.left: comboChip.right
        anchors.leftMargin: 12 * s
        anchors.right: parent.right
        anchors.rightMargin: 14 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1 * s

        Text {
            anchors.right: parent.right
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: brow.modelData.label
            color: brow.focused ? Theme.subtle : Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            anchors.right: parent.right
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: rowHover.hovered && brow.modelData.cmd.length > 0
            text: brow.modelData.cmd
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * s
            font.weight: Font.Normal
            elide: Text.ElideLeft
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: surface ? !surface.listening : true
        cursorShape: brow.modelData.isMouse ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: {
            if (surface) {
                surface.focusIndex = brow.index;
                surface.openEdit(brow.modelData);
            }
        }
    }
}

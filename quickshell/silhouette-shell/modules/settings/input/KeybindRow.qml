pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One keybind row in the keybinds list. All data is passed from the delegate
 * body where the Keybinds surface and the model data are both accessible.
 */
Item {
    id: brow

    property var surface: null
    property real s: 1
    property int rowIndex: -1
    property string kbCombo: ""
    property string kbLabel: ""
    property string kbCmd: ""
    property bool kbIsMouse: false

    readonly property bool focused: surface ? surface.focusIndex === brow.rowIndex : false

    width: ListView.view ? ListView.view.width : 0
    height: 38 * s

    onFocusedChanged: {
        if (focused && surface && surface.bindList) surface.bindList.focusRowItem = brow;
    }

    HoverHandler {
        id: rowHover
        onHoveredChanged: if (hovered && surface && !surface.listening) surface.focusIndex = brow.rowIndex
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
            text: surface ? surface.comboPretty(brow.kbCombo) : brow.kbCombo
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
            text: brow.kbLabel
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
            visible: rowHover.hovered && brow.kbCmd.length > 0
            text: brow.kbCmd
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
        cursorShape: brow.kbIsMouse ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: {
            if (surface) {
                surface.focusIndex = brow.rowIndex;
                surface.openEdit(brow.kbModel());
            }
        }
    }

    /** Reconstruct a model-like object for openEdit. */
    function kbModel() {
        return { combo: brow.kbCombo, label: brow.kbLabel, cmd: brow.kbCmd, isMouse: brow.kbIsMouse };
    }
}

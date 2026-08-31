pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * A wide settings line for card-style tabs (Display): a leading glyph or icon
 * beside a default content slot, with the same hover/keyboard soul-seam wiring
 * as SettingsRow and FieldRow. `surface` points at the owning settings surface;
 * scale derives from it.
 */
Item {
    id: crow

    property var surface: null
    property string icon: ""
    property string glyphText: ""
    default property alias content: crowInner.data

    readonly property bool focused: crow.surface ? crow.surface.focusRowItem === crow : false
    readonly property real s: crow.surface ? crow.surface.s : 1

    width: parent ? parent.width : 0
    implicitHeight: crowInner.childrenRect.height

    HoverHandler {
        id: crowHover
        onHoveredChanged: if (crow.surface) crow.surface.reportRowHover(crow, hovered)
    }

    HoverTile {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: -3 * crow.s
        anchors.leftMargin: -7 * crow.s
        anchors.rightMargin: -7 * crow.s
        height: 32 * crow.s
        radius: 8 * crow.s
        focused: crow.focused
        hovered: crowHover.hovered
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (crow.surface) crow.surface.activateRow(crow)
    }

    GlyphIcon {
        id: crowIcon
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: 5 * crow.s
        width: 16 * crow.s
        height: 16 * crow.s
        name: crow.icon
        visible: crow.icon.length > 0
        color: crow.focused ? Theme.cream : Theme.subtle
        stroke: 1.8
    }

    Text {
        anchors.centerIn: crowIcon
        visible: crow.glyphText.length > 0
        text: crow.glyphText
        color: crow.focused ? Theme.cream : Theme.subtle
        font.family: Theme.fontJp
        font.pixelSize: 13 * crow.s
    }

    Item {
        id: crowInner
        anchors.left: crowIcon.right
        anchors.leftMargin: 9 * crow.s
        anchors.right: parent.right
        anchors.top: parent.top
        height: childrenRect.height
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * Header device picker chip: an icon-only button that toggles its dropdown.
 * It reads as an open field (onGlow tint and border) while its list is showing,
 * the same affordance the display surface uses, so no chevron is needed.
 */
Rectangle {
    id: dchip

    property real s: 1.1
    property string glyph: ""
    property bool open: false
    property string tip: ""
    signal toggled()

    width: 26 * s
    height: 26 * s
    radius: 8 * s
    color: dchip.open ? Qt.alpha(Theme.onGlow, 0.14)
        : (dchipHover.hovered ? Theme.frameBg : "transparent")
    border.width: 1
    border.color: dchip.open ? Qt.alpha(Theme.onGlow, 0.5) : Theme.border
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    GlyphIcon {
        anchors.centerIn: parent
        width: 15 * s
        height: 15 * s
        name: dchip.glyph
        color: dchip.open ? Theme.vermLit : Theme.iconDim
        stroke: 1.7
    }

    HoverHandler { id: dchipHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dchip.toggled()
    }

    Tooltip {
        s: dchip.s
        placement: "below"
        title: dchip.tip
        show: dchipHover.hovered && !dchip.open
    }
}

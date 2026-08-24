pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * Small square icon chip for the mixer header: a glyph button with an on/off
 * state and a tooltip that appears on hover. `accent` switches the lit state
 * from the plain framed fill to the flame tint the device pickers use, so one
 * chip covers every header button (previously IconChip + DevicePickerChip).
 */
Rectangle {
    id: chip

    property real s: 1.1
    property string glyph: ""
    property bool on: false
    /** Lit-state styling: false = framed fill (toggle chips), true = flame tint (device pickers). */
    property bool accent: false
    property string tipTitle: ""
    property string tipDesc: ""
    /** Hide the tooltip while the chip is in its on state (device pickers do this). */
    property bool tipWhileOn: false
    signal toggled()

    width: 26 * s
    height: 26 * s
    radius: 8 * s
    color: chip.on
        ? (chip.accent ? Qt.alpha(Theme.onGlow, 0.14) : Theme.frameBg)
        : (chip.accent && chipHover.hovered ? Theme.frameBg : "transparent")
    border.width: 1
    border.color: chip.on
        ? (chip.accent ? Qt.alpha(Theme.onGlow, 0.5) : Theme.frameBorder)
        : Theme.border
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    GlyphIcon {
        anchors.centerIn: parent
        width: 15 * s
        height: 15 * s
        name: chip.glyph
        color: chip.on ? Theme.vermLit : Theme.iconDim
        stroke: 1.7
    }

    HoverHandler { id: chipHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.toggled()
    }

    Tooltip {
        s: chip.s
        placement: "below"
        title: chip.tipTitle
        desc: chip.tipDesc
        show: chipHover.hovered && (!chip.tipWhileOn || !chip.on)
    }
}

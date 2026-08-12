pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Brightness OSD face: sun glyph, percentage and a live fill bar that follows
 * the backlight level. Driven by the Osd root through `active` and
 * `brightness`.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false
    property real brightness: 0

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    GlyphIcon {
        id: brightGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * face.s
        height: 17 * face.s
        name: "sun"
        color: Theme.iconDim
        stroke: 1.7
    }

    Text {
        id: brightPct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32 * face.s
        horizontalAlignment: Text.AlignRight
        text: Math.round(face.brightness * 100) + "%"
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    Rectangle {
        anchors.left: brightGlyph.right
        anchors.leftMargin: 12 * face.s
        anchors.right: brightPct.left
        anchors.rightMargin: 12 * face.s
        anchors.verticalCenter: parent.verticalCenter
        height: 4 * face.s
        radius: 2 * face.s
        color: Theme.threadBg

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.brightness
            radius: parent.radius
            color: Theme.vermLit
            Behavior on width { NumberAnimation { duration: Motion.fast } }
        }
    }
}

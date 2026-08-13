pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Brightness OSD face: a level sun glyph (rays lengthen with the backlight),
 * percentage and a flame-gradient fill bar that follows the backlight level,
 * matching the battery face's filament language. Driven by the Osd root
 * through `active` and `brightness`.
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
        name: "sun-level"
        progress: face.brightness
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
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.vermDeep }
                GradientStop { position: 1.0; color: Theme.flameGlow }
            }
            Behavior on width { NumberAnimation { duration: Motion.fast } }
        }
    }
}

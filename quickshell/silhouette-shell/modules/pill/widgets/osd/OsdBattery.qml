pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Battery OSD face: bolt glyph, percentage and a flame-gradient fill bar with
 * a charging shimmer. Driven by the Osd root through `active`, `charging`,
 * `pct` and `frac` so the face stays free of service imports.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false
    property bool charging: false
    property int pct: 0
    property real frac: 0

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    GlyphIcon {
        id: battGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * face.s
        height: 17 * face.s
        name: "bolt"
        color: Theme.flameGlow
        stroke: 1.7
    }

    Text {
        id: battPct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 40 * face.s
        horizontalAlignment: Text.AlignRight
        text: face.pct + "%"
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    Rectangle {
        anchors.left: battGlyph.right
        anchors.leftMargin: 12 * face.s
        anchors.right: battPct.left
        anchors.rightMargin: 12 * face.s
        anchors.verticalCenter: parent.verticalCenter
        height: 4 * face.s
        radius: 2 * face.s
        color: Theme.threadBg
        clip: true

        Rectangle {
            id: battFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.frac
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.vermDeep }
                GradientStop { position: 1.0; color: Theme.flameGlow }
            }
            Behavior on width { NumberAnimation { duration: Motion.fast } }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 34 * face.s
                color: "transparent"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#55ffe6d6" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }

                NumberAnimation on x {
                    from: -34 * face.s
                    to: battFill.width
                    duration: 1200
                    loops: Animation.Infinite
                    running: face.active && face.charging
                }
            }
        }
    }
}

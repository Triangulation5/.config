pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Level OSD face: a glyph at the left, a percentage at the right and a fill
 * bar between them that tracks `fill`. Shared by the volume, brightness and
 * battery faces, which only differ in glyph, percentage and fill styling:
 * `fillGradient` wins over `fillColor`, and `shimmerOn` runs the charging
 * sweep the battery face uses. Driven by the Osd root through `active`.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false

    property string glyph: ""
    property color glyphColor: Theme.iconDim
    property real glyphProgress: 1

    property string pctText: ""
    property color pctColor: Theme.cream
    property real pctWidth: 32 * face.s

    property real fill: 0
    property color fillColor: Theme.vermLit
    property Gradient fillGradient: null

    property bool shimmerOn: false

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    GlyphIcon {
        id: levelGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * face.s
        height: 17 * face.s
        name: face.glyph
        progress: face.glyphProgress
        color: face.glyphColor
        stroke: 1.7
    }

    Text {
        id: pctLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: face.pctWidth
        horizontalAlignment: Text.AlignRight
        text: face.pctText
        color: face.pctColor
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    Rectangle {
        anchors.left: levelGlyph.right
        anchors.leftMargin: 12 * face.s
        anchors.right: pctLabel.left
        anchors.rightMargin: 12 * face.s
        anchors.verticalCenter: parent.verticalCenter
        height: 4 * face.s
        radius: 2 * face.s
        color: Theme.threadBg
        clip: true

        Rectangle {
            id: levelFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.fill
            radius: parent.radius
            gradient: face.fillGradient
            color: face.fillGradient ? "transparent" : face.fillColor
            Behavior on width { NumberAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 34 * face.s
                visible: face.shimmerOn
                color: "transparent"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#55ffe6d6" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
                NumberAnimation on x {
                    from: -34 * face.s
                    to: levelFill.width
                    duration: 1200
                    loops: Animation.Infinite
                    running: face.active && face.shimmerOn
                }
            }
        }
    }
}

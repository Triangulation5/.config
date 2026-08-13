pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Volume OSD face: a level speaker glyph (waves sweep open with the volume),
 * percentage and a live fill bar that follows the sink volume. Driven by the
 * Osd root through `active`, `muted` and `volume`.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false
    property bool muted: false
    property real volume: 0

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    GlyphIcon {
        id: volGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * face.s
        height: 17 * face.s
        name: face.muted ? "speaker-off" : "speaker-level"
        progress: face.volume
        color: face.muted ? Theme.dim : Theme.iconDim
        stroke: 1.7
    }

    Text {
        id: volPct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32 * face.s
        horizontalAlignment: Text.AlignRight
        text: Math.round(face.volume * 100) + "%"
        color: face.muted ? Theme.dim : Theme.cream
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    Rectangle {
        anchors.left: volGlyph.right
        anchors.leftMargin: 12 * face.s
        anchors.right: volPct.left
        anchors.rightMargin: 12 * face.s
        anchors.verticalCenter: parent.verticalCenter
        height: 4 * face.s
        radius: 2 * face.s
        color: Theme.threadBg

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.volume
            radius: parent.radius
            color: face.muted ? Theme.vermDim : Theme.vermLit
            Behavior on width { NumberAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }
}

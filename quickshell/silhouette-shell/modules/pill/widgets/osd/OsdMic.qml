pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Microphone OSD face: mic glyph and a one-line on/off state, tinted vermilion
 * while muted. Driven by the Osd root through `active` and `micMuted`.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false
    property bool micMuted: false

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    GlyphIcon {
        id: micGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * face.s
        height: 17 * face.s
        name: face.micMuted ? "mic-off" : "mic"
        color: face.micMuted ? Theme.verm : Theme.vermLit
        stroke: 1.7
    }

    Text {
        anchors.left: micGlyph.right
        anchors.leftMargin: 12 * face.s
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Microphone " + (face.micMuted ? "off" : "on")
        color: face.micMuted ? Theme.verm : Theme.cream
        font.family: Theme.font
        font.pixelSize: 11.5 * face.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
}

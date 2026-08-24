pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.modules.pill.widgets.osd

/**
 * Microphone OSD face: mic glyph and a one-line on/off state, tinted vermilion
 * while muted. Driven by the Osd root through `active` and `micMuted`.
 */
OsdFace {
    id: face

    property bool micMuted: false

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

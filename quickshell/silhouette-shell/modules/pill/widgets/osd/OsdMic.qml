pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
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

    Rectangle {
        id: micContainer
        anchors.left: parent.left
        anchors.leftMargin: 4 * face.s
        anchors.verticalCenter: parent.verticalCenter
        width: 38 * face.s
        height: width
        radius: 14 * face.s
        color: face.micMuted ? Qt.alpha(Theme.error, 0.16) : Theme.primaryContainer

        MouseArea {
            anchors.fill: parent
            enabled: !!(Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio)
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                const source = Pipewire.defaultAudioSource;
                if (source && source.audio)
                    source.audio.muted = !source.audio.muted;
            }
        }
    }

    GlyphIcon {
        id: micGlyph
        anchors.centerIn: micContainer
        width: 17 * face.s
        height: 17 * face.s
        name: face.micMuted ? "mic-off" : "mic"
        color: face.micMuted ? Theme.error : Theme.primary
        stroke: 1.7
    }

    Text {
        anchors.left: micContainer.right
        anchors.leftMargin: 12 * face.s
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: face.micMuted ? "Microphone muted" : "Microphone on"
        color: face.micMuted ? Theme.error : Theme.onSurface
        font.family: Theme.font
        font.pixelSize: 11.5 * face.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
}

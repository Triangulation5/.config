pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.recording

/**
 * The Recorder's two audio faders (Microphone + Desktop): each row drives the
 * default Pipewire source/sink level (matching what gsr captures via its
 * default_input / default_output aliases) and toggles the ScreenRec capture
 * flag when its glyph/label is clicked. `faderFocus` and `stepFocused` are
 * routed from the host exactly like the mixer, so arrow keys and the wheel
 * keep working.
 */
Item {
    id: audioFaders

    property real s: 1

    /** Index of the currently focused fader (-1 = none), owned by the host. */
    property int faderFocus: -1

    /** Re-emitted from the rows; the host decides what a nudge adjusts. */
    signal stepFocused(int deltaPct)

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    width: parent ? parent.width : 0
    height: 54 * s

    Column {
        width: parent.width
        spacing: 0

        AudioRow {
            s: audioFaders.s
            faderFocus: audioFaders.faderFocus
            onStepFocused: (delta) => audioFaders.stepFocused(delta)
            glyph: "mic"
            name: "Microphone"
            on: ScreenRec.micOn
            faderIndex: 0
            level: audioFaders.source && audioFaders.source.audio ? audioFaders.source.audio.volume : 0
            onFaderMoved: (v) => { if (audioFaders.source && audioFaders.source.audio) audioFaders.source.audio.volume = v; }

            MouseArea {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * audioFaders.s
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.micOn = !ScreenRec.micOn
            }
        }

        AudioRow {
            s: audioFaders.s
            faderFocus: audioFaders.faderFocus
            onStepFocused: (delta) => audioFaders.stepFocused(delta)
            glyph: "speaker"
            name: "Desktop"
            on: ScreenRec.desktopOn
            faderIndex: 1
            level: audioFaders.sink && audioFaders.sink.audio ? audioFaders.sink.audio.volume : 0
            onFaderMoved: (v) => { if (audioFaders.sink && audioFaders.sink.audio) audioFaders.sink.audio.volume = v; }

            MouseArea {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * audioFaders.s
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.desktopOn = !ScreenRec.desktopOn
            }
        }
    }
}

import QtQuick
import Quickshell.Services.Pipewire
import qs.services

/**
 * Default output volume, or the muted state. The tracker keeps the sink's audio
 * object live so its volume property notifies this binding; without it the block
 * would read once and never follow a change.
 */
Text {
    id: root

    property real s: 1.1

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: !sink || !sink.audio || sink.audio.muted
    readonly property int pct: (sink && sink.audio) ? Math.round(sink.audio.volume * 100) : 0

    text: muted ? "VOL mute" : "VOL " + pct + "%"
    color: muted ? BarStyle.dim : BarStyle.fg
    font.family: Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
}

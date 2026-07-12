import QtQuick
import Quickshell.Services.Pipewire

Text {
    readonly property var sink: Pipewire.defaultAudioSink

    color: "white"

    PwObjectTracker {
        objects: [sink].filter(Boolean)
    }

    text: {
        if (!sink || !sink.audio)
            return "VOL ?"

        if (sink.audio.muted)
            return "MUTED"

        return "VOL " +
               Math.round(sink.audio.volume * 100) + "%"
    }
}

pragma Singleton

import QtQuick

/**
 * System: the screen recorder. Quality feeds gpu-screen-recorder's presets
 * (Ultra maps to its `very_high`, Lossless to its `ultra`), and the same values
 * drive the ffmpeg path as a CRF, which is why they are named rather than
 * numbered.
 */
QtObject {
    readonly property string name: "System"
    readonly property string icon: "\u2B21"
    readonly property string keywords: "recording recorder capture gpu-screen-recorder quality ffmpeg crf replay fps audio"

    readonly property var groups: [
        { card: "Recording", rows: [
            { key: "recordCountdown", type: "slider", label: "Countdown", min: 0, max: 10, step: 1, unit: "s", reset: 5 },
            { key: "recordFps", type: "slider", label: "Frame rate", min: 15, max: 144, step: 15, unit: "fps", reset: 60 },
            { key: "recordQuality", type: "segmented", label: "Quality",
              options: ["medium", "high", "ultra", "lossless"], names: ["Medium", "High", "Ultra", "Lossless"], reset: "high" },
            { key: "recordCursor", type: "toggle", label: "Capture cursor", reset: true },
            { key: "recordMic", type: "toggle", label: "Microphone", caption: "Mix the mic into the recording", reset: true },
            { key: "recordDesktop", type: "toggle", label: "Desktop audio", reset: true },
            { key: "recordDir", type: "text", label: "Save folder", placeholder: "~/Videos",
              caption: "Where recordings land (empty = ~/Videos)", reset: "" }
        ]}
    ]
}

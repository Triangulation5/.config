pragma Singleton

import QtQuick

/**
 * System: the low-battery warning, the system monitor's speed test and the
 * screen recorder. Quality feeds gpu-screen-recorder's presets (Ultra maps to
 * its `very_high`, Lossless to its `ultra`), and the same values drive the
 * ffmpeg path as a CRF, which is why they are named rather than numbered.
 *
 * The low-battery row is one threshold for two warnings — the laptop's own
 * (services/Battery.qml) and a peripheral's (services/Peripherals.qml) — so the
 * two cannot drift apart.
 *
 * The speed-test row is the pill's 系 surface: the test moves tens of megabytes,
 * so it is off and the card waits for its Test button until this is turned on.
 *
 * Audio sits here because there is no page of its own: one row, the ceiling the
 * mixer's volume fader reaches.
 */
QtObject {
    readonly property string name: "System"
    readonly property string icon: "\u2B21"
    readonly property string keywords: "recording recorder capture gpu-screen-recorder quality ffmpeg crf replay fps audio volume loud boost battery power charge low warn peripheral system monitor sysmon speed test network throughput"

    readonly property var groups: [
        { card: "Power", rows: [
            { key: "battLowPct", type: "slider", label: "Low battery warning",
              min: 5, max: 50, step: 5, unit: "%",
              caption: "Warn at or below this charge, for the laptop battery and for peripherals", reset: 20 },
            { key: "periphLowNotify", type: "toggle", label: "Low peripheral warning",
              caption: "Notify when a peripheral reaches that charge and is not charging", reset: true }
        ]},
        { card: "Audio", rows: [
            { key: "maxVolume", type: "slider", label: "Max volume",
              min: 100, max: 150, step: 5, unit: "%",
              caption: "Ceiling the mixer's volume fader reaches; above 100% lets the sink run past unity", reset: 100 }
        ]},
        { card: "System monitor", rows: [
            { key: "sysmonAutoTest", type: "toggle", label: "Auto speed test",
              caption: "Run the Cloudflare speed test the moment the monitor opens; off runs it only when Test is pressed (a run moves tens of MB)", reset: false }
        ]},
        { card: "Recording", rows: [
            { key: "recordCountdown", type: "slider", label: "Countdown", min: 0, max: 10, step: 1, unit: "s", reset: 5 },
            { key: "recordFps", type: "slider", label: "Frame rate", min: 15, max: 144, step: 15, unit: "fps", reset: 60 },
            { key: "recordQuality", type: "segmented", label: "Quality",
              options: ["medium", "high", "ultra", "lossless"], names: ["Medium", "High", "Ultra", "Lossless"], reset: "high" },
            { key: "recordCursor", type: "toggle", label: "Capture cursor", reset: true },
            { key: "recordMic", type: "toggle", label: "Microphone", caption: "Mix the mic into the recording", reset: true },
            { key: "recordDesktop", type: "toggle", label: "Desktop audio", reset: true },
            { key: "recordNotify", type: "toggle", label: "Save notification",
              caption: "Post a notification when a recording is saved", reset: true },
            { key: "recordDir", type: "text", label: "Save folder", placeholder: "~/Videos",
              caption: "Where recordings land (empty = ~/Videos)", reset: "" },
            { key: "recHistoryMax", type: "slider", label: "Recent recordings",
              min: 10, max: 200, step: 10, unit: "",
              caption: "How many saved recordings the recorder's list looks up", reset: 40 }
        ]}
    ]
}

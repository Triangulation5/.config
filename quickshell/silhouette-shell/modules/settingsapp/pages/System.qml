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
    readonly property string keywords: "recording recorder capture gpu-screen-recorder quality ffmpeg crf replay fps audio volume loud boost battery power charge low warn packs bat0 bat1 breakdown peripheral system monitor sysmon speed test network throughput privacy indicator dot microphone mic input capture audio-in loopback screen share camera webcam video playback audio-out speaker output sink recording master toggle switch on off poll rust native optimization"

    readonly property var groups: [
        { card: "Native tools", rows: [
            { key: "useRustTools", type: "toggle", label: "Use Rust tools",
              caption: "Use optimized Rust for wallpaper, monitoring, and recording.",
              reset: true }
        ]},
        { card: "Power", rows: [
            { key: "battLowPct", type: "slider", label: "Low battery warning",
              min: 5, max: 50, step: 5, unit: "%",
              caption: "Warn at or below this charge.", reset: 20 },
            { key: "periphLowNotify", type: "toggle", label: "Low peripheral warning",
              caption: "Notify for non-charging peripherals.", reset: true },
            { key: "battShowPacks", type: "toggle", label: "Per-battery breakdown",
              caption: "Show individual BAT0/BAT1 rows in the battery card.", reset: false }
        ]},
        { card: "Audio", rows: [
            { key: "maxVolume", type: "slider", label: "Max volume",
              min: 100, max: 150, step: 5, unit: "%",
              caption: "Volume slider ceiling.", reset: 100 }
        ]},
        { card: "System monitor", rows: [
            { key: "sysmonAutoTest", type: "toggle", label: "Auto speed test",
              caption: "Run speed test on monitor open.", reset: false }
        ]},
        { card: "Recording", rows: [
            { key: "recordCountdown", type: "slider", label: "Countdown", min: 0, max: 10, step: 1, unit: "s", reset: 5 },
            { key: "recordFps", type: "slider", label: "Frame rate", min: 15, max: 144, step: 15, unit: "fps", reset: 60 },
            { key: "recordQuality", type: "segmented", label: "Quality",
              options: ["medium", "high", "ultra", "lossless"], names: ["Medium", "High", "Ultra", "Lossless"], reset: "high" },
            { key: "recordCursor", type: "toggle", label: "Capture cursor", reset: true },
            { key: "recordMic", type: "toggle", label: "Microphone", caption: "Include mic audio.", reset: true },
            { key: "recordDesktop", type: "toggle", label: "Desktop audio", reset: true },
            { key: "recordNotify", type: "toggle", label: "Save notification",
              caption: "Notify when recording saved.", reset: true },
            { key: "recordDir", type: "text", label: "Save folder", placeholder: "~/Videos",
              caption: "Recording destination.", reset: "" },
            { key: "recHistoryMax", type: "slider", label: "Recent recordings",
              min: 10, max: 200, step: 10, unit: "",
              caption: "Number of recordings to track.", reset: 40 }
        ]},
        { card: "Privacy indicator", rows: [
            { key: "privacyDot", type: "toggle", label: "Indicator",
              caption: "Master switch for privacy dot.", reset: true },
            { key: "privacyScreen", type: "toggle", label: "Screen recording",
              caption: "Indicator for active screen recording.", reset: true },
            { key: "privacyAudioIn", type: "toggle", label: "Audio capture",
              caption: "Indicator for active mic/audio-in capture.",
              reset: false },
            { key: "privacyCam", type: "toggle", label: "Camera",
              caption: "Indicator for camera usage.", reset: true },
            { key: "privacyAudioOut", type: "toggle", label: "Audio playback",
              caption: "Indicator for audio output.",
              reset: false },
            { key: "privacyPollMs", type: "slider", label: "Check every",
              min: 500, max: 60000, step: 500, displayScale: 0.001, unit: "s", reset: 1000,
              caption: "Interval for privacy checks. Higher saves CPU." }
        ]},
        { card: "Dot colour", rows: [
            { key: "privacyToneCam", type: "swatch", source: "camera",
              swatches: ["rose", "coral", "periwinkle", "lilac", "seafoam", "moss"],
              label: "Camera",
              caption: "Camera indicator color.", reset: "auto" },
            { key: "privacyToneScreen", type: "swatch", source: "screen",
              swatches: ["periwinkle", "coral", "rose", "lilac", "seafoam", "moss"],
              label: "Screen recording",
              caption: "Recording indicator color.", reset: "auto" },
            { key: "privacyToneAudioIn", type: "swatch", source: "audioIn",
              swatches: ["lilac", "coral", "rose", "periwinkle", "seafoam", "moss"],
              label: "Audio capture",
              caption: "Audio capture indicator color.", reset: "auto" },
            { key: "privacyToneAudioOut", type: "swatch", source: "audioOut",
              swatches: ["moss", "coral", "rose", "periwinkle", "lilac", "seafoam"],
              label: "Audio playback",
              caption: "Audio output indicator color.",
              reset: "auto" }
        ]}
    ]
}

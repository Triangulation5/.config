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
    readonly property string keywords: "recording recorder capture gpu-screen-recorder quality ffmpeg crf replay fps audio volume loud boost battery power charge low warn peripheral system monitor sysmon speed test network throughput privacy indicator dot microphone mic input capture audio-in loopback screen share camera webcam video playback audio-out speaker output sink recording master toggle switch on off poll"

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
        ]},
        { card: "Privacy indicator", rows: [
            { key: "privacyDot", type: "toggle", label: "Indicator",
              caption: "The master switch for this card. Off draws no dot and stops asking "
                + "PipeWire anything at all, so the indicator costs nothing but the code that "
                + "decides not to run", reset: true },
            { key: "privacyScreen", type: "toggle", label: "Screen recording",
              caption: "Read from the recorder's own live flag rather than polled, so it is "
                + "exact the instant a recording starts and this row is free. A recording "
                + "started outside the shell is reported here too", reset: true },
            { key: "privacyAudioIn", type: "toggle", label: "Audio capture",
              caption: "Any process reading audio out of a device. That is the microphone, and "
                + "also a system-audio loopback such as a screen share that carries sound — "
                + "PipeWire reports every one of them the same way, so this single row is as "
                + "fine as the signal gets. Off by default, like audio playback: the most "
                + "reliable thing holding a microphone open is a visualiser running all "
                + "session, and a dot that is lit all session is a dot you learn to ignore",
              reset: false },
            { key: "privacyCam", type: "toggle", label: "Camera",
              caption: "Any process reading from a camera. Switching this off stops the camera "
                + "lighting the dot; the check itself keeps running for the rows above it", reset: true },
            { key: "privacyAudioOut", type: "toggle", label: "Audio playback",
              caption: "Off by default. Sound going out to a speaker is somebody listening, "
                + "not a privacy event, so any player, call or game would light a dot that "
                + "then means nothing. This is about which process is sending sound and has "
                + "nothing to do with volume — the mixer and the OSD are separate settings",
              reset: false },
            { key: "privacyPollMs", type: "slider", label: "Check every",
              min: 500, max: 60000, step: 500, displayScale: 1000, unit: "s", reset: 1000,
              caption: "How often the dot re-reads PipeWire for the audio capture, camera and "
                + "audio playback rows above. Each check is a process spawn, so this trades a "
                + "little idle CPU for a dot that appears the moment you start talking; raise "
                + "it if you would rather have the CPU. It cannot be wound below 0.5s. "
                + "Switching all three of those rows off stops the checks entirely. Screen "
                + "recording is not polled at all. If a check cannot run, the dot shows amber "
                + "rather than going quiet." }
        ]},
        { card: "Dot colour", rows: [
            { key: "privacyToneCam", type: "swatch", source: "camera",
              swatches: ["rose", "coral", "periwinkle", "lilac", "seafoam", "moss"],
              label: "Camera",
              caption: "Auto is the palette's own rose — the colour a camera has worn since the "
                + "dot first shipped. With two things capturing at once the dot takes the first "
                + "of camera, screen, audio capture, audio playback, so this row wins when the "
                + "camera is on", reset: "auto" },
            { key: "privacyToneScreen", type: "swatch", source: "screen",
              swatches: ["periwinkle", "coral", "rose", "lilac", "seafoam", "moss"],
              label: "Screen recording",
              caption: "Auto is the palette's hint blue, which keeps a recording off the same "
                + "warm reds as everything else the shell warns about", reset: "auto" },
            { key: "privacyToneAudioIn", type: "swatch", source: "audioIn",
              swatches: ["lilac", "coral", "rose", "periwinkle", "seafoam", "moss"],
              label: "Audio capture",
              caption: "Auto is the palette's constant lilac. Amber is not offered anywhere here: "
                + "it is the dot's own \"could not check\" tone, and a capture wearing it would "
                + "make the one state that has to stay unambiguous ambiguous", reset: "auto" },
            { key: "privacyToneAudioOut", type: "swatch", source: "audioOut",
              swatches: ["moss", "coral", "rose", "periwinkle", "lilac", "seafoam"],
              label: "Audio playback",
              caption: "Auto is the palette's plus green, the one row here that is not a capture "
                + "and should not be painted like one. Coral is the tone the dot shipped with, "
                + "kept in the list so the colour you already know is still one click away",
              reset: "auto" }
        ]}
    ]
}

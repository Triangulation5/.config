pragma Singleton

import QtQuick

/**
 * Motion: the shell's own animation budget and spectrum visualizer, plus the
 * Hyprland animations themselves — the compositor's master switch, the speed
 * every animation leaf runs at, and which of the three animation sets the config
 * builds (liquid, pill, macos). Those three are written into
 * `decorations.lua` (see the Deco service).
 *
 * The config's animation style gates whole branches of curve and leaf
 * definitions, so switching it changes more than one field; that is the file's
 * design, not something to paper over here.
 *
 * The Shell card is the other half of the same subject, and the two speeds are
 * deliberately separate: the compositor's speed multiplies the leaves in the
 * config, the shell's multiplies the durations `services/Motion.qml` hands to
 * every surface the pill morphs into. One is the desktop, one is the pill, and
 * wanting them equal is not the same as making them one control.
 *
 * Lite mode sits with them because it is the other half of the same budget:
 * reduce motion trims how long things take, lite mode trims what they cost to
 * draw (the blur layers).
 */
QtObject {
    readonly property string name: "Motion"
    readonly property string icon: "\u2248"
    readonly property string keywords: "animation animations speed easing curve bezier style liquid pill macos visualizer cava bars string spectrum motion lite performance gpu blur low end integrated"

    readonly property var groups: [
        { card: "Compositor", rows: [
            { source: "deco", field: "animOn", type: "toggle", label: "Animations",
              caption: "Animate windows, workspaces and fades", reset: true },
            { source: "deco", field: "animSpeed", type: "slider", label: "Speed", min: 1, max: 10, step: 0.5, unit: "",
              caption: "Higher is faster, applied to every animation leaf", reset: 3 },
            { source: "deco", field: "animStyle", type: "segmented", label: "Style",
              caption: "Which curve and leaf set the config defines",
              options: ["liquid", "pill", "macos"], names: ["Liquid", "Pill", "macOS"], reset: "macos" }
        ]},
        { card: "Shell", rows: [
            { key: "reduceMotion", type: "toggle", label: "Reduce motion",
              caption: "Trim the shell's own animation budget", reset: false },
            { key: "liteMode", type: "toggle", label: "Lite mode",
              caption: "Skip the shell's blur layers — the now-playing bleed, the ambient aura, the Ame bead, the lock backdrop — for an integrated GPU; everything still draws, just flat", reset: false },
            { key: "motionSpeed", type: "slider", label: "Speed",
              min: 0.5, max: 2, step: 0.05, unit: "\u00D7",
              caption: "Scales every duration the shell's own motion hands out; the "
                  + "compositor's speed is the row above", reset: 1.0 }
        ]},
        { card: "Visualizer", rows: [
            { key: "musicViz", type: "toggle", label: "Music visualizer",
              caption: "Spectrum in the rest pill while a player is open", reset: true },
            { key: "vizStyle", type: "segmented", label: "Style",
              caption: "Bars, mirrored bars, or the flowing string",
              options: ["bars", "centered", "string"],
              names: ["Bars", "Center", "String"], reset: "bars" },
            { key: "vizFps", type: "slider", label: "Framerate", min: 15, max: 120, step: 15, unit: "fps",
              caption: "Capture rate; the pill EQ is visually identical at 30", reset: 60 }
        ]}
    ]
}

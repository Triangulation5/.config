pragma Singleton

import QtQuick

/**
 * Look: the window decoration the shell's own Look surface edits, read and
 * written straight into `~/.config/hypr/modules/decorations.lua` (see the Deco
 * service) so a change applies now and survives a restart.
 *
 * Every row names a `deco` field rather than a flag, and its bounds are the
 * shell's: a scrub that could not move a field is a control that lies.
 */
QtObject {
    readonly property string name: "Look"
    readonly property string icon: "\u25A3"
    readonly property string keywords: "gaps rounding radius border blur shadow opacity animation decorations window decoration"

    readonly property var groups: [
        { card: "Window", rows: [
            { source: "deco", field: "gapsIn", type: "slider", label: "Gaps inner", min: 0, max: 40, step: 1, unit: "px",
              caption: "Space between tiled windows", reset: 6 },
            { source: "deco", field: "gapsOut", type: "slider", label: "Gaps outer", min: 0, max: 60, step: 1, unit: "px",
              caption: "Space to the screen edge", reset: 12 },
            { source: "deco", field: "rounding", type: "slider", label: "Rounding", min: 0, max: 30, step: 1, unit: "px",
              caption: "Corner radius in pixels", reset: 12 },
            { source: "deco", field: "roundingPower", type: "slider", label: "Rounding power", min: 1, max: 10, step: 1, unit: "",
              caption: "Higher bends corners to a squircle", reset: 4 },
            { source: "deco", field: "borderSize", type: "slider", label: "Border size", min: 0, max: 8, step: 1, unit: "px",
              caption: "Window outline thickness", reset: 2 },
            { source: "deco", field: "resizeOnBorder", type: "toggle", label: "Resize on border",
              caption: "Drag a window edge to resize", reset: true },
            { source: "deco", field: "layout", type: "segmented", label: "Layout",
              caption: "Window tiling layout",
              options: ["dwindle", "master"], names: ["Dwindle", "Master"], reset: "dwindle" }
        ]},
        { card: "Blur", rows: [
            { source: "deco", field: "blurOn", type: "toggle", label: "Blur",
              caption: "Blur behind transparent windows", reset: true },
            { source: "deco", field: "blurSize", type: "slider", label: "Strength", min: 1, max: 20, step: 1, unit: "px",
              caption: "Blur radius", reset: 8 },
            { source: "deco", field: "blurPasses", type: "slider", label: "Passes", min: 1, max: 5, step: 1, unit: "",
              caption: "More passes, smoother blur", reset: 3 },
            { source: "deco", field: "blurVibrancy", type: "slider", label: "Vibrancy", min: 0, max: 1, step: 0.01, unit: "",
              caption: "Colour saturation behind the blur", reset: 0.17 },
            { source: "deco", field: "blurNoise", type: "slider", label: "Noise", min: 0, max: 0.2, step: 0.01, unit: "",
              caption: "Grain mixed into the blur", reset: 0.01 }
        ]},
        { card: "Shadow", rows: [
            { source: "deco", field: "shadowOn", type: "toggle", label: "Shadow",
              caption: "Drop shadow under windows", reset: true },
            { source: "deco", field: "shadowRange", type: "slider", label: "Range", min: 0, max: 50, step: 1, unit: "px",
              caption: "How far the shadow spreads", reset: 12 },
            { source: "deco", field: "shadowPower", type: "slider", label: "Render power", min: 1, max: 4, step: 1, unit: "",
              caption: "Shadow falloff sharpness", reset: 3 }
        ]},
        { card: "Opacity", rows: [
            { source: "deco", field: "activeOpacity", type: "slider", label: "Active window", min: 0.5, max: 1, step: 0.05, unit: "",
              caption: "Focused window transparency", reset: 1.0 },
            { source: "deco", field: "inactiveOpacity", type: "slider", label: "Inactive window", min: 0.5, max: 1, step: 0.05, unit: "",
              caption: "Unfocused window transparency", reset: 1.0 }
        ]}
    ]
}

pragma Singleton

import QtQuick
import qs.services

/**
 * Input: pointer, keyboard and cursor, written into `input.lua`, `env.lua` and
 * the autostart cursor line (see the Input service). The cursor rows apply live
 * through `hyprctl setcursor`; everything else reloads Hyprland.
 *
 * The layout row offers the common layouts plus whatever the file already says,
 * so a config on an unlisted one still shows its value instead of an empty strip.
 */
QtObject {
    readonly property string name: "Input"
    readonly property string icon: "\u2328"

    readonly property var groups: [
        { card: "Pointer", rows: [
            { source: "input", field: "sensitivity", type: "slider", label: "Sensitivity", min: -1, max: 1, step: 0.05, unit: "",
              caption: "Pointer speed offset; 0 leaves it alone", reset: 0 },
            { source: "input", field: "accelProfile", type: "segmented", label: "Acceleration",
              caption: "How pointer speed follows motion",
              options: ["flat", "adaptive"], names: ["Flat", "Adaptive"], reset: "flat" }
        ]},
        { card: "Keyboard", rows: [
            { source: "input", field: "kbLayout", type: "segmented", label: "Layout",
              caption: "Keyboard layout",
              options: Input.kbLayoutOptions, names: Input.kbLayoutNames, reset: "us" },
            { source: "input", field: "repeatRate", type: "slider", label: "Repeat rate", min: 1, max: 100, step: 1, unit: "/s",
              caption: "Key repeats per second when held", reset: 25 },
            { source: "input", field: "repeatDelay", type: "slider", label: "Repeat delay", min: 100, max: 1000, step: 50, unit: "ms",
              caption: "Hold time before a key repeats", reset: 600 },
            { source: "input", field: "numlock", type: "toggle", label: "Numlock",
              caption: "Numlock on at startup", reset: false }
        ]},
        { card: "Cursor", rows: [
            { source: "input", field: "cursorSize", type: "slider", label: "Size", min: 16, max: 64, step: 2, unit: "px",
              caption: "Cursor size in pixels", reset: 24 },
            { source: "input", field: "cursorTheme", type: "text", label: "Theme", placeholder: "Bibata-Modern-Ice",
              caption: "XCURSOR_THEME; applied live with hyprctl setcursor", reset: "Bibata-Modern-Ice" }
        ]}
    ]
}

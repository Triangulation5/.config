pragma Singleton

import QtQuick

/**
 * Bar & Island: the pill's own geometry, the notch look, and game mode. These
 * are the flags the shell reads in Modules/pill and in Motion, so a change here
 * is visible on the pill immediately.
 */
QtObject {
    readonly property string name: "Bar & Island"
    readonly property string icon: "\u25AD"

    readonly property var groups: [
        { card: "Pill", rows: [
            { key: "topGap", type: "slider", label: "Pill gap", min: -1, max: 2, step: 0.1, unit: "",
              caption: "Space above the pill as a fraction of the shipped 8px; lower moves it up", reset: 0.7 },
            { key: "appGap", type: "slider", label: "App gap", min: 0, max: 2, step: 0.1, unit: "",
              caption: "Gap between the pill and tiled windows; 0 tucks them flush underneath", reset: 1.0 },
            { key: "pillOpacity", type: "slider", label: "Pill opacity", min: 0.55, max: 1, step: 0.05,
              displayScale: 100, unit: "%", reset: 1.0 },
            // The pill's frost is a layer rule in the Hyprland config, not a flag:
            // toggling it adds or removes that rule, which is what the shell does.
            { source: "deco", field: "pillBlur", type: "toggle", label: "Pill blur",
              caption: "Frosts the pill body; needs opacity under 100% to show", reset: true },
            { key: "autoHide", type: "toggle", label: "Auto hide",
              caption: "Retract the pill off the top edge until the pointer touches it", reset: false }
        ]},
        { card: "Notch", rows: [
            { key: "notchStyle", type: "toggle", label: "Show as notch",
              caption: "Square-top island with flared ears instead of the rounded pill", reset: false },
            { key: "notchFlare", type: "slider", label: "Notch flare", min: -7, max: 10, step: 0.25, unit: "px",
              caption: "Flare offset pushed out on both notch ears", reset: 1 }
        ]},
        { card: "Gaming", rows: [
            { key: "gameMode", type: "toggle", label: "Game mode",
              caption: "Flat strip, no animations, no popups while a game is focused", reset: false }
        ]}
    ]
}

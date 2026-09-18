pragma Singleton

import QtQuick

/**
 * Corners: the overlay that rounds the display's own corners, one panel per
 * monitor. Three radii — the notch style's wider bezel rounding, the normal
 * style's subtler one, and what the corners collapse to while game mode is on —
 * plus the bezel shadow inside them and how long the collapse takes.
 *
 * These were constants inside `modules/screencorner/ScreenCornerRoot.qml`, which
 * is the sort of value that looks like code until the first person wants a
 * squarer screen: they are flags now (see Flags), and this page is why.
 */
QtObject {
    readonly property string name: "Corners"
    readonly property string icon: "\u25E2"
    readonly property string keywords: "corner corners rounding radius screen edge bezel shadow notch game squircle display"

    readonly property var groups: [
        { card: "Screen corners", rows: [
            { key: "cornerNotchRadius", type: "slider", label: "Notch radius",
              min: 0, max: 40, step: 1, unit: "px",
              caption: "Screen rounding while the pill is in notch style", reset: 12 },
            { key: "cornerNormalRadius", type: "slider", label: "Radius",
              min: 0, max: 40, step: 1, unit: "px",
              caption: "Screen rounding otherwise; 0 squares the display off", reset: 8 },
            { key: "cornerGameRadius", type: "slider", label: "Game mode",
              min: 0, max: 40, step: 1, unit: "px",
              caption: "What the corners collapse to while game mode is on", reset: 0 },
            { key: "cornerShadowSize", type: "slider", label: "Inner shadow",
              min: 0, max: 24, step: 1, unit: "px",
              caption: "Bezel shadow painted inside each corner (0 = none)", reset: 8 },
            { key: "cornerMorphMs", type: "slider", label: "Collapse time",
              min: 0, max: 3000, step: 100, unit: "ms",
              caption: "How long the corners take to come and go in game mode", reset: 1500 }
        ]}
    ]
}

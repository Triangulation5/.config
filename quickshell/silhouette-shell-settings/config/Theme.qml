pragma Singleton

import QtQuick

/**
 * The panel's palette, radii, type and motion — the app's own theme, not the
 * shell's. These are the values the panel was designed around, so keep them
 * together: a component that needs a colour takes it from here rather than
 * inventing one.
 */
QtObject {
    // Palette
    readonly property color window: "#090909"
    readonly property color sidebar: "#080808"
    readonly property color card: "#100d0d"
    readonly property color text: "#d0d0d0"
    readonly property color textSecondary: "#888888"
    readonly property color accent: "#9dcc9a"
    readonly property color sliderTrack: "#2a2a2a"
    readonly property color border: Qt.rgba(1, 1, 1, 0.05)
    readonly property color hover: "#161616"
    readonly property color selected: "#1e1e1e"
    readonly property color searchField: "#161616"
    readonly property color knob: "#101010"
    readonly property color navButton: "#161616"

    // Radii. There is no window radius: the compositor cuts this window's corners
    // (see Panel), so a token here would only be a second opinion.
    readonly property int radiusCard: 14
    readonly property int radiusRow: 10

    // Typography
    readonly property int fontSizeTitle: 20
    readonly property int fontSizeNormal: 14
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeSection: 11

    // Motion
    readonly property int animFast: 120
    readonly property int animNormal: 150
    readonly property int animWindow: 220
}

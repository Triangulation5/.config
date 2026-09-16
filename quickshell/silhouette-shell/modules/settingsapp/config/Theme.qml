pragma Singleton

import QtQuick
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services

/**
 * The panel's palette, radii, type and motion, with two exceptions that are not
 * the app's own: `accent` (every highlight — the rail's selection, the toggles,
 * the reveal ring, the focus ring on a field) and `window`/`sidebar` (the surface
 * behind the rail and the cards) belong to the pill. A settings window that
 * highlights in a different colour from the thing it configures reads as a
 * different app, which is exactly how this one read.
 *
 * "Belong to the pill" means the pill's *mode*, not one frozen snapshot. On the
 * static palette the accent is the pill's curated highlight `#d8647e`, and the
 * body is **black**: the shell's Theme writes its static surfaces as
 * `"rgba(37,37,48,1.00)"`, which Qt's colour parser cannot read, so `cardTop`
 * falls back to `#000000` and that is what the pill actually paints. Matching the
 * pill means matching the pixels, so this window is black too — see the note on
 * `window` below. On dynamic or manual the pill paints the generated palette the
 * shell's Dyn service watches (those tokens are valid hex, so they land), and
 * this window follows it, re-tinting the moment a wallpaper change re-tints the
 * pill. Everything else, the cards included, stays as designed: a card is the
 * app's own surface, and `#100d0d` is what the rows were laid out against.
 *
 * These are the values the panel was designed around, so keep them together: a
 * component that needs a colour takes it from here rather than inventing one.
 */
QtObject {
    // Palette

    /** True while the shell's palette follows the wallpaper or the manual hue. */
    readonly property bool dyn: Store.adapter.paletteMode !== "static"

    /** The pill's highlight. */
    readonly property color accent: dyn ? Dyn.primary : "#d8647e"
    /**
     * The pill's own body colour: the backdrop the rail and the cards sit on.
     *
     * Static is `#000000`, not the `#252530` the shell's token is named for,
     * because the shell never manages to paint the latter: `Theme.cardTop` is
     * assigned the string `"rgba(37,37,48,1.00)"`, which is not a colour Qt can
     * parse, so the property keeps its black default and the pill, its cards and
     * its capsules all come out black. Verified against the running shell: the
     * pill's body pixels read `(0,0,1)` while its text reads `(205,205,205)`,
     * the static `Theme.cream` — so the palette is static and the body is the
     * fallback. If the shell's strings are ever repaired, this value is the one
     * line in this app that has to follow, and the comment above the singleton
     * says so.
     */
    readonly property color window: dyn ? Dyn.surfaceContainerHigh : "#000000"
    readonly property color sidebar: window
    readonly property color card: "#100d0d"
    readonly property color text: "#d0d0d0"
    readonly property color textSecondary: "#888888"
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

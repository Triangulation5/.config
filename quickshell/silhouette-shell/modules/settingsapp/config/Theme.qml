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
 * "Belong to the pill" means the pill's *mode*, not one frozen snapshot. On a
 * dynamic or manual palette the pill paints the generated colours the shell's
 * Dyn service watches (those tokens are valid hex, so they land), and this window
 * follows it, re-tinting the moment a wallpaper change re-tints the pill. On the
 * static palette the pill paints whichever scheme is selected, and so does this
 * window — see the note on `window` below. Everything else, the cards included,
 * stays as designed: a card is the app's own surface, and `#100d0d` is what the
 * rows were laid out against.
 *
 * The shell's two static schemes are defined in the shell's own
 * `services/ColorScheme.qml`, and the accent and body colour each one paints are
 * restated here. They have to be: the app and the shell are separate Quickshell
 * instances (see `services/Dyn.qml`), so the flags file is the only thing they
 * share and a scheme cannot be imported across that boundary. Only the two
 * values the pill-facing tokens below actually use are restated — the same rule
 * that keeps `Dyn` to two keys.
 *
 * These are the values the panel was designed around, so keep them together: a
 * component that needs a colour takes it from here rather than inventing one.
 */
QtObject {
    id: root

    /** Palette */

    /** True while the shell's palette follows the wallpaper or the manual hue. */
    readonly property bool dyn: Store.adapter.paletteMode !== "static"

    /**
     * True when the shell is on its original static palette rather than the port.
     * Only an explicit "vague" turns it off, so a value that is neither name
     * renders as legacy — the same default the flag itself carries, and the same
     * fallback the shell's own `services/ColorScheme.qml` applies.
     */
    readonly property bool legacy: Store.adapter.colorScheme !== "vague"

    /** The pill's highlight. Both static schemes agree on it, so only dyn branches. */
    readonly property color accent: dyn ? Dyn.primary : "#d8647e"
    /**
     * The pill's own body colour: the backdrop the rail and the cards sit on.
     *
     * The pill paints this as its `Theme.cardTop`, so this follows whichever
     * static scheme is selected. `legacy` — the default — is `#000000`, because
     * that scheme keeps the shell's original `"rgba(37,37,48,1.00)"`, which Qt's
     * colour parser cannot read and which therefore resolves to transparent
     * black; `vague` is `#252530`, the colour that scheme ports from vague.nvim's
     * `line`. That is the whole difference between the two schemes as far as this
     * window is concerned, and it is visible the moment the scheme row on the
     * Appearance page is touched.
     */
    readonly property color window: dyn ? Dyn.surfaceContainerHigh : (legacy ? "#000000" : "#252530")
    readonly property color sidebar: window
    readonly property color card: "#100d0d"
    readonly property color text: "#d0d0d0"
    readonly property color textSecondary: "#888888"
    /** Ink that is there but out of play — a chevron at the end of the page list. */
    readonly property color faint: "#4d4d4d"
    readonly property color sliderTrack: "#2a2a2a"
    readonly property color border: Qt.rgba(1, 1, 1, 0.05)
    readonly property color hover: "#161616"
    readonly property color selected: "#1e1e1e"
    readonly property color searchField: "#161616"
    readonly property color knob: "#101010"
    readonly property color navButton: "#161616"

    /**
     * The privacy dot's swatches, mirrored from `services/ColorScheme.qml` for
     * the same reason `accent` is restated above: this app and the shell are
     * separate Quickshell instances, so a row that offers a colour has to know
     * the colours without importing them. These are vague.nvim's own hues —
     * every value is the same string the shell paints from, so a pick here is
     * the pick the dot shows.
     *
     * Amber is absent on purpose: it is the dot's "the check could not run"
     * tone, and a capture wearing it would make the one state that must stay
     * unambiguous ambiguous.
     */
    readonly property var privacySwatches: ({
        rose: "#d8647e",
        coral: "#e0705f",
        periwinkle: "#7e98e8",
        lilac: "#aeaed1",
        seafoam: "#b4d4cf",
        moss: "#7fa563"
    })

    /**
     * What each source takes on "Auto", mirroring the same table in
     * `services/ColorScheme.qml`. The Auto chip paints this, so the row shows
     * the colour that choice will actually produce rather than the word.
     */
    readonly property var privacyTones: ({
        camera: root.privacySwatches.rose,
        screen: root.privacySwatches.periwinkle,
        audioIn: root.privacySwatches.lilac,
        audioOut: root.privacySwatches.moss
    })

    /**
     * Resolve one chip's colour: the swatch it names, or the row's own default
     * for Auto. An unknown name falls back to Auto's colour rather than to
     * transparent, because a chip the user can pick must never be invisible.
     */
    function privacySwatchColor(key, source) {
        if (key !== "auto" && root.privacySwatches[key] !== undefined)
            return root.privacySwatches[key];
        if (root.privacyTones[source] !== undefined)
            return root.privacyTones[source];
        return root.privacyTones.screen;
    }

    /**
     * Radii. There is no window radius: the compositor cuts this window's
     * corners (see Panel), so a token here would only be a second opinion.
     */
    readonly property int radiusCard: 14
    readonly property int radiusRow: 10

    /** Typography */
    readonly property int fontSizeTitle: 20
    readonly property int fontSizeNormal: 14
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeSection: 11

    /** Motion */
    readonly property int animFast: 120
    readonly property int animNormal: 150
    readonly property int animWindow: 220
}

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
 * window — see the note on `window` below. Accented is the middle case: the
 * accent follows the wallpaper while the window keeps the selected static
 * scheme's body, so `accent` branches on `accentFromWallpaper` rather than on
 * `dyn`. Everything else, the cards included, stays as designed: a card is the
 * app's own surface, and `#100d0d` is what the rows were laid out against.
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
 *
 * Surfaces, outlines and radii pass through this app's `Style` first, which
 * reads the same profile table as the shell and the same `Store.adapter.style`
 * the Design style row writes. Washi returns every base value untouched;
 * Material tints the window and cards from the accent and rounds the shape
 * scale, so the window re-dresses itself live as the toggle moves.
 */
QtObject {
    id: root

    /** Palette */

    /**
     * True while the window itself follows the generated palette: Dynamic and
     * Manual. Accented is deliberately excluded — it keeps this window's static
     * surfaces and text and takes only `accent` from the wallpaper, which is the
     * whole point of that mode (see `accentFromWallpaper` below).
     */
    readonly property bool dyn: Store.adapter.paletteMode === "dynamic" || Store.adapter.paletteMode === "manual"

    /** True in Accented mode: wallpaper accents on the selected static scheme. */
    readonly property bool accented: Store.adapter.paletteMode === "accented"

    /** True when the highlight and the ink that sits on it are generated. */
    readonly property bool accentFromWallpaper: root.dyn || root.accented

    /** True while the Material design language is active. */
    readonly property bool material: Style.tonal

    /**
     * True when the shell is on its original static palette rather than the port.
     * Only an explicit "vague" turns it off, so a value that is neither name
     * renders as legacy — the same default the flag itself carries, and the same
     * fallback the shell's own `services/ColorScheme.qml` applies.
     */
    readonly property bool legacy: Store.adapter.colorScheme !== "vague"

    /** The pill's highlight. Both static schemes agree on it, so only the accent source branches. */
    readonly property color accent: accentFromWallpaper ? Dyn.primary : "#d8647e"
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
    /**
     * The palette's own window colour, before the design language treats it.
     * Kept separate from `window` so Style can return it untouched on Washi and
     * tint it with the accent on Material without the conditional above having
     * to be repeated.
     */
    readonly property color baseWindow: dyn ? Dyn.surfaceContainerHigh : (legacy ? "#000000" : "#252530")
    readonly property color window: Style.surface(root.baseWindow, root.accent, "window")
    readonly property color sidebar: window
    /**
     * On Dynamic these stop being the app's own dark design and become the
     * generated scheme: a Material light palette has light cards and dark ink,
     * and keeping `#100d0d`/`#d0d0d0` would paint light text on a light card.
     * The card role is one step below the window's, which is the M3 elevation
     * convention the shell's pill already follows.
     */
    readonly property color baseCard: dyn ? Dyn.surfaceContainerLow : "#100d0d"
    readonly property color card: Style.surface(root.baseCard, root.accent, "card")

    /**
     * Text on the generated scheme: Material's on_surface / on_surface_variant
     * are the intended inks. `wallcolors.py` walks both until they clear 4.5:1
     * on every surface step the app paints on (window, cards, hover), so they
     * are used as-is rather than re-mixed here — a fixed-grey mix was what made
     * light-mode ink faint and dark-mode labels look muddy.
     */
    readonly property color text: dyn ? Dyn.onSurface : "#d0d0d0"
    readonly property color textSecondary: dyn ? Dyn.onSurfaceVariant : "#888888"

    /** Ink that is there but out of play — a chevron at the end of the page list. */
    readonly property color faint: dyn ? Dyn.outline : "#4d4d4d"
    readonly property color sliderTrack: dyn ? Dyn.outlineVariant : "#2a2a2a"
    /** Typed copy so Qt.alpha gets a colour, not a string, on the dynamic branch. */
    readonly property color dynamicOutlineVariant: Dyn.outlineVariant
    readonly property color baseBorder: dyn ? Qt.alpha(dynamicOutlineVariant, 0.45) : Qt.rgba(1, 1, 1, 0.05)
    readonly property color border: Style.border(root.baseBorder, root.accent)
    readonly property color baseHover: dyn ? Dyn.surfaceContainerHighest : "#161616"
    readonly property color hover: Style.overlay(root.baseHover, root.accent, false)
    readonly property color baseSelected: dyn ? Dyn.surfaceContainerHighest : "#1e1e1e"
    readonly property color selected: Style.overlay(root.baseSelected, root.accent, true)
    readonly property color baseSearchField: dyn ? Dyn.surfaceContainer : "#161616"
    readonly property color searchField: Style.control(root.baseSearchField, root.accent)
    readonly property color surfaceContainerLow: dyn ? Dyn.surfaceContainerLow : root.card
    readonly property color surfaceContainer: dyn ? Dyn.surfaceContainer : root.card
    readonly property color surfaceContainerHigh: dyn ? Dyn.surfaceContainerHigh : root.searchField
    readonly property color surfaceContainerHighest: dyn ? Dyn.surfaceContainerHighest : root.selected
    readonly property color knob: accentFromWallpaper ? Dyn.onPrimary : "#101010"
    readonly property color baseNavButton: dyn ? Dyn.surfaceContainer : "#161616"
    readonly property color navButton: Style.control(root.baseNavButton, root.accent)

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
    readonly property int radiusCard: Style.radiusCard
    readonly property int radiusRow: Style.radiusRow
    readonly property int radiusChip: Style.radiusChip
    readonly property int radiusField: Style.radiusField
    readonly property int radiusTile: Style.radiusTile
    readonly property int radiusSmall: Style.radiusSmall

    /** 4 dp spacing scale. */
    readonly property int space1: Style.space1
    readonly property int space2: Style.space2
    readonly property int space3: Style.space3
    readonly property int space4: Style.space4
    readonly property int space5: Style.space5
    readonly property int space6: Style.space6

    /** Typography */
    readonly property string fontFamily: (Store.adapter.uiFont && Store.adapter.uiFont.length > 0) ? Store.adapter.uiFont : "Inter"
    readonly property int fontSizeTitle: 20
    readonly property int fontSizeNormal: 14
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeSection: 11

    /** Motion */
    readonly property int animFast: Style.animFast
    readonly property int animNormal: Style.animNormal
    readonly property int animWindow: Style.animWindow
}

/**
 * Shared colour and font tokens for the shell. Every surface and widget reads
 * its palette from here so a single swap re-tints the whole shell. In dynamic
 * or manual palette mode the tokens follow the live wallpaper-derived palette
 * (Dyn); in accented mode only the accent tokens do, while surfaces and text
 * stay on the selected scheme. Otherwise they come from the selected colour
 * scheme — by default the shell's own original palette, or `vague`, a proper
 * port of that palette (see `ColorScheme.qml`, which is where a scheme is
 * defined and chosen). Also carries the UI font (Flags-driven, defaulting to
 * Inter) and a small artist-list helper for media labels.
 *
 * The colours below are a façade, not a palette. They were the palette once, and
 * they are kept as named properties anyway because every surface in the shell
 * binds to them: folding the schemes in here would mean editing every consumer
 * each time one was added, and renaming a token is a shell-wide search. So the
 * scheme lives in its own file and this one reads it — which also means a widget
 * that wants the whole palette can read `ColorScheme` directly, while one that
 * just wants a colour keeps saying `Theme.<token>` as it always has.
 *
 * The surface and shape tokens pass through `Style` first. A design language
 * changes a surface's *material* as well as its colour — Material tints the
 * card with the accent, Washi leaves the palette untouched — so the resolved
 * tokens belong to the style, and `Theme` stays the one name consumers bind to.
 */
pragma Singleton
import QtQuick
import Quickshell
import qs.services

Singleton {
    /** True while the whole palette follows the wallpaper or the manual hue. */
    readonly property bool dyn: ColorScheme.dyn

    /** The colour scheme the palette is drawn from: "legacy" or "vague". */
    readonly property string colorScheme: ColorScheme.name

    /**
     * The live design language: "washi" or "material". Components rarely need
     * to branch on this — the surface tokens below already carry the style's
     * material — but a surface that has an extra treatment (a tonal fill, a
     * specular rim) can ask.
     */
    readonly property string designStyle: Style.name
    readonly property bool material: Style.tonal

    /**
     * Shape scale from the design language. Washi returns the numbers the shell
     * shipped with, so a component that takes a radius from here keeps its old
     * silhouette until Material is picked.
     */
    readonly property real radiusCard: Style.radiusCard
    readonly property real radiusRow: Style.radiusRow
    readonly property real radiusChip: Style.radiusChip
    readonly property real radiusField: Style.radiusField
    readonly property real radiusTile: Style.radiusTile
    readonly property real radiusSmall: Style.radiusSmall

    /** 4 dp spacing scale. */
    readonly property int space1: Style.space1
    readonly property int space2: Style.space2
    readonly property int space3: Style.space3
    readonly property int space4: Style.space4
    readonly property int space5: Style.space5
    readonly property int space6: Style.space6

    /** Pill outline, elevation and corner treatment from the design language. */
    readonly property real pillBorderWidth: Style.pillBorderWidth
    readonly property real pillShadowOpacity: Style.pillShadowOpacity
    readonly property real pillShadowBlur: Style.pillShadowBlur
    readonly property real pillShadowOffset: Style.pillShadowOffset
    function pillRestCorner(base) { return Style.pillCorner(base); }
    function pillOpenCorner(base) { return Style.pillOpenCorner(base); }

    /**
     * Material 3 colour roles. Washi maps these onto the same scheme tokens the
     * shell already used, so a component can name a role unconditionally.
     */
    readonly property color primary: Style.primary
    readonly property color onPrimary: Style.onPrimary
    readonly property color primaryContainer: Style.primaryContainer
    readonly property color onPrimaryContainer: Style.onPrimaryContainer
    readonly property color secondaryContainer: Style.secondaryContainer
    readonly property color onSecondaryContainer: Style.onSecondaryContainer
    readonly property color onSurface: Style.onSurface
    readonly property color onSurfaceVariant: Style.onSurfaceVariant
    readonly property color outline: Style.outline
    readonly property color outlineVariant: Style.outlineVariant

    readonly property color surfaceContainerLowest: Style.surfaceContainerLowest
    readonly property color surfaceContainerLow: Style.surfaceContainerLow
    readonly property color surfaceContainer: Style.surfaceContainer
    readonly property color surfaceContainerHigh: Style.surfaceContainerHigh
    readonly property color surfaceContainerHighest: Style.surfaceContainerHighest
    readonly property color surfaceDim: Style.surfaceDim
    readonly property color surfaceBright: Style.surfaceBright

    /** M3 interaction state layers. */
    readonly property color stateHover: Style.stateHover
    readonly property color stateFocus: Style.stateFocus
    readonly property color statePressed: Style.statePressed
    readonly property color stateSelected: Style.stateSelected

    /** Palette */

    readonly property color onGlow: ColorScheme.onGlow

    readonly property color verm:     ColorScheme.verm
    readonly property color vermLit:  ColorScheme.vermLit
    readonly property color vermDeep: ColorScheme.vermDeep

    readonly property color cream:    ColorScheme.cream
    readonly property color bright:   ColorScheme.bright
    readonly property color dim:      ColorScheme.dim

    readonly property color cardTop:  Style.cardTop
    readonly property color cardBot:  Style.cardBot

    readonly property color border: Style.border

    readonly property color shadow: Qt.rgba(0, 0, 0, 1.00)

    readonly property color tileBg: Style.tileBg

    readonly property color subtle: ColorScheme.subtle
    readonly property color faint: ColorScheme.faint
    readonly property color iconDim: ColorScheme.iconDim

    readonly property color hair:     Style.hair
    readonly property color hairSoft: Style.hairSoft
    readonly property color sheen:    Style.sheen

    readonly property color vermDim: ColorScheme.vermDim
    readonly property color vermDimDeep: ColorScheme.vermDimDeep
    readonly property color vermBurn: ColorScheme.vermBurn

    readonly property color tickRest: ColorScheme.tickRest

    readonly property color threadBg: ColorScheme.threadBg

    readonly property color flameCore: ColorScheme.flameCore
    readonly property color flameGlow: ColorScheme.flameGlow

    readonly property string flameInk:   ColorScheme.flameInk
    readonly property string flameEmber: ColorScheme.flameEmber
    readonly property string flameBurn:  ColorScheme.flameBurn
    readonly property string flameTip:   ColorScheme.flameTip

    readonly property color todayWarm: ColorScheme.todayWarm

    readonly property color ghost: Style.ghost

    readonly property color capsule: Style.capsule
    readonly property color capsuleBorder: Style.capsuleBorder
    readonly property color error: ColorScheme.error

    /**
     * The privacy dot's unknown tone: the capture check could not be run.
     * Fixed rather than scheme- and palette-dependent — a safety signal must
     * not be something a pale wallpaper can hide. The *capture* tones are not
     * here because there is more than one of them and which applies is the
     * service's call: read `Privacy.tone`. See the note in `ColorScheme.qml`.
     */
    readonly property color privacyUnknown: ColorScheme.privacyUnknown
    readonly property color placeholder: ColorScheme.placeholder
    readonly property color trackBg: Style.trackBg

    readonly property color frameBg: Style.frameBg
    readonly property color frameBorder: Style.frameBorder
    readonly property color creamMenu: Style.creamMenu

    readonly property real shadowOpacity: Style.shadowOpacity

    property var fontFamilies: Qt.fontFamilies()
    function refreshFonts() { fontFamilies = Qt.fontFamilies(); }
    readonly property string font: (Flags.uiFont.length > 0 && fontFamilies.indexOf(Flags.uiFont) >= 0) ? Flags.uiFont : "Inter"
    readonly property string fontJp: "JetBrainsMono Nerd Font Mono"

    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }

    /**
     * Linear blend between two colors, used everywhere a surface mixes its
     * card palette (wash tints, marquee fades). Shared so callers never
     * reimplement the lerp.
     */
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1);
    }
}

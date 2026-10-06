/**
 * Shared colour and font tokens for the shell. Every surface and widget reads
 * its palette from here so a single swap re-tints the whole shell. In dynamic
 * palette mode the tokens follow the live wallpaper-derived palette (Dyn);
 * otherwise they come from the selected colour scheme — by default the shell's own
 * original palette, or `vague`, a proper port of that palette (see
 * `ColorScheme.qml`, which is where a scheme is defined and chosen). Also carries
 * the UI font (Flags-driven, defaulting to Inter) and a small artist-list helper
 * for media labels.
 *
 * The colours below are a façade, not a palette. They were the palette once, and
 * they are kept as named properties anyway because every surface in the shell
 * binds to them: folding the schemes in here would mean editing every consumer
 * each time one was added, and renaming a token is a shell-wide search. So the
 * scheme lives in its own file and this one reads it — which also means a widget
 * that wants the whole palette can read `ColorScheme` directly, while one that
 * just wants a colour keeps saying `Theme.<token>` as it always has.
 */
pragma Singleton
import QtQuick
import Quickshell
import qs.services

Singleton {
    /** True while the shell's palette follows the wallpaper or the manual hue. */
    readonly property bool dyn: ColorScheme.dyn

    /** The colour scheme the palette is drawn from: "legacy" or "vague". */
    readonly property string colorScheme: ColorScheme.name

    /** Palette */

    readonly property color onGlow: ColorScheme.onGlow

    readonly property color verm:     ColorScheme.verm
    readonly property color vermLit:  ColorScheme.vermLit
    readonly property color vermDeep: ColorScheme.vermDeep

    readonly property color cream:    ColorScheme.cream
    readonly property color bright:   ColorScheme.bright
    readonly property color dim:      ColorScheme.dim

    readonly property color cardTop:  ColorScheme.cardTop
    readonly property color cardBot:  ColorScheme.cardBot

    readonly property color border: ColorScheme.border

    readonly property color shadow: Qt.rgba(0, 0, 0, 1.00)

    readonly property color tileBg: ColorScheme.tileBg

    readonly property color subtle: ColorScheme.subtle
    readonly property color faint: ColorScheme.faint
    readonly property color iconDim: ColorScheme.iconDim

    readonly property color hair:     ColorScheme.hair
    readonly property color hairSoft: ColorScheme.hairSoft
    readonly property color sheen:    ColorScheme.sheen

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

    readonly property color ghost: ColorScheme.ghost

    readonly property color capsule: ColorScheme.capsule
    readonly property color capsuleBorder: ColorScheme.capsuleBorder
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
    readonly property color trackBg: ColorScheme.trackBg

    readonly property color frameBg: ColorScheme.frameBg
    readonly property color frameBorder: ColorScheme.frameBorder
    readonly property color creamMenu: ColorScheme.creamMenu

    readonly property real shadowOpacity: 0.5

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

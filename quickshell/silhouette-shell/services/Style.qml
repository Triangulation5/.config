pragma Singleton
import QtQuick
import Quickshell
import qs.services
import "../utils/settings/style.js" as Spec

/**
 * The shell's design-language tokens.
 *
 * `Flags.style` picks one of three profiles from
 * `utils/settings/style.js`: Washi (the original paper-flat look), Liquid
 * Glass (Apple's translucent material) or Material You (Google's tonal
 * Material 3). The profile owns shape, surface treatment, outlines, shadows and
 * motion — never the palette. A style can be worn with any palette mode, so
 * "Material You" on a static scheme is still Material's tonal surface
 * treatment, while "Dynamic" is still the wallpaper-derived colour ramp.
 *
 * Colours are computed here rather than in `Theme` because a style can change
 * a surface's *material*: Washi returns the scheme colour untouched, Material
 * mixes the accent into it, and Glass lightens it a little and then makes it
 * translucent so Hyprland's compositor blur can show through. `Theme` is then a
 * pure façade again — it reads these tokens and the rest of the shell keeps
 * binding to `Theme.cardTop`, `Theme.border` and friends.
 *
 * Washi is the identity profile: every function returns its input unchanged and
 * every radius/duration keeps the old number, so a session that never touches
 * the style flag renders exactly as it did before this file existed.
 */
Singleton {
    id: root

    readonly property var p: Spec.profile(Flags.style)

    readonly property string name: p.name
    readonly property string label: p.label
    readonly property string description: p.description
    readonly property bool glass: p.glass
    readonly property bool tonal: p.tonal

    /** Shape scale. */
    readonly property real radiusCard: p.radiusCard
    readonly property real radiusRow: p.radiusRow
    readonly property real radiusChip: p.radiusChip
    readonly property real radiusField: p.radiusField
    readonly property real radiusTile: p.radiusTile
    readonly property real radiusSmall: p.radiusSmall

    /** Surface material. */
    readonly property real borderWidth: p.borderWidth
    readonly property real specular: p.specular
    readonly property real shadowOpacity: p.shadowOpacity
    readonly property real shadowBlur: p.shadowBlur
    readonly property real shadowOffset: p.shadowOffset

    /**
     * The live surface tokens, ready for `Theme` to expose.
     *
     * `cardTop` is the pill body and the settings cards, `cardBot` its lower
     * gradient stop, and `tileBg` the small-control surface. They are computed
     * from `ColorScheme` here so a wallpaper change and a style change are the
     * same kind of update to every consumer.
     */
    readonly property color cardTop: surface(ColorScheme.cardTop, "surface")
    readonly property color cardBot: surface(ColorScheme.cardBot, "surface")
    readonly property color tileBg: surface(ColorScheme.tileBg, "tile")
    readonly property color border: borderColor(ColorScheme.border)
    readonly property color sheen: sheenColor(ColorScheme.sheen)

    /** Pill body. */
    readonly property real pillBorderWidth: p.pillBorderWidth
    readonly property real pillShadowOpacity: p.pillShadowOpacity
    readonly property real pillShadowBlur: p.pillShadowBlur
    readonly property real pillShadowOffset: p.pillShadowOffset

    /** Bar strip. */
    readonly property real barRadius: p.barRadius
    readonly property real barBorderWidth: p.barBorderWidth
    readonly property real barHighlight: p.barHighlight
    readonly property color barBorder: p.barBorderRim > 0
        ? Qt.rgba(1, 1, 1, p.barBorderRim)
        : Qt.rgba(0, 0, 0, 0)

    /** Motion, before `Motion` applies the reduce-motion and speed flags. */
    readonly property int motionFast: p.motionFast
    readonly property int motionStandard: p.motionStandard
    readonly property int motionMorph: p.motionMorph
    readonly property int motionShapeshift: p.motionShapeshift
    readonly property int motionGlide: p.motionGlide
    readonly property int motionHeat: p.motionHeat
    readonly property int motionPulse: p.motionPulse
    readonly property bool motionLiquid: p.motionLiquid
    readonly property var motionCurve: p.motionCurve

    /** The settings app's own animation budget. */
    readonly property int appFast: p.appFast
    readonly property int appNormal: p.appNormal
    readonly property int appWindow: p.appWindow

    /** Linear blend, shared by the surface functions below. */
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1);
    }

    /** Perceived lightness, used to choose a glass opacity that keeps ink readable. */
    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    /**
     * A surface in the current style.
     *
     * `kind` is "surface" (the pill body), "card" (a card on it) or "tile" (a
     * small control). Glass needs a slightly stronger tint on cards than on the
     * wide pill body, and a dark surface needs a little more opacity than a
     * light one before cream ink reads over a blurred wallpaper.
     */
    function surface(base, kind) {
        if (root.p.glass) {
            var lighten = kind === "card" ? 0.08 : (kind === "tile" ? 0.06 : 0.05);
            var tinted = root.mix(base, Qt.rgba(1, 1, 1, 1), lighten);
            var alpha = kind === "window" ? root.p.glassAlphaWindow
                : (kind === "card" ? root.p.glassAlphaCard : root.p.glassAlpha);
            if (root.luminance(tinted) < 0.42)
                alpha = Math.min(0.82, alpha + 0.06);
            return Qt.rgba(tinted.r, tinted.g, tinted.b, alpha);
        }
        if (root.p.tonal) {
            var amount = kind === "card" ? root.p.accentMixCard
                : (kind === "tile" ? root.p.accentMixTile : root.p.accentMixSurface);
            return root.mix(base, ColorScheme.vermLit, amount);
        }
        return base;
    }

    /** The bar's backdrop, in the current style. */
    function barSurface(base) {
        if (String(base) === "transparent" || base.a <= 0)
            return Qt.rgba(0, 0, 0, 0);
        if (root.p.glass) {
            var tinted = root.mix(base, Qt.rgba(1, 1, 1, 1), 0.05);
            return Qt.rgba(tinted.r, tinted.g, tinted.b, 0.72);
        }
        if (root.p.tonal)
            return root.mix(base, ColorScheme.vermLit, 0.12);
        return base;
    }

    /** The bar's top stop: a touch lighter on glass, a touch more accent on Material. */
    function barTop(base) {
        if (String(base) === "transparent" || base.a <= 0)
            return Qt.rgba(0, 0, 0, 0);
        if (root.p.glass)
            return root.barSurface(root.mix(base, Qt.rgba(1, 1, 1, 1), 0.09));
        if (root.p.tonal)
            return root.mix(root.barSurface(base), ColorScheme.vermLit, 0.06);
        return root.barSurface(base);
    }

    /** The bar's bottom stop: slightly darker on glass, slightly deeper on Material. */
    function barBottom(base) {
        if (String(base) === "transparent" || base.a <= 0)
            return Qt.rgba(0, 0, 0, 0);
        if (root.p.glass)
            return root.barSurface(root.mix(base, Qt.rgba(0, 0, 0, 1), 0.05));
        if (root.p.tonal)
            return root.mix(root.barSurface(base), Qt.rgba(0, 0, 0, 1), 0.04);
        return root.barSurface(base);
    }

    /** A 1px light-catching edge on a glass strip. */
    readonly property color barSheen: root.p.barHighlight > 0
        ? Qt.rgba(1, 1, 1, root.p.barHighlight)
        : Qt.rgba(0, 0, 0, 0)

    /** A surface's outline. */
    function borderColor(base) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, root.p.borderRim);
        if (root.p.tonal)
            return Qt.rgba(ColorScheme.vermLit.r, ColorScheme.vermLit.g,
                           ColorScheme.vermLit.b, root.p.borderAccent);
        return base;
    }

    /** The bright line along a surface's top edge. */
    function sheenColor(base) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, root.p.sheen);
        if (root.p.tonal)
            return Qt.rgba(0, 0, 0, 0);
        return base;
    }

    /** A small control fill: the segmented chip, toggle track, search field. */
    function control(base) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, 0.09);
        if (root.p.tonal)
            return root.mix(base, ColorScheme.vermLit, 0.10);
        return base;
    }

    /** Glass specular overlay alpha, used by the pill and the settings panel. */
    readonly property real specularAlpha: root.p.specular
}

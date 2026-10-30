pragma Singleton
import QtQuick
import Quickshell
import qs.services
import "../utils/settings/style.js" as Spec

/**
 * The shell's design-language tokens.
 *
 * `Flags.style` picks one of the profiles in `utils/settings/style.js`. Two are
 * offered in Settings — Washi (the original paper-flat look) and Material
 * (Google's tonal Material 3 / Material You) — while the table also carries a
 * Liquid Glass profile for a later pass. The profile owns shape, surface
 * treatment, outlines, shadows and motion — never the palette. A style can be
 * worn with any palette mode, so "Material" on a static scheme is still
 * Material's tonal surface treatment, while "Dynamic" is still the
 * wallpaper-derived colour ramp.
 *
 * Material is not Washi with a tint. It carries a real Material 3 role set:
 *
 *   - a tonal surface-container ladder (lowest → highest) generated from the
 *     accent's hue at a capped chroma, or read straight from the generated
 *     palette when one is live;
 *   - primary / on-primary / primary-container / secondary-container and the
 *     on-surface inks that sit on them;
 *   - outline and outline-variant, used as quiet dividers instead of borders;
 *   - the four M3 interaction state layers (hover, focus, pressed, selected);
 *   - a 4 dp spacing scale, full-round shapes and emphasized motion.
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
    property bool transitioning: false
    property bool initialized: false
    readonly property int transitionDuration: Math.round(420
        * (Flags.reduceMotion ? 0.45 : 1)
        * Math.max(0.1, Flags.motionSpeed))

    Component.onCompleted: initialized = true
    onNameChanged: {
        if (!initialized)
            return;
        transitioning = true;
        transitionTimer.restart();
    }

    Timer {
        id: transitionTimer
        interval: root.transitionDuration
        onTriggered: root.transitioning = false
    }

    /** True when the live palette is a light Material scheme. */
    readonly property bool light: ColorScheme.dyn ? Dyn.light : false

    /** Shape scale. */
    readonly property real radiusCard: p.radiusCard
    readonly property real radiusRow: p.radiusRow
    readonly property real radiusChip: p.radiusChip
    readonly property real radiusField: p.radiusField
    readonly property real radiusTile: p.radiusTile
    readonly property real radiusSmall: p.radiusSmall

    /** 4 dp spacing scale. */
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32

    /** Surface material. */
    readonly property real borderWidth: p.borderWidth
    readonly property real specular: p.specular
    readonly property real shadowOpacity: p.shadowOpacity
    readonly property real shadowBlur: p.shadowBlur
    readonly property real shadowOffset: p.shadowOffset

    /** M3 interaction state layers, ready for `Theme`. */
    readonly property color stateHover: root.tonal
        ? Qt.rgba(root.onSurface.r, root.onSurface.g, root.onSurface.b, p.stateHover)
        : ColorScheme.frameBg
    readonly property color stateFocus: root.tonal
        ? Qt.rgba(root.onSurface.r, root.onSurface.g, root.onSurface.b, p.stateFocus)
        : ColorScheme.frameBg
    readonly property color statePressed: root.tonal
        ? Qt.rgba(root.onSurface.r, root.onSurface.g, root.onSurface.b, p.statePressed)
        : Qt.rgba(ColorScheme.cream.r, ColorScheme.cream.g, ColorScheme.cream.b, 0.10)
    readonly property color stateSelected: root.tonal
        ? Qt.rgba(root.primary.r, root.primary.g, root.primary.b, p.stateSelected)
        : Qt.rgba(ColorScheme.vermLit.r, ColorScheme.vermLit.g, ColorScheme.vermLit.b, 0.16)

    /**
     * The M3 colour roles. On Washi these deliberately land on the scheme tokens
     * the shell already painted with, so a component can name a role without
     * changing the paper look.
     */
    readonly property color primary: ColorScheme.vermLit
    readonly property color onPrimary: root.light
        ? "#ffffff"
        : (root.tonal ? Qt.hsla(root.hue(), 0.32, 0.11, 1) : ColorScheme.tileBg)
    readonly property color primaryContainer: root.tonal
        ? root.mix(root.surfaceContainer, root.primary, 0.22)
        : ColorScheme.vermDeep
    readonly property color onPrimaryContainer: root.tonal
        ? (root.light ? root.mix(root.primary, "#000000", 0.45)
                      : root.mix(root.primary, "#ffffff", 0.62))
        : ColorScheme.bright
    readonly property color secondaryContainer: root.tonal
        ? root.mix(root.surfaceContainerHigh, root.primary, 0.14)
        : ColorScheme.ghost
    readonly property color onSecondaryContainer: ColorScheme.cream
    readonly property color onSurface: ColorScheme.cream
    readonly property color onSurfaceVariant: ColorScheme.dim
    readonly property color outline: root.tonal
        ? Qt.hsla(root.hue(), root.chroma() * 0.65, root.light ? 0.52 : 0.44, 1)
        : ColorScheme.border
    readonly property color outlineVariant: root.tonal
        ? Qt.hsla(root.hue(), root.chroma() * 0.45, root.light ? 0.80 : 0.27, 1)
        : ColorScheme.border
    readonly property color error: ColorScheme.error

    /**
     * The Material 3 surface-container ladder. Dark tones follow the published
     * M3 neutral steps (lowest ≈ 4 % through highest ≈ 22 %), light tones run
     * from 100 % down to 90 %. Dynamic palettes already publish these steps, so
     * they are read from `Dyn` when one is live rather than regenerated.
     */
    readonly property color surfaceContainerLowest: roleSurface("lowest")
    readonly property color surfaceContainerLow: roleSurface("low")
    readonly property color surfaceContainer: roleSurface("container")
    readonly property color surfaceContainerHigh: roleSurface("high")
    readonly property color surfaceContainerHighest: roleSurface("highest")
    readonly property color surfaceDim: roleSurface("dim")
    readonly property color surfaceBright: roleSurface("bright")

    /**
     * The live surface tokens, ready for `Theme` to expose.
     *
     * `cardTop` is the pill body and the settings cards, `cardBot` its lower
     * gradient stop, and `tileBg` the small-control surface. They are computed
     * from `ColorScheme` here so a wallpaper change and a style change are the
     * same kind of update to every consumer.
     */
    readonly property color cardTop: surface(ColorScheme.cardTop, "surface")
    readonly property color cardBot: surface(ColorScheme.cardBot, "low")
    readonly property color tileBg: surface(ColorScheme.tileBg, "tile")
    readonly property color border: borderColor(ColorScheme.border)
    readonly property color sheen: sheenColor(ColorScheme.sheen)

    /** Quiet dividers and state washes. */
    readonly property color hair: root.tonal
        ? Qt.rgba(root.outlineVariant.r, root.outlineVariant.g, root.outlineVariant.b, p.dividerAlpha)
        : ColorScheme.hair
    readonly property color hairSoft: root.tonal
        ? Qt.rgba(root.outlineVariant.r, root.outlineVariant.g, root.outlineVariant.b, p.dividerSoftAlpha)
        : ColorScheme.hairSoft
    readonly property color frameBg: root.tonal ? root.stateHover : ColorScheme.frameBg
    readonly property color frameBorder: root.tonal
        ? Qt.rgba(root.outline.r, root.outline.g, root.outline.b, 0.18)
        : ColorScheme.frameBorder
    readonly property color capsule: root.tonal ? root.surfaceContainerHighest : ColorScheme.capsule
    readonly property color capsuleBorder: root.tonal
        ? Qt.rgba(root.outline.r, root.outline.g, root.outline.b, 0.35)
        : ColorScheme.capsuleBorder
    readonly property color ghost: root.tonal ? root.secondaryContainer : ColorScheme.ghost
    readonly property color trackBg: root.tonal
        ? Qt.rgba(root.onSurface.r, root.onSurface.g, root.onSurface.b, p.trackAlpha)
        : ColorScheme.trackBg
    readonly property color creamMenu: ColorScheme.creamMenu

    /** Pill body. */
    readonly property real pillBorderWidth: p.pillBorderWidth
    readonly property real pillShadowOpacity: p.pillShadowOpacity
    readonly property real pillShadowBlur: p.pillShadowBlur
    readonly property real pillShadowOffset: p.pillShadowOffset

    /** The pill's rest and open corner scales. */
    function pillCorner(base) { return base * p.pillCornerScale }
    function pillOpenCorner(base) { return base * p.pillOpenScale }

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

    /** The accent's hue, safe for a greyscale accent. */
    function hue() {
        var c = ColorScheme.vermLit;
        return c.hslHue < 0 ? 0 : c.hslHue;
    }

    /** The accent's chroma, capped by the profile so surfaces stay neutral. */
    function chroma() {
        return Math.max(0, Math.min(ColorScheme.vermLit.hslSaturation, p.chromaCap));
    }

    /** One rung of the generated M3 neutral ladder. */
    function tone(lightness) {
        return Qt.hsla(root.hue(), root.chroma(), lightness, 1);
    }

    /** A surface-container role in the current style. */
    function roleSurface(role) {
        if (root.p.glass) {
            switch (role) {
            case "lowest": return ColorScheme.tileBg;
            case "low": return ColorScheme.capsule;
            case "highest": return ColorScheme.ghost;
            default: return ColorScheme.cardTop;
            }
        }
        if (!root.p.tonal) {
            switch (role) {
            case "lowest": return ColorScheme.tileBg;
            case "low": return ColorScheme.capsule;
            case "container": return ColorScheme.cardTop;
            case "high": return ColorScheme.cardTop;
            case "highest": return ColorScheme.ghost;
            case "dim": return ColorScheme.tileBg;
            case "bright": return ColorScheme.cardTop;
            }
            return ColorScheme.cardTop;
        }
        if (ColorScheme.dyn) {
            switch (role) {
            case "lowest": return Dyn.surface;
            case "low": return Dyn.surfaceContainerLow;
            case "container": return Dyn.surfaceContainer;
            case "high": return Dyn.surfaceContainerHigh;
            case "highest": return Dyn.surfaceContainerHighest;
            case "dim": return Dyn.surfaceContainerLow;
            case "bright": return Dyn.surfaceContainerHighest;
            }
            return Dyn.surfaceContainer;
        }
        switch (role) {
        case "lowest": return root.tone(root.light ? 1.00 : 0.045);
        case "low": return root.tone(root.light ? 0.96 : 0.075);
        case "container": return root.tone(root.light ? 0.94 : 0.10);
        case "high": return root.tone(root.light ? 0.92 : 0.135);
        case "highest": return root.tone(root.light ? 0.90 : 0.17);
        case "dim": return root.tone(root.light ? 0.87 : 0.06);
        case "bright": return root.tone(root.light ? 1.00 : 0.235);
        }
        return root.tone(root.light ? 0.94 : 0.10);
    }

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
     * light one before cream ink reads over a blurred wallpaper. Material
     * resolves the kind to a role in the tonal container ladder; Washi returns
     * the scheme colour untouched.
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
            switch (kind) {
            case "window": return root.surfaceContainerLow;
            case "card": return root.surfaceContainerHigh;
            case "tile": return root.surfaceContainerHighest;
            case "lowest": return root.surfaceContainerLowest;
            case "low": return root.surfaceContainerLow;
            case "high": return root.surfaceContainerHigh;
            case "highest": return root.surfaceContainerHighest;
            }
            return root.surfaceContainer;
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
            return root.mix(base, root.primary, 0.10);
        return base;
    }

    /** The bar's top stop: a touch lighter on glass, a touch more accent on Material. */
    function barTop(base) {
        if (String(base) === "transparent" || base.a <= 0)
            return Qt.rgba(0, 0, 0, 0);
        if (root.p.glass)
            return root.barSurface(root.mix(base, Qt.rgba(1, 1, 1, 1), 0.09));
        if (root.p.tonal)
            return root.mix(root.barSurface(base), root.primary, 0.06);
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

    /**
     * A surface's outline. Material keeps it quiet — tonal separation does the
     * work, and the outline is a low-alpha neutral rather than an accent line.
     */
    function borderColor(base) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, root.p.borderRim);
        if (root.p.tonal)
            return Qt.rgba(root.outline.r, root.outline.g, root.outline.b, 0.42);
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
            return root.surfaceContainerHighest;
        return base;
    }

    /** Glass specular overlay alpha, used by the pill and the settings panel. */
    readonly property real specularAlpha: root.p.specular
}

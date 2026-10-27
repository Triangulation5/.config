.pragma library

/**
 * The three design languages the shell can wear.
 *
 * A style is a *shape and material* profile, not a palette: the palette flags
 * (static / dynamic / accented / manual, and the colour scheme underneath)
 * decide what colours a surface is made of, while this table decides what the
 * surface is made of — how round it is, whether it is opaque paper, tinted
 * Material, or translucent glass, how it is outlined, how it casts a shadow,
 * and how it moves.
 *
 * Washi is the shell's original look and deliberately carries the old numbers
 * verbatim. Every consumer treats `washi` as the identity profile, so adding
 * this file changes nothing until another style is picked.
 *
 * Liquid Glass is Apple's iOS 26 / macOS Tahoe 26 material: translucent layers
 * that blur what is behind them, a light-catching rim, a specular sheen, a
 * deeper adaptive shadow, continuous large radii, and springy, gel-like motion.
 * A desktop shell cannot reproduce real lensing, so the profile states the
 * parts that *can* be stated in QML and Hyprland: alpha + compositor blur,
 * rim light, specular gradient, and overshooting motion.
 *
 * Material You is Google's Material 3 (Expressive) language: opaque tonal
 * surfaces tinted from the accent, no decorative outline or gloss, full-round
 * shapes, and expressive motion with a slight settle. On a dynamic palette the
 * shell already has the Material colour roles; on a static one the profile
 * tints the curated surface itself so the style still reads.
 *
 * Durations are the unmultiplied base values; Motion and the settings app
 * scale them by the user's reduce-motion and speed flags.
 */
var profiles = {
    "washi": {
        name: "washi",
        label: "Washi",
        description: "Flat paper surfaces, hairline rules and restrained motion — the shell's original look.",
        glass: false,
        tonal: false,

        radiusCard: 14,
        radiusRow: 10,
        radiusChip: 7,
        radiusField: 10,
        radiusTile: 13,
        radiusSmall: 7,

        /** The accent mixed into opaque surfaces. Washi uses the palette as-is. */
        accentMixCard: 0.0,
        accentMixSurface: 0.0,
        accentMixTile: 0.0,
        /** Extra lightness mixed into a glass surface before it is made translucent. */
        glassLighten: 0.0,
        /** Opacity of a glass surface over the blurred backdrop. */
        glassAlpha: 1.0,
        /** A window/card on a glass desktop is a touch more opaque than the pill. */
        glassAlphaCard: 1.0,
        glassAlphaWindow: 1.0,

        borderWidth: 1,
        borderRim: 0.0,
        borderAccent: 0.0,
        specular: 0.0,
        sheen: 0.0,

        shadowOpacity: 0.50,
        shadowBlur: 0.70,
        shadowOffset: 3.0,

        barRadius: 0,
        barBorderWidth: 0,
        barBorderRim: 0.0,
        barHighlight: 0.0,

        pillBorderWidth: 1,
        pillShadowOpacity: 0.50,
        pillShadowBlur: 0.70,
        pillShadowOffset: 3.0,

        motionFast: 140,
        motionStandard: 300,
        motionMorph: 420,
        motionShapeshift: 820,
        motionGlide: 260,
        motionHeat: 1100,
        motionPulse: 420,
        motionLiquid: false,
        motionCurve: [0.16, 1.00, 0.30, 1.00, 1.00, 1.00],
        appFast: 120,
        appNormal: 150,
        appWindow: 220
    },

    "liquid-glass": {
        name: "liquid-glass",
        label: "Liquid Glass",
        description: "Translucent glass that blurs the wallpaper, with a bright rim, specular sheen and springy motion — Apple's iOS 26 / macOS Tahoe language.",
        glass: true,
        tonal: false,

        radiusCard: 24,
        radiusRow: 16,
        radiusChip: 11,
        radiusField: 16,
        radiusTile: 18,
        radiusSmall: 8,

        accentMixCard: 0.0,
        accentMixSurface: 0.0,
        accentMixTile: 0.0,
        glassLighten: 0.07,
        glassAlpha: 0.74,
        glassAlphaCard: 0.78,
        glassAlphaWindow: 0.72,

        borderWidth: 1,
        borderRim: 0.22,
        borderAccent: 0.0,
        specular: 0.16,
        sheen: 0.34,

        shadowOpacity: 0.74,
        shadowBlur: 1.30,
        shadowOffset: 8.0,

        barRadius: 18,
        barBorderWidth: 1,
        barBorderRim: 0.20,
        barHighlight: 0.22,

        pillBorderWidth: 1,
        pillShadowOpacity: 0.74,
        pillShadowBlur: 1.35,
        pillShadowOffset: 8.0,

        motionFast: 170,
        motionStandard: 320,
        motionMorph: 520,
        motionShapeshift: 720,
        motionGlide: 300,
        motionHeat: 900,
        motionPulse: 800,
        motionLiquid: true,
        motionCurve: [0.20, 1.18, 0.34, 1.00, 1.00, 1.00],
        appFast: 160,
        appNormal: 260,
        appWindow: 320
    },

    "material-you": {
        name: "material-you",
        label: "Material You",
        description: "Tonal Material 3 surfaces tinted from the accent, full-round shapes and expressive motion — Google's dynamic-colour language.",
        glass: false,
        tonal: true,

        radiusCard: 20,
        radiusRow: 14,
        radiusChip: 12,
        radiusField: 18,
        radiusTile: 16,
        radiusSmall: 10,

        accentMixCard: 0.11,
        accentMixSurface: 0.055,
        accentMixTile: 0.08,
        glassLighten: 0.0,
        glassAlpha: 1.0,
        glassAlphaCard: 1.0,
        glassAlphaWindow: 1.0,

        borderWidth: 1,
        borderRim: 0.0,
        borderAccent: 0.20,
        specular: 0.0,
        sheen: 0.0,

        shadowOpacity: 0.38,
        shadowBlur: 0.85,
        shadowOffset: 4.0,

        barRadius: 20,
        barBorderWidth: 0,
        barBorderRim: 0.0,
        barHighlight: 0.0,

        pillBorderWidth: 0,
        pillShadowOpacity: 0.38,
        pillShadowBlur: 0.85,
        pillShadowOffset: 4.0,

        motionFast: 150,
        motionStandard: 280,
        motionMorph: 460,
        motionShapeshift: 760,
        motionGlide: 280,
        motionHeat: 1000,
        motionPulse: 380,
        motionLiquid: false,
        motionCurve: [0.18, 1.10, 0.32, 1.00, 1.00, 1.00],
        appFast: 130,
        appNormal: 200,
        appWindow: 280
    }
}

/** The profile for `name`, falling back to Washi for an unknown value. */
function profile(name) {
    return profiles[name] || profiles["washi"]
}

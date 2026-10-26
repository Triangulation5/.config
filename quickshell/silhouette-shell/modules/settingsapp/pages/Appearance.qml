pragma Singleton

import QtQuick
import "../utils/rows.js" as Rows

/**
 * Appearance: the palette the whole rice is tinted from, the UI font and scale,
 * the now-playing backdrop and the aura that follows it, and the two paths the
 * shell reads for media backdrops and wallpapers.
 *
 * Mode is the switch that matters: static keeps the curated set, while dynamic
 * and manual hand the job to the wallpaper palette, which is also what re-tints
 * this window (see config/Theme.qml). Accented sits between them: it keeps the
 * selected static scheme's surfaces and text and takes only the accent from the
 * wallpaper, so the theme someone tuned stays put while the highlights follow
 * the image. The scheme row above it only decides *which* curated set static
 * paints — the vague.nvim port or the shell's original one — so it does nothing
 * on Dynamic and Manual; Accented keeps it as the body its wallpaper accent
 * sits on, which is the point of that mode.
 *
 * Dynamic is Material You. Its options are the generation controls: the M3
 * scheme variant (the nine caelestia and DMS both list, plus Auto), matugen's
 * contrast level, Auto/Light/Dark (Auto is matugen's `smart`, which reads the
 * wallpaper), which colour matugen prefers when an image offers several, the
 * M3 role the base surface sits on, and how saturated the containers are. They
 * write flags only; the shell's Dyn watcher regenerates the palette and this
 * window re-tints from the same colors.json it already reads. Accented shares
 * the accent-producing four (scheme, contrast, preferred colour, container
 * saturation); Appearance and Surface role belong to Dynamic alone, because
 * Accented keeps the static surfaces and always asks for the dark-scheme accent
 * that reads on them.
 *
 * The aura is a card of its own rather than three rows under the backdrop,
 * because it is the one group here that is a *shape* of another setting: the
 * backdrop mode sets whether it can run at all, and these three only decide how
 * far it reaches and whether it tints the shadow. Sitting in the same card read
 * as four peers, and the mode's veto on all of them was invisible.
 *
 * The aura ships off: the backdrop is the effect, and the bleed around the pill
 * is an addition someone opts into, not part of the default look.
 *
 * A row for a field the shell's own Appearance surface edits states only what
 * this page alone decides about it — the editor, the label, the caption, the unit
 * — and takes its bounds, choices and default from the table shared with that
 * surface (`utils/settings/fields.js`, read through `row()` below). Aura and
 * wallpaper are this page's alone, so they state their own.
 */
QtObject {
    readonly property string name: "Appearance"
    readonly property string icon: "\u25D0"
    readonly property string keywords: "theme colour color palette scheme colorscheme wallpaper font scale ui tint backdrop media aura glow shadow strength"

    /** One row for a flag, its bounds read from the shared table (see utils/rows.js). */
    function row(field, type, label, caption, unit, extra) {
        return Rows.flag(field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        { card: "Palette", rows: [
            row("colorScheme", "segmented", "Colorscheme",
                "Which static palette the shell paints from — the vague.nvim port, or the original black-bodied one. Static mode, and the body Accented puts wallpaper accents on", ""),
            row("paletteMode", "segmented", "Mode", "Static washi, full wallpaper colours, wallpaper accents on the static theme, or pick a hue", ""),
            row("manualHue", "slider", "Hue", "", "\u00B0"),
            row("manualSat", "slider", "Saturation", "", "%", { displayScale: 100 }),
            row("manualDark", "toggle", "Dark accent", "Dark instead of light accent tones in manual mode", "")
        ]},
        /**
         * Dynamic is the Material You path: these are generation options, not
         * palette tokens, so they only mean anything while Mode above is
         * Dynamic. The card stays visible on the other modes and the captions
         * say so, matching how the Colorscheme row above describes its own
         * static-only reach rather than disappearing.
         */
        { card: "Material You \u00B7 Dynamic", rows: [
            row("dynamicScheme", "select", "Scheme",
                "Auto picks a Material 3 variant from the wallpaper's colourfulness; tonal spot is Google's default, vibrant and expressive push chroma, neutral and monochrome drain it. Dynamic and Accented modes", ""),
            row("dynamicMode", "segmented", "Appearance",
                "Auto reads light or dark from the wallpaper; Light and Dark force one. Dynamic mode only — Accented always keeps the dark-scheme accent for the static dark theme", ""),
            row("dynamicContrast", "slider", "Contrast",
                "Material's -100% to 100% contrast level. Positive separates text and surfaces further; Dynamic and Accented modes",
                "%", { displayScale: 100 }),
            row("dynamicPrefer", "select", "Wallpaper accent",
                "Which colour matugen takes when the wallpaper offers several: the most saturated, the lightest, the darkest, or the highest value. Dynamic and Accented modes", ""),
            row("surfaceRole", "select", "Surface role",
                "Which Material 3 role the shell's base surface sits on. Default is the neutral elevation ramp; a container role tints the window and its text is rebuilt from that role's own ink. Dynamic mode only — Accented keeps the static surfaces", ""),
            row("containerSaturation", "slider", "Container saturation",
                "Chroma on the surface and accent containers: flat grey at 0%, the vague-tuned default at 100%, Material's own tint at 200%. Dynamic and Accented modes",
                "%", { displayScale: 100 })
        ]},
        { card: "Typography & scale", rows: [
            row("uiFont", "text", "UI font", "Font family for every surface", "", { placeholder: "Inter" }),
            row("uiScale", "slider", "UI scale", "", "%", { displayScale: 100 })
        ]},
        { card: "Media backdrop", rows: [
            row("mediaStyle", "segmented", "Now-playing backdrop",
                "Blurred album-art bleed, the warm wash, or fully transparent", "")
        ]},
        /**
         * The aura card is the one group here that answers to another row: the
         * backdrop above has to be something other than None for any of these
         * to do anything, and its own capture says so.
         */
        { card: "Ambient aura", rows: [
            { key: "auraOn", type: "toggle", label: "Ambient aura",
              caption: "Cover colour bleeds around the rest pill. Off by default", reset: false },
            { key: "auraStrength", type: "slider", label: "Aura strength", min: 0, max: 2, step: 0.05,
              caption: "Scales the backdrop mode's own strength — full on Bleed, a whisper on Wash",
              displayScale: 100, unit: "%", reset: 1.0 },
            { key: "auraShadow", type: "toggle", label: "Aura shadow",
              caption: "Darkens the pill's shadow with the cover's dominant colour", reset: true }
        ]},
        { card: "Wallpaper", rows: [
            { key: "wallpaperDir", type: "text", label: "Folder", placeholder: "~/Pictures",
              caption: "Folder the picker reads and downloads land in. A leading ~ is expanded. Empty auto-detects ~/Pictures, then ~/Pictures/rice-wallpapers or ~/Pictures/Wallpapers",
              reset: "" }
        ]}
    ]
}

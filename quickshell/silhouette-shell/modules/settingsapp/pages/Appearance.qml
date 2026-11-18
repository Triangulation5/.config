pragma Singleton

import QtQuick
import "../../../utils/settings/rows.js" as Rows

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
    readonly property string keywords: "theme colour color design style washi material material-you palette scheme colorscheme wallpaper font scale ui tint backdrop media aura glow shadow strength"

    /** One row for a flag, its bounds read from the shared table (see utils/settings/rows.js). */
    function row(field, type, label, caption, unit, extra) {
        return Rows.flag(field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        /**
         * The design language is its own card rather than the first row under
         * Palette because it is not a palette choice: it decides the shape,
         * material, outlines and motion every surface wears, and it holds while
         * the colours underneath change. Keeping it separate also makes the
         * vocabulary clear — Washi and Material are styles, Static and Dynamic
         * are palettes.
         */
        { card: "Design language", rows: [
            row("style", "segmented", "Design style",
                "Washi: flat identity. Material: Material 3. Applies shell-wide.", "")
        ]},
        { card: "Palette", rows: [
            row("colorScheme", "segmented", "Colorscheme",
                "Select static palette: vague.nvim or shell original. Used in Static and Accented modes.", ""),
            row("paletteMode", "segmented", "Mode", "Static, wallpaper-based colors, or custom hue.", ""),
            row("manualHue", "slider", "Hue", "", "\u00B0"),
            row("manualSat", "slider", "Saturation", "", "%", { displayScale: 100 }),
            row("manualDark", "toggle", "Dark accent", "Use dark accent tones in manual mode.", "")
        ]},
        { card: "Material You \u00B7 Dynamic", rows: [
            row("dynamicScheme", "select", "Scheme",
                "Auto: wallpaper-based variant. Other options: Material 3 variants.", ""),
            row("dynamicMode", "segmented", "Appearance",
                "Force Light/Dark mode. Auto matches wallpaper.", ""),
            row("dynamicContrast", "slider", "Contrast",
                "Adjust accent contrast (-100% to 100%).",
                "%", { displayScale: 100 }),
            row("dynamicPrefer", "select", "Wallpaper accent",
                "Accent source: saturated, light, dark, or value.", ""),
            row("surfaceRole", "select", "Surface role",
                "Base surface elevation ramp. Container roles tint the window.", ""),
            row("containerSaturation", "slider", "Container saturation",
                "Surface and accent container chroma (0%–200%).",
                "%", { displayScale: 100 })
        ]},
        { card: "Typography & scale", rows: [
            row("uiFont", "text", "UI font", "Shell surface font family.", "", { placeholder: "Inter" }),
            row("uiScale", "slider", "UI scale", "", "%", { displayScale: 100 })
        ]},
        { card: "Media backdrop", rows: [
            row("mediaStyle", "segmented", "Now-playing backdrop",
                "Art blur, warm wash, or transparent.", "")
        ]},
        { card: "Ambient aura", rows: [
            { key: "auraOn", type: "toggle", label: "Ambient aura",
              caption: "Cover color bleed around the pill.", reset: false },
            { key: "auraStrength", type: "slider", label: "Aura strength", min: 0, max: 2, step: 0.05,
              caption: "Adjust intensity of blur/wash effect.",
              displayScale: 100, unit: "%", reset: 1.0 },
            { key: "auraShadow", type: "toggle", label: "Aura shadow",
              caption: "Tint pill shadow with cover color.", reset: true }
        ]},
        { card: "Wallpaper", rows: [
            { key: "wallpaperDir", type: "text", label: "Folder", placeholder: "~/Pictures",
              caption: "Wallpaper directory. Defaults to ~/Pictures.",
              reset: "" }
        ]}
    ]
}

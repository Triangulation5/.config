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
 * this window (see config/Theme.qml).
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
    readonly property string keywords: "theme colour color palette wallpaper font scale ui tint backdrop media aura glow shadow strength"

    /** One row for a flag, its bounds read from the shared table (see utils/rows.js). */
    function row(field, type, label, caption, unit, extra) {
        return Rows.flag(field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        { card: "Palette", rows: [
            row("paletteMode", "segmented", "Mode", "Static washi, live wallpaper colours, or pick a hue", ""),
            row("manualHue", "slider", "Hue", "", "\u00B0"),
            row("manualSat", "slider", "Saturation", "", "%", { displayScale: 100 }),
            row("manualDark", "toggle", "Dark accent", "Dark instead of light accent tones in manual mode", "")
        ]},
        { card: "Typography & scale", rows: [
            row("uiFont", "text", "UI font", "Font family for every surface", "", { placeholder: "Inter" }),
            row("uiScale", "slider", "UI scale", "", "%", { displayScale: 100 })
        ]},
        { card: "Media backdrop", rows: [
            row("mediaStyle", "segmented", "Now-playing backdrop",
                "Blurred album-art bleed, the warm wash, or fully transparent", "")
        ]},
        // The aura card is the one group here that answers to another row: the
        // backdrop above has to be something other than None for any of these to
        // do anything, and its own capture says so.
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

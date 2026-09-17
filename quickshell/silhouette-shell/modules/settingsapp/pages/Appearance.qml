pragma Singleton

import QtQuick

/**
 * Appearance: the palette the whole rice is tinted from, the UI font and scale,
 * and the two paths the shell reads for media backdrops and wallpapers.
 *
 * Mode is the switch that matters: static keeps the curated set, while dynamic
 * and manual hand the job to the wallpaper palette, which is also what re-tints
 * this window (see config/Theme.qml).
 */
QtObject {
    readonly property string name: "Appearance"
    readonly property string icon: "\u25D0"
    readonly property string caption: "Palette, font, scale, wallpapers"
    readonly property string keywords: "theme colour color palette wallpaper font scale ui tint backdrop media"

    readonly property var groups: [
        { card: "Palette", rows: [
            { key: "paletteMode", type: "segmented", label: "Mode",
              caption: "Static washi, live wallpaper colours, or pick a hue",
              options: ["static", "dynamic", "manual"], names: ["Static", "Dynamic", "Manual"], reset: "static" },
            { key: "manualHue", type: "slider", label: "Hue", min: 0, max: 359, step: 5, unit: "\u00B0", reset: 0 },
            { key: "manualSat", type: "slider", label: "Saturation", min: 0, max: 1, step: 0.05,
              displayScale: 100, unit: "%", reset: 0.5 },
            { key: "manualDark", type: "toggle", label: "Dark accent",
              caption: "Dark instead of light accent tones in manual mode", reset: true }
        ]},
        { card: "Typography & scale", rows: [
            { key: "uiFont", type: "text", label: "UI font", placeholder: "Inter",
              caption: "Font family for every surface", reset: "JetBrainsMono Nerd Font Mono" },
            { key: "uiScale", type: "slider", label: "UI scale", min: 0.9, max: 1.25, step: 0.05,
              displayScale: 100, unit: "%", reset: 1.1 }
        ]},
        { card: "Media backdrop", rows: [
            { key: "mediaStyle", type: "segmented", label: "Now-playing backdrop",
              caption: "Blurred album-art bleed, the warm wash, or fully transparent",
              options: ["bleed", "wash", "none"], names: ["Bleed", "Wash", "None"], reset: "bleed" },
            { key: "auraOn", type: "toggle", label: "Ambient aura",
              caption: "Cover colour bleeds around the rest pill. Runs at the backdrop's own strength, and stays off while the backdrop is None",
              reset: true },
            { key: "auraStrength", type: "slider", label: "Aura strength", min: 0, max: 2, step: 0.05,
              displayScale: 100, unit: "%", reset: 1.0 },
            { key: "auraShadow", type: "toggle", label: "Aura shadow",
              caption: "Darkens the pill's shadow with the cover's dominant colour", reset: true }
        ]},
        { card: "Wallpaper", rows: [
            { key: "wallpaperDir", type: "text", label: "Folder", placeholder: "~/Pictures",
              caption: "Folder the picker reads (empty = ~/Pictures)", reset: "" }
        ]}
    ]
}

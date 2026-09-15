pragma Singleton

import QtQuick

/**
 * The app's page model: every sidebar entry with its section (category
 * header), icon glyph and the groups of setting rows it shows. Each row
 * describes one shell flag: the Flags key, editor type, bounds/unit and the
 * macOS-System-Settings-style layout row it renders as. Pages bind through
 * Store (get/set/changed) so an edit lands in flags.json and the live shell
 * applies it instantly.
 */
QtObject {
    readonly property var sections: ["Shell", "Control"]

    readonly property var pages: [
        { id: "bar",        section: "Shell",   name: "Bar & Island",   icon: "bar",      groups: barIslandGroups },
        { id: "clock",      section: "Shell",   name: "Clock & Date",   icon: "clock",    groups: clockGroups },
        { id: "appearance", section: "Shell",   name: "Appearance",     icon: "aperture", groups: appearanceGroups },
        { id: "motion",     section: "Shell",   name: "Motion",         icon: "wave",     groups: motionGroups },
        { id: "launcher",   section: "Shell",   name: "Launcher",       icon: "command",  groups: launcherGroups },
        { id: "notify",     section: "Control", name: "Notifications",  icon: "bell",     groups: notifyGroups },
        { id: "control",    section: "Control", name: "Control Center", icon: "grid",     groups: controlGroups },
        { id: "lock",       section: "Control", name: "Lock Screen",    icon: "lock",     groups: lockGroups },
        { id: "system",     section: "Control", name: "System",         icon: "gear",     groups: systemGroups }
    ]

    // ── Bar & Island ─────────────────────────────────────────────────────
    readonly property var barIslandGroups: [
        { card: "Expanded Island", rows: [
            { key: "notchFlare", type: "slider", label: "Corner radius (expanded)", min: -8, max: 8, step: 0.25, unit: " px" },
            { key: "notchStyle", type: "toggle", label: "Status circle (battery and Wi-Fi)",
              caption: "Square-top island with flared ears instead of the pill" },
            { key: "mediaStyle", type: "toggle", label: "Album art circle while a player is open",
              caption: "On: album-art bleed backdrop behind the track" },
            { key: "topGap", type: "slider", label: "Stage lift on hover", min: 0, max: 2, step: 0.1, unit: " px" }
        ]},
        { title: "Game mode", card: "Game mode", rows: [
            { key: "gameMode", type: "toggle", label: "Game mode",
              caption: "Flat strip, no animations, no popups" },
            { key: "appGap", type: "slider", label: "Bar height", min: 0, max: 2, step: 0.1, unit: " px" },
            { key: "pillOpacity", type: "slider", label: "Cluster gap", min: 0.3, max: 1, step: 0.05, unit: " px" }
        ]}
    ]

    // ── Clock & Date ─────────────────────────────────────────────────────
    readonly property var clockGroups: [
        { card: "Clock", rows: [
            { key: "time12h", type: "toggle", label: "12-hour clock", caption: "AM/PM instead of 24-hour time" },
            { key: "clockSeconds", type: "toggle", label: "Show seconds" },
            { key: "showGlyphs", type: "toggle", label: "Japanese glyphs",
              caption: "Kanji headers and transport glyphs across the shell" }
        ]},
        { card: "Weather glance", rows: [
            { key: "weatherCity", type: "text", label: "City", placeholder: "auto",
              caption: "wttr.in city for the calendar glance (empty = auto)" }
        ]}
    ]

    // ── Appearance ───────────────────────────────────────────────────────
    readonly property var appearanceGroups: [
        { card: "Palette", rows: [
            { key: "paletteMode", type: "segmented", label: "Mode",
              caption: "Static washi, live wallpaper colours, or pick a hue",
              options: ["static", "dynamic", "manual"], names: ["Static", "Dynamic", "Manual"] },
            { key: "manualHue", type: "slider", label: "Hue (manual mode)", min: 0, max: 359, step: 5, unit: "°" },
            { key: "manualSat", type: "slider", label: "Saturation (manual mode)", min: 0, max: 1, step: 0.05, displayScale: 100, unit: "%" },
            { key: "manualDark", type: "toggle", label: "Dark accent", caption: "Dark instead of light accent tones in manual mode" }
        ]},
        { card: "Typography & scale", rows: [
            { key: "uiFont", type: "text", label: "UI font", placeholder: "Inter",
              caption: "Font family for every surface (empty = Inter)" },
            { key: "uiScale", type: "slider", label: "UI scale", min: 0.9, max: 1.25, step: 0.05, displayScale: 100, unit: "%" }
        ]},
        { card: "Media backdrop", rows: [
            { key: "mediaStyle", type: "segmented", label: "Style",
              caption: "Album art bleed, the warm wash, or none",
              options: ["bleed", "wash", "none"], names: ["Bleed", "Wash", "None"] },
            { key: "musicViz", type: "toggle", label: "Music visualizer", caption: "Spectrum bars in the rest pill" },
            { key: "vizStyle", type: "segmented", label: "Visualizer style", options: ["bars", "centered"], names: ["Bars", "Center"] },
            { key: "vizFps", type: "slider", label: "Visualizer framerate", min: 15, max: 120, step: 15, unit: " fps" }
        ]},
        { card: "Weather & files", rows: [
            { key: "wallpaperDir", type: "text", label: "Wallpaper folder", placeholder: "~/Pictures",
              caption: "Folder the picker reads (empty = ~/Pictures)" }
        ]}
    ]

    // ── Motion ───────────────────────────────────────────────────────────
    readonly property var motionGroups: [
        { card: "Animation", rows: [
            { key: "reduceMotion", type: "toggle", label: "Reduce motion",
              caption: "Trim the animation budget across the shell" },
            { key: "pillBlur", type: "toggle", label: "Pill blur", caption: "Background blur behind the pill body" },
            { key: "pillOpacity", type: "slider", label: "Pill opacity", min: 0.3, max: 1, step: 0.05, displayScale: 100, unit: "%" },
            { key: "autoHide", type: "toggle", label: "Auto hide",
              caption: "Retract the pill off the top edge until the pointer touches it" }
        ]}
    ]

    // ── Launcher ─────────────────────────────────────────────────────────
    readonly property var launcherGroups: [
        { card: "Launcher", rows: [
            { key: "vimKeys", type: "toggle", label: "Vim keys", caption: "h/j/k/l navigation in the pill menus" }
        ]}
    ]

    // ── Notifications ────────────────────────────────────────────────────
    readonly property var notifyGroups: [
        { card: "Notifications", rows: [
            { key: "dnd", type: "toggle", label: "Do not disturb", caption: "Notifications stay silent" }
        ]}
    ]

    // ── Control Center ───────────────────────────────────────────────────
    readonly property var controlGroups: [
        { card: "Night light", rows: [
            { key: "nightLightMode", type: "segmented", label: "Mode",
              caption: "Warm the screen on a schedule or always",
              options: ["off", "always", "scheduled"], names: ["Off", "Always", "Scheduled"] },
            { key: "nightLightTemp", type: "slider", label: "Temperature", min: 2500, max: 6500, step: 100, unit: " K" },
            { key: "nightLightOnMin", type: "slider", label: "On at", min: 0, max: 1439, step: 15, unit: " min" },
            { key: "nightLightOffMin", type: "slider", label: "Off at", min: 0, max: 1439, step: 15, unit: " min" }
        ]},
        { card: "Session", rows: [
            { key: "keepAwake", type: "toggle", label: "Keep awake", caption: "Inhibit idle until toggled off" }
        ]}
    ]

    // ── Lock Screen ──────────────────────────────────────────────────────
    readonly property var lockGroups: [
        { card: "Idle", rows: [
            { key: "idleLockMin", type: "slider", label: "Lock after", min: 0, max: 60, step: 1, unit: " min" },
            { key: "idleScreenOffMin", type: "slider", label: "Screen off after", min: 0, max: 60, step: 1, unit: " min" },
            { key: "idleSuspendMin", type: "slider", label: "Suspend after", min: 0, max: 120, step: 1, unit: " min" }
        ]},
        { card: "Lock screen", rows: [
            { key: "lockDotsMode", type: "segmented", label: "Password beads",
              caption: "Bead entrance animation on the lock screen",
              options: ["drop", "pulse", "gpixel"], names: ["Drop", "Pulse", "Gpixel"] }
        ]}
    ]

    // ── System ───────────────────────────────────────────────────────────
    readonly property var systemGroups: [
        { card: "Recording", rows: [
            { key: "recordCountdown", type: "slider", label: "Countdown", min: 0, max: 10, step: 1, unit: " s" },
            { key: "recordFps", type: "slider", label: "Frame rate", min: 15, max: 144, step: 15, unit: " fps" },
            { key: "recordQuality", type: "segmented", label: "Quality",
              options: ["low", "medium", "high", "ultra"], names: ["Low", "Medium", "High", "Ultra"] },
            { key: "recordCursor", type: "toggle", label: "Capture cursor" },
            { key: "recordMic", type: "toggle", label: "Microphone", caption: "Mix the mic into the recording" },
            { key: "recordDesktop", type: "toggle", label: "Desktop audio" },
            { key: "recordDir", type: "text", label: "Save folder", placeholder: "~/Videos",
              caption: "Where recordings land (empty = ~/Videos)" }
        ]}
    ]

    /** Pages whose name/caption/rows match every token of `query`. */
    function searchPages(query) {
        var q = query.trim().toLowerCase();
        if (q.length === 0)
            return null;
        var tokens = q.split(/\s+/);
        var out = [];
        for (var p = 0; p < pages.length; p++) {
            var page = pages[p];
            var hay = page.name.toLowerCase();
            var rows = [];
            for (var g = 0; g < page.groups.length; g++) {
                var grp = page.groups[g];
                var hitRows = [];
                for (var r = 0; r < grp.rows.length; r++) {
                    var row = grp.rows[r];
                    var rowHay = (row.label + " " + (row.caption || "") + " " + row.key).toLowerCase();
                    var ok = true;
                    for (var t = 0; t < tokens.length; t++)
                        if (rowHay.indexOf(tokens[t]) === -1 && hay.indexOf(tokens[t]) === -1) { ok = false; break; }
                    if (ok)
                        hitRows.push(row);
                }
                if (hitRows.length > 0)
                    rows.push({ card: grp.card, rows: hitRows });
            }
            if (rows.length > 0)
                out.push({ page: page, groups: rows });
        }
        return out;
    }
}

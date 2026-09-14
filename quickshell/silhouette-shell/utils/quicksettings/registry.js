/**
 * Quick-settings registry: every shell setting the pill can drive, described
 * once and rendered by the control center surface. The user's current live
 * values (from ~/.local/state/ricelin/flags.json) are baked in as the new
 * code defaults in Flags.qml; the descriptions here only control how each
 * setting is searched, grouped and edited.
 *
 * `key` is the Flags property. `type` picks the editor:
 *   toggle — boolean flip;      seg — cycle through `vals`;
 *   int    — stepped scrub over `min`/`max`/`step` (optional `unit`; optional
 *            `scale` to show a fraction as a percent, e.g. saturation);
 *   text   — free text field (`placeholder` when empty).
 *
 * `group`/`sub` shape the default (unsearched) browse order; `label`,
 * `caption` and the optional `terms` list feed the search index, so a query
 * like "warm" finds Night light without its name containing it. Keep the
 * file dependency-free: it must parse as both QML's JS engine and a lint.
 */

var registry = [
    // ── Shell · Look ────────────────────────────────────────────────────
    { key: "paletteMode", type: "seg", group: "Look", label: "Palette",
      caption: "Static washi, live wallpaper colours, or pick a hue",
      vals: ["static", "dynamic", "manual"],
      names: ["Static", "Dynamic", "Manual"], terms: ["theme", "color", "colour", "accent", "matugen", "wallpaper", "hue"] },
    { key: "uiFont", type: "text", group: "Look", label: "UI font",
      caption: "Font family for every surface (empty = Inter)",
      placeholder: "Inter", terms: ["typeface", "family", "text", "inter"] },
    { key: "uiScale", type: "seg", group: "Look", label: "UI scale",
      vals: [0.9, 1.0, 1.1, 1.25], names: ["90%", "100%", "110%", "125%"],
      terms: ["size", "zoom", "bigger", "smaller"] },
    { key: "mediaStyle", type: "seg", group: "Look", label: "Media backdrop",
      caption: "Album art bleed over the wallpaper tint, the warm wash, or none",
      vals: ["bleed", "wash", "none"], names: ["Bleed", "Wash", "None"],
      terms: ["album", "cover", "music", "now playing", "card"] },
    { key: "vizStyle", type: "seg", group: "Look", label: "Visualizer style",
      caption: "Rest-pill spectrum renderer",
      vals: ["bars", "centered"], names: ["Bars", "Center"],
      terms: ["cava", "spectrum", "eq", "wave", "music bars"] },
    { key: "vizFps", type: "int", group: "Look", label: "Visualizer framerate",
      caption: "Spectrum capture rate — 30 looks identical on the pill",
      min: 15, max: 120, step: 15, unit: "fps",
      terms: ["fps", "framerate", "refresh", "hz"] },

    // ── Shell · Manual palette ──────────────────────────────────────────
    { key: "manualHue", type: "int", group: "Manual palette", label: "Hue",
      caption: "Accent hue for manual palette mode (degrees)",
      min: 0, max: 359, step: 5, unit: "°",
      terms: ["color", "colour", "accent", "rainbow"] },
    { key: "manualSat", type: "int", group: "Manual palette", label: "Saturation",
      caption: "Accent saturation for manual palette mode",
      min: 0, max: 1, step: 0.05, scale: 100, unit: "%",
      terms: ["color", "colour", "accent", "vivid", "muted"] },
    { key: "manualDark", type: "toggle", group: "Manual palette", label: "Dark accent",
      caption: "Dark instead of light accent tones in manual mode",
      terms: ["light", "mode", "theme"] },

    // ── Shell · Pill ────────────────────────────────────────────────────
    { key: "notchStyle", type: "toggle", group: "Pill", label: "Notch style",
      caption: "Square-top island with flared ears instead of the pill",
      terms: ["dynamic island", "bar shape", "rounded", "corners"] },
    { key: "notchFlare", type: "int", group: "Pill", label: "Notch flare",
      caption: "How far both notch ears push out",
      min: -8, max: 8, step: 0.25, unit: "px",
      terms: ["ears", "wings", "width"] },
    { key: "pillOpacity", type: "int", group: "Pill", label: "Pill opacity",
      caption: "Surface opacity of the whole pill body",
      min: 0.3, max: 1, step: 0.05,
      terms: ["transparency", "translucent", "glass", "see through"] },
    { key: "pillBlur", type: "toggle", group: "Pill", label: "Pill blur",
      caption: "Background blur behind the pill body",
      terms: ["frosted", "glass", "backdrop"] },
    { key: "topGap", type: "int", group: "Pill", label: "Top gap",
      caption: "Margin above the pill (fraction of the shipped 8px)",
      min: 0, max: 2, step: 0.1, terms: ["margin", "edge", "offset", "y"] },
    { key: "appGap", type: "int", group: "Pill", label: "Window gap",
      caption: "Reserved band windows tuck under (fraction of the shipped 12px)",
      min: 0, max: 2, step: 0.1, terms: ["reserve", "exclusive zone", "strut", "windows"] },
    { key: "autoHide", type: "toggle", group: "Pill", label: "Auto hide",
      caption: "Retract the pill off the top edge until the pointer touches it",
      terms: ["retract", "hide bar", "mouse edge", "peek"] },
    { key: "gameMode", type: "toggle", group: "Pill", label: "Game mode",
      caption: "Flat strip, no animations, no popups",
      terms: ["gaming", "performance", "strip", "fullscreen"] },

    // ── Shell · Behaviour ───────────────────────────────────────────────
    { key: "time12h", type: "toggle", group: "Behaviour", label: "12-hour clock",
      caption: "AM/PM instead of 24-hour time",
      terms: ["clock format", "am pm", "time"] },
    { key: "clockSeconds", type: "toggle", group: "Behaviour", label: "Clock seconds",
      terms: ["seconds", "time"] },
    { key: "showGlyphs", type: "toggle", group: "Behaviour", label: "Japanese glyphs",
      caption: "Kanji headers and transport glyphs across the shell",
      terms: ["kanji", "漢字", "jp", "cjk", "icons"] },
    { key: "vimKeys", type: "toggle", group: "Behaviour", label: "Vim keys",
      caption: "h/j/k/l navigation in the pill menus",
      terms: ["hjkl", "keyboard", "arrows", "navigation"] },
    { key: "reduceMotion", type: "toggle", group: "Behaviour", label: "Reduce motion",
      caption: "Trim the animation budget",
      terms: ["animation", "speed", "accessibility", "motion"] },
    { key: "dnd", type: "toggle", group: "Behaviour", label: "Do not disturb",
      caption: "Notifications stay silent",
      terms: ["notifications", "silence", "quiet", "mute popups"] },
    { key: "keepAwake", type: "toggle", group: "Behaviour", label: "Keep awake",
      caption: "Inhibit idle until toggled off",
      terms: ["caffeine", "inhibit", "sleep", "screensaver"] },

    // ── Shell · Media ───────────────────────────────────────────────────
    { key: "musicViz", type: "toggle", group: "Media", label: "Music visualizer",
      caption: "Spectrum bars in the rest pill",
      terms: ["cava", "spectrum", "eq", "audio"] },

    // ── Hardware · Night light ──────────────────────────────────────────
    { key: "nightLightMode", type: "seg", group: "Night light", label: "Night light",
      caption: "Warm the screen on a schedule or always",
      vals: ["off", "always", "scheduled"], names: ["Off", "Always", "Scheduled"],
      terms: ["color temperature", "warmth", "redshift", "blue light", "eye strain"] },
    { key: "nightLightTemp", type: "int", group: "Night light", label: "Temperature",
      caption: "Kelvin of the warmed panel",
      min: 2500, max: 6500, step: 100, unit: "K",
      terms: ["kelvin", "warmth", "color", "warm"] },
    { key: "nightLightOnMin", type: "int", group: "Night light", label: "On at",
      caption: "Minutes from midnight the schedule warms up",
      min: 0, max: 1439, step: 15, unit: "min",
      terms: ["schedule", "start", "sunset", "time of day"] },
    { key: "nightLightOffMin", type: "int", group: "Night light", label: "Off at",
      caption: "Minutes from midnight the schedule cools back down",
      min: 0, max: 1439, step: 15, unit: "min",
      terms: ["schedule", "stop", "sunrise", "time of day"] },

    // ── Hardware · Idle & lock ──────────────────────────────────────────
    { key: "idleLockMin", type: "int", group: "Idle & lock", label: "Lock after",
      caption: "Idle minutes before the screen locks (0 = never)",
      min: 0, max: 60, step: 1, unit: "min", terms: ["autolock", "screen lock", "timeout"] },
    { key: "idleScreenOffMin", type: "int", group: "Idle & lock", label: "Screen off after",
      caption: "Idle minutes before the panel powers down (0 = never)",
      min: 0, max: 60, step: 1, unit: "min", terms: ["dpms", "display sleep", "blank"] },
    { key: "idleSuspendMin", type: "int", group: "Idle & lock", label: "Suspend after",
      caption: "Idle minutes before the machine suspends (0 = never)",
      min: 0, max: 120, step: 1, unit: "min", terms: ["sleep", "ram", "suspend to idle"] },
    { key: "lockDotsMode", type: "seg", group: "Idle & lock", label: "Lock dots",
      caption: "Password bead entrance on the lock screen",
      vals: ["drop", "pulse", "gpixel"], names: ["Drop", "Pulse", "Gpixel"],
      terms: ["password", "pin", "animation", "lock screen"] },

    // ── Hardware · Recording ────────────────────────────────────────────
    { key: "recordCountdown", type: "int", group: "Recording", label: "Countdown",
      caption: "Seconds before capture starts",
      min: 0, max: 10, step: 1, unit: "s", terms: ["delay", "start timer"] },
    { key: "recordFps", type: "int", group: "Recording", label: "Frame rate",
      min: 15, max: 144, step: 15, unit: "fps",
      terms: ["fps", "framerate", "smoothness"] },
    { key: "recordQuality", type: "seg", group: "Recording", label: "Quality",
      vals: ["low", "medium", "high", "ultra"],
      names: ["Low", "Medium", "High", "Ultra"],
      terms: ["bitrate", "crf", "codec", "file size"] },
    { key: "recordCursor", type: "toggle", group: "Recording", label: "Capture cursor",
      terms: ["mouse", "pointer"] },
    { key: "recordMic", type: "toggle", group: "Recording", label: "Microphone",
      caption: "Mix the mic into the recording",
      terms: ["audio", "voice"] },
    { key: "recordDesktop", type: "toggle", group: "Recording", label: "Desktop audio",
      terms: ["system sound", "output", "audio"] },
    { key: "recordDir", type: "text", group: "Recording", label: "Save folder",
      caption: "Where recordings land (empty = ~/Videos)",
      placeholder: "~/Videos", terms: ["path", "directory", "output", "videos"] },

    // ── Hardware · Weather & wallpaper ──────────────────────────────────
    { key: "weatherCity", type: "text", group: "Weather & files", label: "Weather city",
      caption: "wttr.in city for the calendar glance (empty = auto)",
      placeholder: "auto", terms: ["location", "forecast", "wttr"] },
    { key: "wallpaperDir", type: "text", group: "Weather & files", label: "Wallpaper folder",
      caption: "Folder the picker reads (empty = ~/Pictures)",
      placeholder: "~/Pictures", terms: ["directory", "path", "pictures", "images"] }
];

/** Every row flattened, for the search index. */
function all() {
    return registry;
}

/** Group display order — unsearched browse mode walks these in order. */
var groupOrder = [
    "Look", "Manual palette", "Pill", "Behaviour", "Media",
    "Night light", "Idle & lock", "Recording", "Weather & files"
];

/**
 * Rows matching `query` across label, caption, group, key and terms — a
 * case-insensitive substring match per token, so "night warm" finds the
 * temperature row and "12" finds the clock format. Returns [{row, score}]
 * sorted by best score: label hits outrank term hits.
 */
function search(query) {
    var q = query.trim().toLowerCase();
    if (q.length === 0)
        return [];
    var tokens = q.split(/\s+/);
    var hits = [];
    for (var i = 0; i < registry.length; i++) {
        var row = registry[i];
        var hay = (row.label + " " + (row.caption || "") + " " + row.group + " " + row.key).toLowerCase();
        var terms = (row.terms || []).join(" ").toLowerCase();
        var score = 0;
        var ok = true;
        for (var t = 0; t < tokens.length; t++) {
            var tok = tokens[t];
            if (row.label.toLowerCase().indexOf(tok) !== -1)
                score += 3;
            else if (hay.indexOf(tok) !== -1)
                score += 2;
            else if (terms.indexOf(tok) !== -1)
                score += 1;
            else {
                ok = false;
                break;
            }
        }
        if (ok)
            hits.push({ row: row, score: score });
    }
    hits.sort(function (a, b) { return b.score - a.score; });
    return hits;
}

/** Rows of one group, in registry order. */
function byGroup(group) {
    var out = [];
    for (var i = 0; i < registry.length; i++)
        if (registry[i].group === group)
            out.push(registry[i]);
    return out;
}

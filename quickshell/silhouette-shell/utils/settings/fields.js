/**
 * Field metadata shared by the shell's own settings surfaces (modules/settings/)
 * and the settings app (modules/settingsapp/): the bounds, step, default and
 * option list of every field both edit.
 *
 * It exists because the two settings UIs stated this data twice — the app in a
 * row descriptor (`min`/`max`/`step`/`reset`), the shell in the `from`/`to`/`step`
 * of the control next to the field and in the fallback its `seed()` used when the
 * config file did not carry the field. A bound is a property of the field, not of
 * the control drawing it, so it is stated once here and both sides read it; a new
 * setting is then one entry, not two edits that can drift.
 *
 * It lives in `utils/` because that is the one tree both halves already import
 * from (see the Lua helpers next door). `unit` and `decimals` are deliberately
 * *not* here: those are how a control formats its value, not what the field
 * accepts, and each UI keeps its own.
 *
 * Keyed `"<source>.<field>"`, the pair a row's `source` and `field` name — so
 * `"deco.gapsIn"` is the `gapsIn` field of the decoration.lua source, and the
 * shell's Look surface asks for the same key its writeDeco call writes; `flags.*`
 * is a shell flag and `input.*` a field of the input files. Only fields both
 * sides edit are listed; anything one UI owns alone stays with it — which is why
 * the pill's sizes, the aura and the wallpaper folder are not here: the shell's
 * own surfaces never edit them. `monitor.scales` is the one entry that is not a
 * field at all, a choice list both Display surfaces state twice.
 *
 * Most bounds here are the value both sides already shipped — a control that
 * could not move a field is a control that lies, so this is a de-duplication
 * rather than a re-tuning. Where the two had already drifted apart a bound had to
 * be *settled* instead; those entries say so, and why, where they are listed.
 */
var FIELDS = {
    // decoration.lua: the shell's Look surface and the app's Look page.
    "deco.gapsIn":         { min: 0,   max: 40,  step: 1,    reset: 6 },
    "deco.gapsOut":        { min: 0,   max: 60,  step: 1,    reset: 12 },
    "deco.rounding":       { min: 0,   max: 30,  step: 1,    reset: 12 },
    "deco.roundingPower":  { min: 1,   max: 10,  step: 1,    reset: 4 },
    "deco.borderSize":     { min: 0,   max: 8,   step: 1,    reset: 2 },
    "deco.resizeOnBorder": { reset: true },
    "deco.layout":         { options: ["dwindle", "master"], names: ["Dwindle", "Master"], reset: "dwindle" },
    "deco.blurOn":         { reset: true },
    "deco.blurSize":       { min: 1,   max: 20,  step: 1,    reset: 8 },
    "deco.blurPasses":     { min: 1,   max: 5,   step: 1,    reset: 3 },
    "deco.blurVibrancy":   { min: 0,   max: 1,   step: 0.01, reset: 0.17 },
    "deco.blurNoise":      { min: 0,   max: 0.2, step: 0.01, reset: 0.01 },
    "deco.shadowOn":       { reset: true },
    "deco.shadowRange":    { min: 0,   max: 50,  step: 1,    reset: 12 },
    "deco.shadowPower":    { min: 1,   max: 4,   step: 1,    reset: 3 },
    "deco.activeOpacity":  { min: 0.5, max: 1,   step: 0.05, reset: 1.0 },
    "deco.inactiveOpacity":{ min: 0.5, max: 1,   step: 0.05, reset: 1.0 },
    // decorations.lua, animations table: the shell's Animation surface and the
    // app's Motion page. The style the app also offers is not here — the shell's
    // surface shapes the curve itself instead and never picks a style.
    "deco.animOn":         { reset: true },
    "deco.animSpeed":      { min: 1,   max: 10,  step: 0.5,  reset: 3 },

    // flags.json: values the shell reads straight from Flags, edited by its own
    // Pill and Night light groups and by the settings app's Bar & Island and
    // Control Center pages.
    "flags.topGap":         { min: -1,   max: 2,    step: 0.1,  reset: 0.7 },
    "flags.appGap":         { min: 0,    max: 2,    step: 0.1,  reset: 1.0 },
    "flags.pillOpacity":    { min: 0.55, max: 1,    step: 0.05, reset: 1.0 },
    "flags.notchFlare":     { min: -7,   max: 10,   step: 0.25, reset: 1 },
    // The three night-light bounds are settled rather than copied: the two UIs had
    // already drifted apart, and a bound cannot be both. services/NightLight.qml
    // clamps the temperature to 2200-6000 and the app's old 2500-6500 reached past
    // that (buildConf clamped it back), so 2200-6000 is what both offer now. The
    // two times run the whole minute-of-day, 0-1439: the app shipped 1439, and
    // narrowing to the shell's 1425 would leave a value it had already written
    // unreachable from the shell side. Both already used the same step.
    "flags.nightLightMode": { options: ["off", "on", "scheduled"], names: ["Off", "On", "Scheduled"], reset: "scheduled" },
    "flags.nightLightTemp": { min: 2200, max: 6000, step: 100,  reset: 3600 },
    "flags.nightLightOnMin":{ min: 0,    max: 1439, step: 15,   reset: 1200 },
    "flags.nightLightOffMin":{ min: 0,   max: 1439, step: 15,   reset: 420 },
    // The palette and the shell's own motion budget: the shell's Appearance
    // surface and the app's Appearance, Motion pages.
    "flags.paletteMode":    { options: ["static", "dynamic", "manual"], names: ["Static", "Dynamic", "Manual"], reset: "static" },
    "flags.manualHue":      { min: 0,   max: 359, step: 5,    reset: 0 },
    "flags.manualSat":      { min: 0,   max: 1,   step: 0.05, reset: 0.5 },
    "flags.manualDark":     { reset: true },
    "flags.uiScale":        { min: 0.9, max: 1.25, step: 0.05, reset: 1.1,
                             options: [0.9, 1.0, 1.1, 1.25], names: ["90%", "100%", "110%", "125%"] },
    "flags.uiFont":         { reset: "JetBrainsMono Nerd Font Mono" },
    "flags.mediaStyle":     { options: ["bleed", "wash", "none"], names: ["Bleed", "Wash", "None"], reset: "bleed" },
    // The pill clock and the shell's glyph headers: the shell's Appearance surface
    // and the app's Clock & Date page.
    "flags.time12h":        { reset: true },
    "flags.clockSeconds":   { reset: false },
    "flags.showGlyphs":     { reset: false },
    "flags.reduceMotion":   { reset: false },
    "flags.musicViz":       { reset: true },
    "flags.vizStyle":       { options: ["bars", "centered", "string"], names: ["Bars", "Center", "String"], reset: "bars" },
    "flags.vizFps":         { min: 15,  max: 120, step: 15,   reset: 60,
                             options: [15, 30, 60, 120], names: ["15", "30", "60", "120"] },

    // input.lua / env.lua: the shell's Input surface and the app's Input page.
    // These ranges had drifted apart too, and are the union of the two, so no
    // value either UI could already have written is left unreachable (the finer
    // step is kept where the two differed — 0.05 over 0.1, 2px over 4px — since
    // it can reach every value the coarser one could and more).
    "input.sensitivity":    { min: -1,  max: 1,   step: 0.05, reset: 0 },
    "input.accelProfile":   { options: ["flat", "adaptive"], names: ["Flat", "Adaptive"], reset: "flat" },
    // The layout row's names are the options upper-cased, which the app derives,
    // so this entry carries the list and the default and no name list.
    "input.kbLayout":       { options: ["us", "de", "gb", "fr", "es", "it", "tr"], reset: "us" },
    "input.repeatRate":     { min: 1,   max: 100, step: 1,    reset: 25 },
    "input.repeatDelay":    { min: 100, max: 1000, step: 25,  reset: 600 },
    "input.numlock":        { reset: false },
    "input.cursorSize":     { min: 12,  max: 96,  step: 2,    reset: 24 },
    "input.cursorTheme":    { reset: "Bibata-Modern-Ice" },

    // Not a field either UI writes: the fractional-scale choices both Display
    // surfaces draw, stated once so the two lists cannot drift. Only `options`
    // and `names` are meaningful here.
    "monitor.scales":       { options: [1, 1.25, 1.5, 2], names: ["1.0", "1.25", "1.5", "2.0"] }
};

/**
 * The metadata for `<source>.<field>`, or null when the field is not shared
 * between the two UIs (a UI reads a null and keeps its own value).
 */
function get(source, field) {
    return FIELDS[source + "." + field] || null;
}

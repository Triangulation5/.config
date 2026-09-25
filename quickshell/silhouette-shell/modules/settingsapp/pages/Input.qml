pragma Singleton

import QtQuick
import "../utils/rows.js" as Rows
import qs.modules.settingsapp.services

/**
 * Input: pointer, keyboard and cursor, written into `input.lua`, `env.lua` and
 * the autostart cursor line (see the Input service). The cursor rows apply live
 * through `hyprctl setcursor`; everything else reloads Hyprland.
 *
 * The layout row offers the common layouts plus whatever the file already says,
 * so a config on an unlisted one still shows its value instead of an empty strip.
 *
 * A row's bounds, step, choices and default are not stated here: they are
 * properties of the field, shared with the shell's own Input surface, and live in
 * one table (`utils/settings/fields.js`, read through `row()` below).
 */
QtObject {
    readonly property string name: "Input"
    readonly property string icon: "\u2328"
    readonly property string keywords: "mouse pointer sensitivity acceleration accel profile keyboard layout repeat rate delay numlock cursor theme size touchpad scrolling"

    /** One row for an `input` field, its bounds read from the shared table (see utils/rows.js). */
    function row(field, type, label, caption, unit, extra) {
        return Rows.of("input", field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        { card: "Pointer", rows: [
            row("sensitivity", "slider", "Sensitivity", "Pointer speed offset; 0 leaves it alone", ""),
            row("accelProfile", "segmented", "Acceleration", "How pointer speed follows motion", "")
        ]},
        { card: "Keyboard", rows: [
            row("kbLayout", "segmented", "Layout", "Keyboard layout", "",
                { options: Input.kbLayoutOptions, names: Input.kbLayoutNames }),
            row("repeatRate", "slider", "Repeat rate", "Key repeats per second when held", "/s"),
            row("repeatDelay", "slider", "Repeat delay", "Hold time before a key repeats", "ms"),
            row("numlock", "toggle", "Numlock", "Numlock on at startup", "")
        ]},
        { card: "Cursor", rows: [
            row("cursorSize", "slider", "Size", "Cursor size in pixels", "px"),
            row("cursorTheme", "text", "Theme", "XCURSOR_THEME; applied live with hyprctl setcursor", "",
                { placeholder: "Bibata-Modern-Ice" })
        ]}
    ]
}

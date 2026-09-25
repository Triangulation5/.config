pragma Singleton

import QtQuick
import "../utils/rows.js" as Rows

/**
 * Look: the window decoration the shell's own Look surface edits, read and
 * written straight into `~/.config/hypr/modules/decorations.lua` (see the Deco
 * service) so a change applies now and survives a restart.
 *
 * Every row names a `deco` field rather than a flag. What that field accepts is
 * not decided here: its bounds, step and default are properties of the field,
 * shared with the shell's own Look surface, and live in one table
 * (`utils/settings/fields.js`, read through `row()` below). A row therefore
 * carries only what this app alone decides: its editor type, its label, its
 * caption and its unit. A new decoration field is one entry in that table and
 * one row here, rather than two controls that can disagree.
 */
QtObject {
    readonly property string name: "Look"
    readonly property string icon: "\u25A3"
    readonly property string keywords: "gaps rounding radius border blur shadow opacity animation decorations window decoration"

    /**
     * One row for the `deco` field `field`, with its bounds, step, default and
     * option list taken from the shared table. `unit` is the one thing the table
     * does not carry — it is how the control formats a value, not what the field
     * accepts — so the caller states it, empty string included.
     */
    function row(field, type, label, caption, unit) {
        return Rows.of("deco", field, type, label, caption, unit);
    }

    readonly property var groups: [
        { card: "Window", rows: [
            row("gapsIn", "slider", "Gaps inner", "Space between tiled windows", "px"),
            row("gapsOut", "slider", "Gaps outer", "Space to the screen edge", "px"),
            row("rounding", "slider", "Rounding", "Corner radius in pixels", "px"),
            row("roundingPower", "slider", "Rounding power", "Higher bends corners to a squircle", ""),
            row("borderSize", "slider", "Border size", "Window outline thickness", "px"),
            row("resizeOnBorder", "toggle", "Resize on border", "Drag a window edge to resize", ""),
            row("layout", "segmented", "Layout", "Window tiling layout", "")
        ]},
        { card: "Blur", rows: [
            row("blurOn", "toggle", "Blur", "Blur behind transparent windows", ""),
            row("blurSize", "slider", "Strength", "Blur radius", "px"),
            row("blurPasses", "slider", "Passes", "More passes, smoother blur", ""),
            row("blurVibrancy", "slider", "Vibrancy", "Colour saturation behind the blur", ""),
            row("blurNoise", "slider", "Noise", "Grain mixed into the blur", "")
        ]},
        { card: "Shadow", rows: [
            row("shadowOn", "toggle", "Shadow", "Drop shadow under windows", ""),
            row("shadowRange", "slider", "Range", "How far the shadow spreads", "px"),
            row("shadowPower", "slider", "Render power", "Shadow falloff sharpness", "")
        ]},
        { card: "Opacity", rows: [
            row("activeOpacity", "slider", "Active window", "Focused window transparency", ""),
            row("inactiveOpacity", "slider", "Inactive window", "Unfocused window transparency", "")
        ]}
    ]
}

pragma Singleton

import QtQuick
import "../utils/rows.js" as Rows
import qs.modules.settingsapp.config

/**
 * Bar & Island: the pill's own geometry, the notch look, and game mode. These
 * are the flags the shell reads in Modules/pill and in Motion, so a change here
 * is visible on the pill immediately.
 *
 * It imports `qs.config` for one row only, the notch style, which is a pair of
 * flags rather than one — see its comment.
 *
 * The pill's own geometry rows take their bounds, step and default from the table
 * shared with the shell's Pill group (utils/settings/fields.js — read through
 * `row()` below), so the two UIs cannot offer different ranges for one flag.
 */
QtObject {
    readonly property string name: "Bar & Island"
    readonly property string icon: "\u25AD"
    readonly property string keywords: "pill bar island notch game mode pointer hover collapse auto hide strip wake"

    /**
     * One row for the flag `field`, with its bounds, step and default taken from
     * the shared table. `extra` carries what the table deliberately does not —
     * `unit`, `displayScale` and the like are how a control formats a value, not
     * what the field accepts.
     */
    function row(field, type, label, caption, unit, extra) {
        return Rows.flag(field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        { card: "Pill", rows: [
            row("topGap", "slider", "Pill gap",
                "Space above the pill as a fraction of the shipped 8px; lower moves it up. The notch style sets this to -0.2", ""),
            row("appGap", "slider", "App gap",
                "Gap between the pill and tiled windows; 0 tucks them flush underneath", ""),
            row("pillOpacity", "slider", "Pill opacity", "", "%", { displayScale: 100 }),
            // The pill's frost is a layer rule in the Hyprland config, not a flag:
            // toggling it adds or removes that rule, which is what the shell does.
            { source: "deco", field: "pillBlur", type: "toggle", label: "Pill blur",
              caption: "Frosts the pill body; needs opacity under 100% to show", reset: true },
            { key: "autoHide", type: "toggle", label: "Auto hide",
              caption: "Retract the pill off the top edge until the pointer touches it", reset: false },
            { key: "pillAutoStripH", type: "slider", label: "Wake strip",
              min: 1, max: 20, step: 1, unit: "px",
              caption: "Thickness of the top-edge strip that wakes the pill back down while auto hide is on", reset: 5 }
        ]},
        { card: "Notch", rows: [
            /**
             * The one row in this app that writes two flags. Style and gap are a
             * pair in the look, so the shell's own Appearance surface writes both
             * (`Flags.topGap = on ? -0.2 : 0.7`): the gap is what pulls the island
             * flush against the screen edge, and flush is the whole point of a
             * notch. Writing the style alone grows the ears and squares the top
             * corners but leaves the pill floating where it was, which reads as
             * "the toggle did nothing".
             *
             * A pair is not a thing this app's row model has, so the row carries
             * `get`/`set` instead of a bare `key` — and both writes still go
             * through Sources, the same door every other row uses. Moving Pill gap
             * afterwards stays free: the shell re-pairs them only when the style
             * itself changes.
             */
            { key: "notchStyle", type: "toggle", label: "Show as notch",
              caption: "Flush-topped island with flared ears; moves Pill gap with it",
              get: function () { return Sources.read({ key: "notchStyle" }); },
              set: function (v) {
                  Sources.write({ key: "notchStyle" }, v);
                  Sources.write({ key: "topGap" }, v ? -0.2 : 0.7);
              },
              reset: false },
            row("notchFlare", "slider", "Notch flare", "Flare offset pushed out on both notch ears", "px")
        ]},
        { card: "Gaming", rows: [
            { key: "gameMode", type: "toggle", label: "Game mode",
              caption: "Flat strip, no animations, no popups while a game is focused", reset: false }
        ]}
    ]
}

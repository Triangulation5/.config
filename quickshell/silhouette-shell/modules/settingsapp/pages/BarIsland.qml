pragma Singleton

import QtQuick
import qs.modules.settingsapp.config

/**
 * Bar & Island: the pill's own geometry, the notch look, and game mode. These
 * are the flags the shell reads in Modules/pill and in Motion, so a change here
 * is visible on the pill immediately.
 *
 * It imports `qs.config` for one row only, the notch style, which is a pair of
 * flags rather than one — see its comment.
 */
QtObject {
    readonly property string name: "Bar & Island"
    readonly property string icon: "\u25AD"
    readonly property string keywords: "pill bar island notch game mode pointer hover collapse island"

    readonly property var groups: [
        { card: "Pill", rows: [
            { key: "topGap", type: "slider", label: "Pill gap", min: -1, max: 2, step: 0.1, unit: "",
              caption: "Space above the pill as a fraction of the shipped 8px; lower moves it up. The notch style sets this to -0.2", reset: 0.7 },
            { key: "appGap", type: "slider", label: "App gap", min: 0, max: 2, step: 0.1, unit: "",
              caption: "Gap between the pill and tiled windows; 0 tucks them flush underneath", reset: 1.0 },
            { key: "pillOpacity", type: "slider", label: "Pill opacity", min: 0.55, max: 1, step: 0.05,
              displayScale: 100, unit: "%", reset: 1.0 },
            // The pill's frost is a layer rule in the Hyprland config, not a flag:
            // toggling it adds or removes that rule, which is what the shell does.
            { source: "deco", field: "pillBlur", type: "toggle", label: "Pill blur",
              caption: "Frosts the pill body; needs opacity under 100% to show", reset: true },
            { key: "autoHide", type: "toggle", label: "Auto hide",
              caption: "Retract the pill off the top edge until the pointer touches it", reset: false }
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
            { key: "notchFlare", type: "slider", label: "Notch flare", min: -7, max: 10, step: 0.25, unit: "px",
              caption: "Flare offset pushed out on both notch ears", reset: 1 }
        ]},
        { card: "Gaming", rows: [
            { key: "gameMode", type: "toggle", label: "Game mode",
              caption: "Flat strip, no animations, no popups while a game is focused", reset: false }
        ]}
    ]
}

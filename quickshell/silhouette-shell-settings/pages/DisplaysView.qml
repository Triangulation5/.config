import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.components

/**
 * The Displays page body: one card per monitor, each with a resolution, a
 * refresh rate, a scale and a position. The rows are built here rather than
 * declared as data, because their options come from `hyprctl` — a page that had
 * to name them would have to name every monitor anyone might plug in.
 *
 * The rows still go through the same editors and the same `Sources` door as
 * every other page: a built row carries its own `get`/`set` closures, which
 * Sources prefers over a named source. That is what keeps this page from
 * needing a control of its own.
 *
 * A change is applied as soon as it is picked. Every mode offered comes from the
 * monitor's `availableModes`, so an unsupported mode cannot be asked for; the
 * shell's own Display surface puts a watchdog and a confirm step in front of the
 * same write, which this does without.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    Repeater {
        model: Monitors.monitors

        delegate: SettingGroup {
            required property var modelData

            Layout.fillWidth: true
            group: root.groupFor(modelData)
        }
    }

    Text {
        Layout.fillWidth: true
        visible: Monitors.monitors.length === 0
        text: "hyprctl reports no monitors."
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    /** The live monitor with this name, or `fallback` when it is gone. */
    function live(name, fallback) {
        var mon = Monitors.byName(name);
        return mon === null ? fallback : mon;
    }

    /** The `{ card, rows }` group one monitor renders as. */
    function groupFor(mon) {
        var live = root.live(mon.name, mon);
        var resolutions = Monitors.resolutionsFor(live);
        var resIndex = Monitors.resolutionIndex(live);
        var rates = Monitors.ratesFor(live);
        var rateIndex = Math.max(0, rates.indexOf(live.refresh));

        var resOptions = [];
        var resNames = [];
        for (var r = 0; r < resolutions.length; r++) {
            resOptions.push(r);
            resNames.push(resolutions[r].w + "\u00D7" + resolutions[r].h);
        }

        var rateOptions = [];
        var rateNames = [];
        for (var i = 0; i < rates.length; i++) {
            rateOptions.push(i);
            rateNames.push(rates[i] + "Hz");
        }

        var scaleOptions = [];
        var scaleNames = [];
        for (var s = 0; s < Monitors.scales.length; s++) {
            scaleOptions.push(Monitors.scales[s]);
            scaleNames.push(Monitors.scales[s] === 1 ? "1.0" : String(Monitors.scales[s]));
        }

        return {
            card: mon.name + "   " + live.width + "\u00D7" + live.height + " @ " + live.refresh + "Hz   \u00B7   " + live.scale + "\u00D7",
            rows: [
                {
                    type: "segmented", label: "Resolution", caption: "From the modes Hyprland reports",
                    options: resOptions, names: resNames,
                    get: function () { return Monitors.resolutionIndex(root.live(mon.name, mon)); },
                    set: function (v) { Monitors.applyMode(root.live(mon.name, mon), v, 0); }
                },
                {
                    type: "segmented", label: "Refresh", caption: "Rates this resolution supports",
                    options: rateOptions, names: rateNames,
                    get: function () {
                        var m = root.live(mon.name, mon);
                        var list = Monitors.ratesFor(m);
                        return Math.max(0, list.indexOf(m.refresh));
                    },
                    set: function (v) {
                        Monitors.applyMode(root.live(mon.name, mon), Monitors.resolutionIndex(root.live(mon.name, mon)), v);
                    }
                },
                {
                    type: "segmented", label: "Scale", caption: "Fractional scaling this output accepts",
                    options: scaleOptions, names: scaleNames,
                    get: function () { return root.live(mon.name, mon).scale; },
                    set: function (v) { Monitors.applyScale(root.live(mon.name, mon), v); }
                },
                {
                    type: "text", label: "Position", placeholder: "0x0",
                    caption: "Where this output sits in the layout, as XxY",
                    get: function () { return root.live(mon.name, mon).x + "x" + root.live(mon.name, mon).y; },
                    set: function (v) { Monitors.applyPosition(root.live(mon.name, mon), v); }
                }
            ]
        };
    }
}

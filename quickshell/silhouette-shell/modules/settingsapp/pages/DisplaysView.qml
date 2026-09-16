import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import qs.modules.settingsapp.components

/**
 * The Displays page body: the arrangement of every output at the top, then one
 * portrait and one card of controls per monitor. The rows are built here rather
 * than declared as data, because their options come from `hyprctl` — a page that
 * had to name them would have to name every monitor anyone might plug in.
 *
 * The rows still go through the same editors and the same `Sources` door as
 * every other page: a built row carries its own `get`/`set` closures, which
 * Sources prefers over a named source. That is what keeps this page from needing a
 * control of its own.
 *
 * The map and the cards are wired to each other through `selected`: clicking a
 * tile marks that output and scrolls to its settings, which is the whole point of
 * a peek — with two panels plugged in, "which one am I editing" has to be
 * answerable without reading output names.
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

    /** The output the user picked in the map or on a portrait, or "". */
    property string selected: ""

    /** What the arrangement card says under the map. */
    readonly property string layoutCaption: {
        var n = Monitors.monitors.length;
        if (n === 0)
            return "hyprctl reports no connected outputs.";
        if (n === 1)
            return "One output connected, drawn where the compositor has it. A second one appears here beside or above it once it is plugged in.";
        return n + " outputs, drawn where the compositor has them. Click one to open its settings.";
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        SectionLabel {
            Layout.fillWidth: true
            text: "Arrangement"
        }

        Rectangle {
            Layout.fillWidth: true
            color: Theme.card
            radius: Theme.radiusCard
            implicitHeight: arrangement.implicitHeight + 36

            ColumnLayout {
                id: arrangement
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                DisplayMap {
                    id: map
                    Layout.fillWidth: true
                    mons: Monitors.monitors
                    mainName: Monitors.mainName
                    selName: root.selected
                    onPicked: function (name) { root.pick(name) }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.layoutCaption
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Repeater {
        id: cardRepeater

        model: Monitors.monitors

        delegate: ColumnLayout {
            id: block

            required property var modelData

            readonly property string monName: modelData.name

            Layout.fillWidth: true
            spacing: 10

            DisplayHeader {
                Layout.fillWidth: true
                mon: root.live(block.monName, block.modelData)
                main: block.monName === Monitors.mainName
                sel: root.selected === block.monName
                onPicked: root.pick(block.monName)
            }

            // No `card` heading: the portrait above already names this monitor,
            // and the card's own label would say the same thing twice.
            SettingGroup {
                Layout.fillWidth: true
                group: root.groupFor(block.modelData)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: Monitors.monitors.length === 0
        text: "Nothing to configure until an output is connected."
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    /** The live monitor with this name, or `fallback` when it is gone. */
    function live(name, fallback) {
        var mon = Monitors.byName(name);
        return mon === null ? fallback : mon;
    }

    /**
     * Show the monitor `name` names: mark it and scroll its card into view. The
     * scroll target is the block item, measured against the flickable's content
     * item rather than the view, because the view is scrolled by definition.
     */
    function pick(name) {
        root.selected = name;
        var block = root.blockFor(name);
        var flick = root.flickable();
        if (block === null || flick === null)
            return;
        var y = block.mapToItem(flick.contentItem, 0, 0).y;
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - 24));
    }

    /** The delegate showing the monitor `name` names, or null. */
    function blockFor(name) {
        for (var i = 0; i < cardRepeater.count; i++) {
            var item = cardRepeater.itemAt(i);
            if (item && item.monName === name)
                return item;
        }
        return null;
    }

    /**
     * The scroll view this page sits in, found by walking up to the first item
     * that can scroll — or null when the page is previewed on its own, where a
     * pick has nothing to scroll.
     */
    function flickable() {
        var p = root.parent;
        while (p && p.contentY === undefined)
            p = p.parent;
        return p ? p : null;
    }

    /** The `{ card, rows }` group one monitor renders as. */
    function groupFor(mon) {
        var live = root.live(mon.name, mon);
        var resolutions = Monitors.resolutionsFor(live);
        var rates = Monitors.ratesFor(live);

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
            card: "",
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

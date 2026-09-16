pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../utils/lua/monitors.js" as Mon
import "../utils/lua/insert.js" as Insert

/**
 * The displays, from two sides: `hyprctl monitors -j` for what is actually
 * connected and running, and `~/.config/hypr/modules/monitors.lua` for what the
 * layout is declared as. The live read is the source of truth for the controls;
 * the file is what a change is persisted into, followed by a reload.
 *
 * A change is a mode string (`WxH@Hz`, always one Hyprland reports as available,
 * so an unsupported mode can never be asked for), a position (`XxY`) and a
 * scale. The shell's own Display surface applies a mode through its
 * display-apply.sh watchdog and a timed confirm; here a change is written and
 * reloaded directly, which is why every option offered comes from
 * `availableModes` rather than from free input.
 *
 * A config that only declares the catch-all `hl.monitor({ output = "" })` gets a
 * block for the output it is asked to change, appended last so it wins over the
 * catch-all.
 */
Singleton {
    id: root

    readonly property string path: Paths.monitors

    property string text: ""
    property bool loaded: false
    /** Non-empty when the last change could not be applied. */
    property string note: ""

    /** Live monitors, as parsed from `hyprctl monitors -j`. */
    property var monitors: []
    /** The scales the scale row offers. */
    readonly property var scales: [1.0, 1.25, 1.5, 2.0]

    /** One monitor by output name, or null. */
    function byName(name) {
        for (var i = 0; i < root.monitors.length; i++)
            if (root.monitors[i].name === name)
                return root.monitors[i];
        return null;
    }

    /**
     * The modes of `mon` grouped by resolution, largest first, each with its
     * refresh rates descending — the shape the resolution and refresh rows take.
     */
    function resolutionsFor(mon) {
        var byRes = {};
        for (var i = 0; i < mon.modes.length; i++) {
            var m = mon.modes[i];
            var k = m.w + "x" + m.h;
            if (!byRes[k])
                byRes[k] = { w: m.w, h: m.h, rates: [] };
            if (byRes[k].rates.indexOf(m.hz) < 0)
                byRes[k].rates.push(m.hz);
        }
        var list = [];
        for (var key in byRes) {
            byRes[key].rates.sort(function (a, b) { return b - a; });
            list.push(byRes[key]);
        }
        list.sort(function (a, b) { return b.w * b.h - a.w * a.h; });
        return list;
    }

    /** Index of `mon`'s current resolution in `resolutionsFor(mon)`, or 0. */
    function resolutionIndex(mon) {
        var list = root.resolutionsFor(mon);
        for (var i = 0; i < list.length; i++)
            if (list[i].w === mon.width && list[i].h === mon.height)
                return i;
        return 0;
    }

    /** The refresh rates of `mon`'s current resolution, descending. */
    function ratesFor(mon) {
        var list = root.resolutionsFor(mon);
        var i = root.resolutionIndex(mon);
        return list.length > i ? list[i].rates : [];
    }

    /**
     * Apply and persist a change to one output. Reloads the compositor on
     * success; on failure the note says what could not be written.
     */
    function apply(output, mode, position, scale) {
        var res = Mon.setMonitor(root.text, output, mode, position, scale);
        var appended = false;
        if (!res.ok) {
            res = Insert.appendMonitor(root.text, output, mode, position, scale);
            appended = res.ok;
        }
        if (!res.ok) {
            root.note = "Could not rewrite " + output + " in " + root.path + ".";
            return false;
        }
        root.note = appended ? "Added a monitor block for " + output + "." : "";
        root.text = res.text;
        writer.setText(res.text);
        Hypr.reload();
        refresh();
        return true;
    }

    /** Apply a resolution and refresh from the live list, keeping the scale. */
    function applyMode(mon, resIndex, rateIndex) {
        var list = root.resolutionsFor(mon);
        if (list.length === 0)
            return false;
        var resolution = list[Math.min(resIndex, list.length - 1)];
        var rate = resolution.rates[Math.min(rateIndex, resolution.rates.length - 1)];
        return root.apply(mon.name, resolution.w + "x" + resolution.h + "@" + rate,
                          mon.x + "x" + mon.y, mon.scale);
    }

    /** Apply a scale for one output, keeping its current mode and position. */
    function applyScale(mon, scale) {
        return root.apply(mon.name, mon.width + "x" + mon.height + "@" + mon.refresh,
                          mon.x + "x" + mon.y, scale);
    }

    /** Apply a position for one output, keeping its current mode and scale. */
    function applyPosition(mon, position) {
        return root.apply(mon.name, mon.width + "x" + mon.height + "@" + mon.refresh,
                          position, mon.scale);
    }

    /** Re-read the live monitor list. */
    function refresh() {
        if (!live.running)
            live.running = true;
    }

    FileView {
        id: monitorFile
        path: root.path
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.text = monitorFile.text();
            root.loaded = true;
        }
    }

    FileView {
        id: writer
        path: root.path
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: live
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.monitors = Mon.parse(this.text)
        }
    }

    Component.onCompleted: root.refresh()
}

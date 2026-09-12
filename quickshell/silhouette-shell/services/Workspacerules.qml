pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Per-monitor workspace list for the pill's workspace dots.
 *
 * The dots cannot come from Quickshell's `Hyprland.workspaces` model on this
 * stack. Hyprland 0.56 no longer sends an `id` in `hyprctl workspaces -j`,
 * while Quickshell 0.3.1 keys that model on the field: every workspace parses
 * as id 0 and collapses onto a single object, the ones pre-created from events
 * are left at id -1, and `monitor` is often null. Reading the model for the dot
 * range is what made the strip show a different, short number of dots on each
 * workspace with the active dot never landing.
 *
 * So this singleton reads the two hyprctl sources that are still accurate:
 *   - `hyprctl workspacerules -j` — the workspace→monitor assignment declared in
 *     monitors.lua. A rule with no monitor (`monitor = ""`, the usual
 *     single-monitor case) is filed under the focused monitor instead of being
 *     dropped, so its workspace shows before it has ever been visited.
 *   - `hyprctl workspaces -j` — the workspaces that currently exist, keyed by
 *     the reliable `monitor` and numeric `name` fields, so a workspace outside
 *     the rules (r+1 past the last one) still appears.
 *
 * `byMonitor` is their union, deduped and ascending, and is the dots' only
 * source. Both are re-read on the Hyprland events that change the set and on
 * config reload, since editing monitors.lua rewrites the rules.
 */
Singleton {
    id: root

    /** monitorName -> workspace numbers assigned to it by the rules. */
    property var ruledByMonitor: ({})
    /** monitorName -> workspace numbers that currently exist on it. */
    property var liveByMonitor: ({})
    property bool rulesPending: false
    property bool livePending: false

    /** monitorName -> every workspace number on that monitor, ascending. */
    readonly property var byMonitor: {
        var out = {};
        merge(out, ruledByMonitor);
        merge(out, liveByMonitor);
        for (var k in out)
            out[k].sort(function (a, b) { return a - b; });
        return out;
    }

    function merge(dst, src) {
        for (var k in src) {
            var v = src[k];
            if (!dst[k])
                dst[k] = [];
            for (var i = 0; i < v.length; i++)
                if (dst[k].indexOf(v[i]) < 0)
                    dst[k].push(v[i]);
        }
    }

    /**
     * The monitor a rule with no monitor falls back to: the focused one, or the
     * only one, so `monitor = ""` still lands somewhere instead of leaving the
     * whole map empty.
     */
    function fallbackMonitor() {
        var fm = Hyprland.focusedMonitor;
        if (fm)
            return fm.name;
        var mons = Hyprland.monitors.values;
        return mons.length === 1 ? mons[0].name : "";
    }

    function refresh() {
        if (!rulesProc.running)
            rulesProc.running = true;
        else
            rulesPending = true;
        if (!liveProc.running)
            liveProc.running = true;
        else
            livePending = true;
    }

    Process {
        id: rulesProc
        command: ["hyprctl", "workspacerules", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rules = null;
                try {
                    rules = JSON.parse(this.text);
                } catch (e) {
                    rules = null;
                }
                if (rules) {
                    var map = {};
                    for (var i = 0; i < rules.length; i++) {
                        var ws = parseInt(rules[i].workspaceString);
                        if (!(ws >= 1))
                            continue;
                        var mon = rules[i].monitor || root.fallbackMonitor();
                        if (!mon)
                            continue;
                        if (!map[mon])
                            map[mon] = [];
                        map[mon].push(ws);
                    }
                    root.ruledByMonitor = map;
                }
                if (root.rulesPending) {
                    root.rulesPending = false;
                    rulesProc.running = true;
                }
            }
        }
    }

    Process {
        id: liveProc
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var list = null;
                try {
                    list = JSON.parse(this.text);
                } catch (e) {
                    list = null;
                }
                if (list) {
                    var map = {};
                    for (var i = 0; i < list.length; i++) {
                        /** Only numbered workspaces: special/named ones are not dots. */
                        var ws = parseInt(list[i].name);
                        if (!(ws >= 1))
                            continue;
                        var mon = list[i].monitor;
                        if (!mon)
                            continue;
                        if (!map[mon])
                            map[mon] = [];
                        map[mon].push(ws);
                    }
                    root.liveByMonitor = map;
                }
                if (root.livePending) {
                    root.livePending = false;
                    liveProc.running = true;
                }
            }
        }
    }

    Connections {
        target: Hyprland
        /**
         * Only the events that change which workspaces exist or which monitor
         * they sit on. A plain switch between existing workspaces changes
         * neither, and re-spawning hyprctl on every switch isn't worth it.
         */
        function onRawEvent(event) {
            switch (event.name) {
            case "configreloaded":
            case "createworkspacev2":
            case "destroyworkspacev2":
            case "moveworkspacev2":
            case "renameworkspace":
            case "monitoraddedv2":
            case "monitorremoved":
                root.refresh();
                break;
            }
        }
    }

    Component.onCompleted: refresh()
}

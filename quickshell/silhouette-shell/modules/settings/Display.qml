pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../utils/lua/monitors.js" as Mon
import qs.services
import qs.modules.controlcenter

/**
 * 画 DISPLAY sub-surface. A proportional mini-map of the monitor layout sits on
 * top: one tile per output (scaled from logical size, placed by real x/y), the
 * main monitor wears a star, clicking a tile selects it and dragging one snaps
 * it left/right/above/below the other monitor as a pending move. Below the map
 * a single card edits the selected output: resolution, refresh and scale from
 * availableModes, plus a Set as main toggle on non-main outputs.
 *
 * Apply hands mode/position/scale to display-apply.sh, which snapshots the old
 * spec, evals the new one through `hl.monitor` and arms a detached 12s watchdog
 * that reverts if the change is not confirmed — so a mode that blanks the
 * screen heals itself even if the pill dies. A confirmed Keep clears the
 * watchdog and persists by rewriting only that output's block in monitors.lua.
 * A main swap needs no revert: on Apply it exchanges the two workspace_rule
 * loops' monitors in monitors.lua (ground truth for who is main: the loop that
 * carries workspace 1) and marks the output primary for XWayland via xrandr.
 *
 * monitors.lua is held as in-memory text after the first read and every rewrite
 * goes through it, so a main swap and a later Keep in the same session never
 * clobber each other through a stale FileView cache. The card rows join the
 * surface row registry, so hover, the soul seam and keyboard focus behave like
 * the other settings surfaces.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    readonly property string monitorsPath: Quickshell.env("HOME") + "/.config/hypr/modules/monitors.lua"
    readonly property string helper: Quickshell.env("HOME") + "/.config/hypr/scripts/display-apply.sh"

    property var monitors: []
    property string pendingOut: ""
    property string openPicker: ""
    property int countdown: 0
    property string note: ""
    property bool quietRead: false

    property string selName: ""
    property string mainName: ""
    property string luaText: ""

    /** Pending arrangement from a map drag: `{ name, side }`, or null. */
    property var pendingMove: null

    readonly property var selMon: monitorByName(selName)
    readonly property bool selIsMain: selMon !== null && selMon.name === mainName

    readonly property var scaleOptions: [
        { label: "1.0", value: 1 },
        { label: "1.25", value: 1.25 },
        { label: "1.5", value: 1.5 },
        { label: "2.0", value: 2 }
    ]

    onActiveChanged: {
        if (active) {
            cancelCountdown();
            readProc.running = true;
        } else {
            cancelCountdown();
            openPicker = "";
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    onSelMonChanged: if (selMon) card.syncToCurrent()

    rows: {
        void root.selMon;
        void root.mainName;
        var e = [
            { item: card.resRow, kind: "scrub", bump: function (d) { card.bumpRes(d); } },
            { item: card.rateRow, kind: "scrub", bump: function (d) { card.bumpRate(d); } },
            { item: card.scaleRow, kind: "seg", vals: root.scaleOptions.map(function (o) { return o.value; }), get: function () { return card.pickScale; }, set: function (v) { card.pickScale = v; } }
        ];
        if (root.selMon && !root.selIsMain)
            e.push({ item: card.mainRow, kind: "toggle", get: function () { return card.pendingMain; }, set: function (v) { card.pendingMain = v; } });
        return e;
    }

    /**
     * Reduces a monitor's parsed modes to the list of distinct WxH, each carrying
     * the descending list of whole-number Hz offered for that resolution. The
     * native (current width/height) resolution sorts first, then the rest by
     * pixel count descending, so the default selection lands on the panel's real
     * mode.
     */
    function resolutionsFor(mon) {
        var byRes = {};
        for (var i = 0; i < mon.modes.length; i++) {
            var m = mon.modes[i];
            var key = m.w + "x" + m.h;
            if (!byRes[key])
                byRes[key] = { w: m.w, h: m.h, key: key, rates: [] };
            if (byRes[key].rates.indexOf(m.hz) === -1)
                byRes[key].rates.push(m.hz);
        }
        var list = [];
        for (var k in byRes) {
            byRes[k].rates.sort(function (a, b) { return b - a; });
            list.push(byRes[k]);
        }
        list.sort(function (a, b) {
            if (a.w === mon.width && a.h === mon.height) return -1;
            if (b.w === mon.width && b.h === mon.height) return 1;
            return (b.w * b.h) - (a.w * a.h);
        });
        return list;
    }

    function monitorByName(name) {
        for (var i = 0; i < monitors.length; i++)
            if (monitors[i].name === name)
                return monitors[i];
        return null;
    }

    /** The first monitor that is not `name`; the anchor for placement moves. */
    function otherMonitor(name) {
        for (var i = 0; i < monitors.length; i++)
            if (monitors[i].name !== name)
                return monitors[i];
        return null;
    }

    /**
     * Logical x/y of a monitor of `myW`x`myH` placed on `side` of `other`, top
     * or left edge aligned with the anchor. Negative coordinates are fine for
     * Hyprland, so left/above of an origin monitor need no re-anchoring.
     */
    function placementXY(other, side, myW, myH) {
        var oW = Math.round(other.width / other.scale);
        var oH = Math.round(other.height / other.scale);
        if (side === "left")
            return { x: other.x - myW, y: other.y };
        if (side === "above")
            return { x: other.x, y: other.y - myH };
        if (side === "below")
            return { x: other.x, y: other.y + oH };
        return { x: other.x + oW, y: other.y };
    }

    /** The pending-move x/y for `mon` using the card's current size picks, or null. */
    function pendingXY(mon) {
        if (!pendingMove || pendingMove.name !== mon.name)
            return null;
        var other = otherMonitor(mon.name);
        if (!other || card.resolutions.length === 0)
            return null;
        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
        return placementXY(other, pendingMove.side,
            Math.round(res.w / card.pickScale), Math.round(res.h / card.pickScale));
    }

    /**
     * A dropped tile snaps to whichever side of the other monitor its centre
     * ended on, judged in tile-normalised offsets so flat and tall layouts bias
     * the same. A drop that lands the monitor back on its current x/y clears
     * the pending move instead of arming a no-op.
     */
    function dropTile(name, cx, cy) {
        var mon = monitorByName(name);
        var other = otherMonitor(name);
        if (!mon || !other)
            return;
        var oT = null;
        var tiles = mapLayout.tiles;
        for (var i = 0; i < tiles.length; i++)
            if (tiles[i].name !== name) { oT = tiles[i]; break; }
        if (!oT)
            return;
        var nx = (cx - (oT.x + oT.w / 2)) / oT.w;
        var ny = (cy - (oT.y + oT.h / 2)) / oT.h;
        var side = Math.abs(nx) >= Math.abs(ny) ? (nx < 0 ? "left" : "right") : (ny < 0 ? "above" : "below");
        var res = card.resolutions.length > 0 ? card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)] : null;
        var myW = res ? Math.round(res.w / card.pickScale) : Math.round(mon.width / mon.scale);
        var myH = res ? Math.round(res.h / card.pickScale) : Math.round(mon.height / mon.scale);
        var p = placementXY(other, side, myW, myH);
        pendingMove = (p.x === mon.x && p.y === mon.y) ? null : { name: name, side: side };
    }

    /**
     * Scaled tile geometry for the mini-map: logical rects (mode over scale,
     * pending move substituted for its monitor) fitted into the map width and a
     * capped height, centred horizontally. Selection and main state stay out of
     * the entries on purpose — they are read per-tile from root, so clicking a
     * tile never rebuilds the Repeater under an active press.
     */
    readonly property var mapLayout: {
        var mons = root.monitors;
        if (mons.length === 0 || monitorMap.width <= 0)
            return { h: 0, tiles: [] };
        var rects = [];
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var i = 0; i < mons.length; i++) {
            var m = mons[i];
            var r = { name: m.name, hz: m.refresh, x: m.x, y: m.y, w: Math.round(m.width / m.scale), h: Math.round(m.height / m.scale) };
            var p = root.pendingXY(m);
            if (p) {
                var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
                r.x = p.x;
                r.y = p.y;
                r.w = Math.round(res.w / card.pickScale);
                r.h = Math.round(res.h / card.pickScale);
            }
            rects.push(r);
            minX = Math.min(minX, r.x);
            minY = Math.min(minY, r.y);
            maxX = Math.max(maxX, r.x + r.w);
            maxY = Math.max(maxY, r.y + r.h);
        }
        var k = Math.min(monitorMap.width / (maxX - minX), (96 * root.s) / (maxY - minY));
        var ox = (monitorMap.width - (maxX - minX) * k) / 2;
        var tiles = rects.map(function (t) {
            return { name: t.name, hz: t.hz, x: ox + (t.x - minX) * k, y: (t.y - minY) * k, w: t.w * k, h: t.h * k };
        });
        return { h: (maxY - minY) * k, tiles: tiles };
    }

    /**
     * monitors.lua as in-memory text: read once, then every rewrite updates it
     * before hitting disk, so back-to-back edits never read a stale file cache.
     */
    function luaNow() {
        if (luaText.length === 0)
            luaText = monitorsFile.text();
        return luaText;
    }

    /** The main monitor is whichever one the workspace-1 rule loop points at. */
    function mainFromLua(text) {
        var re = /for\s+i\s*=\s*(\d+)\s*,\s*(\d+)\s+do\s*\n\s*hl\.workspace_rule\(\{[^}]*monitor\s*=\s*"([^"]+)"/g;
        var m;
        while ((m = re.exec(text)) !== null)
            if (parseInt(m[1], 10) <= 1 && parseInt(m[2], 10) >= 1)
                return m[3];
        return "";
    }

    /**
     * Swaps the monitor names between the two workspace_rule loops, leaving
     * every other byte of the file untouched (loop style, ranges, whitespace).
     * The later name is replaced first so the earlier offset stays valid.
     */
    function swapWorkspaceLoops(text) {
        var re = /(for\s+i\s*=\s*\d+\s*,\s*\d+\s+do\s*\n\s*hl\.workspace_rule\(\{[^}]*monitor\s*=\s*")([^"]+)"/g;
        var hits = [];
        var m;
        while ((m = re.exec(text)) !== null)
            hits.push({ start: m.index + m[1].length, name: m[2] });
        if (hits.length !== 2)
            return { ok: false, text: text };
        var a = hits[0];
        var b = hits[1];
        return { ok: true, text: text.slice(0, a.start) + b.name
            + text.slice(a.start + a.name.length, b.start) + a.name
            + text.slice(b.start + b.name.length) };
    }

    Process {
        id: readProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.monitors = Mon.parse(this.text);
                root.mainName = root.mainFromLua(root.luaNow());
                if (!root.monitorByName(root.selName)) {
                    var main = root.monitorByName(root.mainName);
                    root.selName = main ? main.name : (root.monitors.length > 0 ? root.monitors[0].name : "");
                }
                if (!root.quietRead)
                    root.note = "Changes apply live, no reload. If a mode looks wrong, it reverts on its own after 12s.";
                root.quietRead = false;
            }
        }
    }

    Process {
        id: applyProc
        property string out: ""
        property string mode: ""
        property string position: ""
        property real scale: 1
        command: ["sh", "-c",
            "sh \"$1\" apply \"$2\" \"$3\" \"$4\" \"$5\"",
            "sh", root.helper, out, mode, position, String(scale)]
        onExited: root.startCountdown()
    }

    Process {
        id: keepProc
        property string out: ""
        command: ["sh", "-c", "sh \"$1\" keep \"$2\"", "sh", root.helper, out]
    }

    /** XWayland primary flag; runs only when a main swap is applied. */
    Process {
        id: xrandrProc
        property string out: ""
        command: ["xrandr", "--output", out, "--primary"]
    }

    /**
     * Applies whatever is pending on the selected monitor. A main swap persists
     * at once (it is not a mode change, nothing to revert); mode, scale or a
     * dragged move go to the helper's apply verb and its 12s watchdog. Only
     * availableModes Hz reach the mode string, so an unsupported mode can never
     * be requested.
     */
    function apply() {
        var mon = root.selMon;
        if (!mon || root.pendingOut.length > 0)
            return;
        if (card.pendingMain && !root.selIsMain)
            applyMainSwap(mon.name);
        if (!card.dirty)
            return;
        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
        var hz = res.rates[Math.min(card.rateIndex, res.rates.length - 1)];
        var p = pendingXY(mon);
        applyProc.out = mon.name;
        applyProc.mode = res.w + "x" + res.h + "@" + hz;
        applyProc.position = p ? p.x + "x" + p.y : mon.x + "x" + mon.y;
        applyProc.scale = card.pickScale;
        root.pendingOut = mon.name;
        applyProc.running = true;
    }

    function applyMainSwap(name) {
        var res = swapWorkspaceLoops(luaNow());
        card.pendingMain = false;
        if (!res.ok) {
            note = "Could not rewrite the workspace rules in monitors.lua.";
            return;
        }
        luaText = res.text;
        writer.setText(res.text);
        mainName = mainFromLua(res.text);
        xrandrProc.out = name;
        xrandrProc.running = true;
        if (!card.dirty)
            note = "Saved. " + name + " is the main monitor now.";
    }

    function startCountdown() {
        root.countdown = 12;
        countTimer.start();
    }

    /**
     * Confirm the pending change: clear the helper's watchdog so it will not
     * revert, persist by rewriting that output's block in monitors.lua, then
     * quietly re-read the live layout so the map lands on ground truth.
     */
    function keep() {
        if (root.pendingOut.length === 0)
            return;
        keepProc.out = root.pendingOut;
        keepProc.running = true;
        var res = Mon.setMonitor(luaNow(), applyProc.out, applyProc.mode, applyProc.position, applyProc.scale);
        if (res.ok) {
            luaText = res.text;
            writer.setText(res.text);
        }
        cancelCountdown();
        root.quietRead = true;
        readProc.running = true;
        root.note = "Saved. " + applyProc.out + " set to " + applyProc.mode + " · scale " + applyProc.scale;
    }

    /**
     * Stop the countdown and forget the pending output. Called on Keep, on the
     * watchdog-driven timeout (the helper has already reverted the live mode), and
     * when the surface closes.
     */
    function cancelCountdown() {
        countTimer.stop();
        root.countdown = 0;
        root.pendingOut = "";
    }

    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) {
                root.cancelCountdown();
                root.quietRead = true;
                readProc.running = true;
                root.note = "Reverted — the change was not confirmed in time.";
            }
        }
    }

    FileView {
        id: monitorsFile
        path: root.monitorsPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: writer
        path: root.monitorsPath
        atomicWrites: true
        printErrors: false
        onSaveFailed: (err) => {
            root.note = "Live mode kept, but writing monitors.lua failed.";
            console.log("display: write failed: " + err);
        }
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        height: root.height + root.mBottom * root.s
        clip: true

        SettingsHeader {
            s: root.s
            glyph: "画"
            title: "DISPLAY"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 12 * root.s

            MonitorMap {
                id: monitorMap
                width: parent.width
                height: root.mapLayout.h
                s: root.s
                tiles: root.mapLayout.tiles
                selName: root.selName
                mainName: root.mainName
                pendingMove: root.pendingMove
                canDrag: root.monitors.length >= 2
                busy: root.pendingOut.length > 0
                onTilePressed: (name) => { root.selName = name; }
                onTileDropped: (name, cx, cy) => { root.dropTile(name, cx, cy); }
            }

            MonitorCard {
                id: card
                host: root
            }

            Text {
                width: parent.width
                visible: root.note.length > 0
                text: root.note
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
        }

        Item { width: 1; height: 4 * root.s }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.pendingOut.length > 0
        z: 50
        onClicked: {}
    }
}

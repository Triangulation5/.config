pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../../utils/lua/setDeco.js" as SetDeco
import qs.services
import qs.modules.settings
import qs.components.controls
import qs.components.layout

/**
 * 飾 LOOK sub-surface: edits window-decoration knobs that live in
 * decoration.lua and writes each change straight back to its source so the
 * choice survives a restart. Window gaps, rounding, border, opacity, blur, and
 * shadow all rewrite the Lua and reload Hyprland. Each group is extracted into
 * its own component under look/.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    kanji: "飾"
    label: "LOOK"
    contentExtra: root.mBottom * root.s
    contentClip: true

    /**
     * Row registry, rebound whenever a group folds or a dependent toggle flips.
     * Scrub rows expose a bump that steps their ScrubValue one increment.
     */
    rows: {
        var r = [];
        if (winGrp.open) {
            r.push({ item: winGrp.gapsInRow, kind: "scrub", bump: function (d) { winGrp.gapsInScrub.bump(d); } });
            r.push({ item: winGrp.gapsOutRow, kind: "scrub", bump: function (d) { winGrp.gapsOutScrub.bump(d); } });
            r.push({ item: winGrp.roundRow, kind: "scrub", bump: function (d) { winGrp.roundScrub.bump(d); } });
            r.push({ item: winGrp.roundPowRow, kind: "scrub", bump: function (d) { winGrp.roundPowScrub.bump(d); } });
            r.push({ item: winGrp.borderRow, kind: "scrub", bump: function (d) { winGrp.borderScrub.bump(d); } });
            r.push({ item: winGrp.resizeRow, kind: "toggle", get: function () { return root.resizeOnBorder; }, set: function (v) { root.resizeOnBorder = v; root.writeDeco("resize_on_border", v ? "true" : "false"); } });
            r.push({ item: winGrp.layoutRow, kind: "seg", vals: ["dwindle", "master"], get: function () { return root.layout; }, set: function (v) { root.layout = v; root.writeDeco("layout", "\"" + v + "\""); } });
        }
        if (nightGrp.open) {
            r.push({ item: nightGrp.nlModeRow, kind: "seg", vals: ["off", "on", "scheduled"], get: function () { return Flags.nightLightMode; }, set: function (v) { NightLight.setMode(v); } });
            if (Flags.nightLightMode !== "off")
                r.push({ item: nightGrp.nlTempRow, kind: "scrub", bump: function (d) { nightGrp.nlTempScrub.bump(d); } });
            if (Flags.nightLightMode === "scheduled") {
                r.push({ item: nightGrp.nlOnRow, kind: "scrub", bump: function (d) { nightGrp.nlOnScrub.bump(d); } });
                r.push({ item: nightGrp.nlOffRow, kind: "scrub", bump: function (d) { nightGrp.nlOffScrub.bump(d); } });
            }
        }
        if (shadowGrp.open) {
            r.push({ item: shadowGrp.shEnRow, kind: "toggle", get: function () { return root.shadowOn; }, set: function (v) { root.shadowOn = v; root.writeShadow("enabled", v ? "true" : "false"); } });
            if (root.shadowOn) {
                r.push({ item: shadowGrp.shRangeRow, kind: "scrub", bump: function (d) { shadowGrp.shRangeScrub.bump(d); } });
                r.push({ item: shadowGrp.shPowRow, kind: "scrub", bump: function (d) { shadowGrp.shPowScrub.bump(d); } });
            }
        }
        if (blurGrp.open) {
            r.push({ item: blurGrp.blEnRow, kind: "toggle", get: function () { return root.blurOn; }, set: function (v) { root.blurOn = v; root.writeBlur("enabled", v ? "true" : "false"); } });
            if (root.blurOn) {
                r.push({ item: blurGrp.blSizeRow, kind: "scrub", bump: function (d) { blurGrp.blSizeScrub.bump(d); } });
                r.push({ item: blurGrp.blPassRow, kind: "scrub", bump: function (d) { blurGrp.blPassScrub.bump(d); } });
                r.push({ item: blurGrp.blVibRow, kind: "scrub", bump: function (d) { blurGrp.blVibScrub.bump(d); } });
                r.push({ item: blurGrp.blNoiseRow, kind: "scrub", bump: function (d) { blurGrp.blNoiseScrub.bump(d); } });
            }
        }
        if (opGrp.open) {
            r.push({ item: opGrp.opActRow, kind: "scrub", bump: function (d) { opGrp.opActScrub.bump(d); } });
            r.push({ item: opGrp.opInactRow, kind: "scrub", bump: function (d) { opGrp.opInactScrub.bump(d); } });
        }
        if (pillGrp.open) {
            r.push({ item: pillGrp.pillGapRow, kind: "scrub", bump: function (d) { pillGrp.pillGapScrub.bump(d); } });
            r.push({ item: pillGrp.appGapRow, kind: "scrub", bump: function (d) { pillGrp.appGapScrub.bump(d); } });
            r.push({ item: pillGrp.pillOpRow, kind: "scrub", bump: function (d) { pillGrp.pillOpScrub.bump(d); } });
            r.push({ item: pillGrp.pillBlurRow, kind: "toggle", get: function () { return Flags.pillBlur; }, set: function (v) { Flags.pillBlur = v; root.applyPillBlur(v); } });
            r.push({ item: pillGrp.vimKeysRow, kind: "toggle", get: function () { return Flags.vimKeys; }, set: function (v) { Flags.vimKeys = v; } });
            if (Flags.notchStyle)
                r.push({ item: pillGrp.notchFlareRow, kind: "scrub", bump: function (d) { pillGrp.notchFlareScrub.bump(d); } });
        }
        return r;
    }

    property string note: ""

    readonly property string decoPath: Quickshell.env("HOME") + "/.config/hypr/modules/decoration.lua"
    readonly property string pillBlurRule: 'hl.layer_rule({ name = "pill-blur", match = { namespace = "pill" }, blur = true, ignore_alpha = 0.5 })\n'

    property int gapsIn: 6
    property int gapsOut: 12
    property int rounding: 12
    property int roundingPower: 4
    property int borderSize: 2
    property bool resizeOnBorder: true
    property string layout: "dwindle"
    property bool blurOn: true
    property int blurSize: 8
    property int blurPasses: 3
    property real blurVibrancy: 0.17
    property real blurNoise: 0.01
    property bool shadowOn: true
    property int shadowRange: 12
    property int shadowRenderPower: 3
    property real activeOpacity: 1.0
    property real inactiveOpacity: 1.0

    readonly property var layoutOptions: [
        { label: "Dwindle", value: "dwindle" },
        { label: "Master", value: "master" }
    ]
    readonly property var nightModeOptions: [
        { label: "Off", value: "off" },
        { label: "On", value: "on" },
        { label: "Scheduled", value: "scheduled" }
    ]

    property string decoText: ""
    property var base: ({})

    onActiveChanged: {
        if (active) { decoFile.reload(); seed(); }
        else { focusRowItem = null; kbIndex = -1; }
    }

    /** Seeds every control from the live decoration.lua. */
    function seed() {
        root.decoText = decoFile.text();
        var t = root.decoText;
        var gi = parseInt(SetDeco.getField(t, "gaps_in"), 10);
        root.gapsIn = isNaN(gi) ? 6 : gi;
        var go = parseInt(SetDeco.getField(t, "gaps_out"), 10);
        root.gapsOut = isNaN(go) ? 12 : go;
        var rd = parseInt(SetDeco.getField(t, "rounding"), 10);
        root.rounding = isNaN(rd) ? 12 : rd;
        var rp = parseInt(SetDeco.getField(t, "rounding_power"), 10);
        root.roundingPower = isNaN(rp) ? 4 : rp;
        var bs = parseInt(SetDeco.getField(t, "border_size"), 10);
        root.borderSize = isNaN(bs) ? 2 : bs;
        root.resizeOnBorder = SetDeco.getField(t, "resize_on_border") === "true";
        var lo = SetDeco.getField(t, "layout");
        root.layout = lo.length > 0 ? lo : "dwindle";
        root.blurOn = SetDeco.getBlockField(t, "blur", "enabled") === "true";
        var bz = parseInt(SetDeco.getBlockField(t, "blur", "size"), 10);
        root.blurSize = isNaN(bz) ? 8 : bz;
        var bp = parseInt(SetDeco.getBlockField(t, "blur", "passes"), 10);
        root.blurPasses = isNaN(bp) ? 3 : bp;
        var vb = parseFloat(SetDeco.getBlockField(t, "blur", "vibrancy"));
        root.blurVibrancy = isNaN(vb) ? 0.17 : vb;
        var nz = parseFloat(SetDeco.getBlockField(t, "blur", "noise"));
        root.blurNoise = isNaN(nz) ? 0.01 : nz;
        root.shadowOn = SetDeco.getBlockField(t, "shadow", "enabled") === "true";
        var sr = parseInt(SetDeco.getBlockField(t, "shadow", "range"), 10);
        root.shadowRange = isNaN(sr) ? 12 : sr;
        var sp = parseInt(SetDeco.getBlockField(t, "shadow", "render_power"), 10);
        root.shadowRenderPower = isNaN(sp) ? 3 : sp;
        var ao = parseFloat(SetDeco.getField(t, "active_opacity"));
        root.activeOpacity = isNaN(ao) ? 1.0 : ao;
        var io = parseFloat(SetDeco.getField(t, "inactive_opacity"));
        root.inactiveOpacity = isNaN(io) ? 1.0 : io;
        Flags.pillBlur = SetDeco.hasNamedRule(t, "pill-blur");
        root.base = {
            gapsIn: root.gapsIn, gapsOut: root.gapsOut, rounding: root.rounding,
            roundingPower: root.roundingPower, borderSize: root.borderSize,
            blurSize: root.blurSize, blurPasses: root.blurPasses,
            blurVibrancy: root.blurVibrancy, blurNoise: root.blurNoise,
            shadowRange: root.shadowRange, shadowRenderPower: root.shadowRenderPower,
            activeOpacity: root.activeOpacity, inactiveOpacity: root.inactiveOpacity,
            pillOpacity: Flags.pillOpacity, topGap: Flags.topGap, appGap: Flags.appGap,
            nlTemp: Flags.nightLightTemp, nlOnMin: Flags.nightLightOnMin,
            nlOffMin: Flags.nightLightOffMin, notchFlare: Flags.notchFlare
        };
    }

    function fmtClock(v) {
        var h = Math.floor(v / 60);
        var m = v % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    function writeDeco(name, literal) {
        var res = SetDeco.setField(root.decoText, name, literal);
        if (!res.ok) return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    function writeOpacity(name, literal) {
        writeDeco(name, literal);
        opacityRefresh.command = ["hyprctl", "eval",
            "hl.config({ decoration = { active_opacity = " + root.activeOpacity.toFixed(2)
            + ", inactive_opacity = " + root.inactiveOpacity.toFixed(2) + " } })"];
        opacityRefresh.running = true;
    }

    function writeBlur(name, literal) {
        var res = SetDeco.setBlockField(root.decoText, "blur", name, literal);
        if (!res.ok) return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    function writeShadow(name, literal) {
        var res = SetDeco.setBlockField(root.decoText, "shadow", name, literal);
        if (!res.ok) return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    function applyPillBlur(on) {
        var t = root.decoText;
        var res;
        if (on) {
            if (SetDeco.hasNamedRule(t, "pill-blur")) return;
            res = SetDeco.addNamedRule(t, root.pillBlurRule);
        } else {
            res = SetDeco.removeNamedRule(t, "pill-blur");
        }
        if (!res.ok) return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    FileView { id: decoFile; path: root.decoPath; blockLoading: true; printErrors: false }
    FileView { id: decoWriter; path: root.decoPath; atomicWrites: true; printErrors: false }

    Timer { id: reloadTimer; interval: 250; repeat: false; onTriggered: reloadProc.running = true }

    Process {
        id: reloadProc
        command: ["sh", "-c", "sleep 0.3; hyprctl reload"]
        onExited: function (exitCode) {
            root.note = exitCode === 0 ? "" : "Hyprland reload failed. The change is saved but not applied.";
        }
    }

    Process { id: opacityRefresh; command: [] }


    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12 * root.s
        anchors.rightMargin: 12 * root.s
        spacing: 0

        WindowGroup { id: winGrp; look: root }
        NightLightGroup { id: nightGrp; look: root }
        ShadowGroup { id: shadowGrp; look: root }
        BlurGroup { id: blurGrp; look: root }
        OpacityGroup { id: opGrp; look: root }
        PillGroup { id: pillGrp; look: root }

        Text {
            width: parent.width
            topPadding: 8 * root.s
            visible: root.note.length > 0
            text: root.note
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.25
        }

        Item { width: 1; height: 10 * root.s }
    }
}

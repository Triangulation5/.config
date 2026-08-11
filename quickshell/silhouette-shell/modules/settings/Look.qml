pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../utils/lua/setDeco.js" as SetDeco
import qs.services
import qs.modules.controlcenter
import qs.components.controls

/**
 * 飾 LOOK sub-surface: edits the window-decoration knobs that live in
 * decoration.lua and writes each change straight back to its source so the choice
 * survives a restart. Window gaps, rounding and border size, the two opacity
 * fields and the blur block all rewrite the Lua and reload Hyprland so the change
 * lands at once. Blur fields are rewritten scoped to the `blur` block, since
 * `enabled` is shared with the sibling `shadow` block. The border colours are
 * sourced from the palette pipeline and never touched here. Reached from the
 * settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    /**
     * Row registry, rebound whenever a group folds or a dependent toggle flips so
     * keyboard navigation never lands on a hidden line. Scrub rows expose a bump
     * that steps their ScrubValue one increment.
     */
    rows: {
        var r = [];
        if (winGrp.open) {
            r.push({ item: gapsInRow, kind: "scrub", bump: function (d) { gapsInScrub.bump(d); } });
            r.push({ item: gapsOutRow, kind: "scrub", bump: function (d) { gapsOutScrub.bump(d); } });
            r.push({ item: roundRow, kind: "scrub", bump: function (d) { roundScrub.bump(d); } });
            r.push({ item: roundPowRow, kind: "scrub", bump: function (d) { roundPowScrub.bump(d); } });
            r.push({ item: borderRow, kind: "scrub", bump: function (d) { borderScrub.bump(d); } });
            r.push({ item: resizeRow, kind: "toggle", get: function () { return root.resizeOnBorder; }, set: function (v) { root.resizeOnBorder = v; root.writeDeco("resize_on_border", v ? "true" : "false"); } });
            r.push({ item: layoutRow, kind: "seg", vals: ["dwindle", "master"], get: function () { return root.layout; }, set: function (v) { root.layout = v; root.writeDeco("layout", "\"" + v + "\""); } });
        }
        if (nightGrp.open) {
            r.push({ item: nlModeRow, kind: "seg", vals: ["off", "on", "scheduled"], get: function () { return Flags.nightLightMode; }, set: function (v) { NightLight.setMode(v); } });
            if (Flags.nightLightMode !== "off")
                r.push({ item: nlTempRow, kind: "scrub", bump: function (d) { nlTempScrub.bump(d); } });
            if (Flags.nightLightMode === "scheduled") {
                r.push({ item: nlOnRow, kind: "scrub", bump: function (d) { nlOnScrub.bump(d); } });
                r.push({ item: nlOffRow, kind: "scrub", bump: function (d) { nlOffScrub.bump(d); } });
            }
        }
        if (shadowGrp.open) {
            r.push({ item: shEnRow, kind: "toggle", get: function () { return root.shadowOn; }, set: function (v) { root.shadowOn = v; root.writeShadow("enabled", v ? "true" : "false"); } });
            if (root.shadowOn) {
                r.push({ item: shRangeRow, kind: "scrub", bump: function (d) { shRangeScrub.bump(d); } });
                r.push({ item: shPowRow, kind: "scrub", bump: function (d) { shPowScrub.bump(d); } });
            }
        }
        if (blurGrp.open) {
            r.push({ item: blEnRow, kind: "toggle", get: function () { return root.blurOn; }, set: function (v) { root.blurOn = v; root.writeBlur("enabled", v ? "true" : "false"); } });
            if (root.blurOn) {
                r.push({ item: blSizeRow, kind: "scrub", bump: function (d) { blSizeScrub.bump(d); } });
                r.push({ item: blPassRow, kind: "scrub", bump: function (d) { blPassScrub.bump(d); } });
                r.push({ item: blVibRow, kind: "scrub", bump: function (d) { blVibScrub.bump(d); } });
                r.push({ item: blNoiseRow, kind: "scrub", bump: function (d) { blNoiseScrub.bump(d); } });
            }
        }
        if (opGrp.open) {
            r.push({ item: opActRow, kind: "scrub", bump: function (d) { opActScrub.bump(d); } });
            r.push({ item: opInactRow, kind: "scrub", bump: function (d) { opInactScrub.bump(d); } });
        }
        if (pillGrp.open) {
            r.push({ item: pillGapRow, kind: "scrub", bump: function (d) { pillGapScrub.bump(d); } });
            r.push({ item: appGapRow, kind: "scrub", bump: function (d) { appGapScrub.bump(d); } });
            r.push({ item: pillOpRow, kind: "scrub", bump: function (d) { pillOpScrub.bump(d); } });
            r.push({ item: pillBlurRow, kind: "toggle", get: function () { return Flags.pillBlur; }, set: function (v) { Flags.pillBlur = v; root.applyPillBlur(v); } });
            if (Flags.notchStyle)
                r.push({ item: notchFlareRow, kind: "scrub", bump: function (d) { notchFlareScrub.bump(d); } });
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

    property string decoText: ""

    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    onActiveChanged: {
        if (active) {
            decoFile.reload();
            seed();
        } else {
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    /**
     * Seeds every control from the live decoration.lua. Numbers fall back to the
     * shipped defaults when a field is missing so a partially hand-edited config
     * never leaves a control blank. Blur fields read from the `blur` block so a
     * field name shared with the `shadow` block resolves correctly.
     */
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
            gapsIn: root.gapsIn,
            gapsOut: root.gapsOut,
            rounding: root.rounding,
            roundingPower: root.roundingPower,
            borderSize: root.borderSize,
            blurSize: root.blurSize,
            blurPasses: root.blurPasses,
            blurVibrancy: root.blurVibrancy,
            blurNoise: root.blurNoise,
            shadowRange: root.shadowRange,
            shadowRenderPower: root.shadowRenderPower,
            activeOpacity: root.activeOpacity,
            inactiveOpacity: root.inactiveOpacity,
            pillOpacity: Flags.pillOpacity,
            topGap: Flags.topGap,
            appGap: Flags.appGap,
            nlTemp: Flags.nightLightTemp,
            nlOnMin: Flags.nightLightOnMin,
            nlOffMin: Flags.nightLightOffMin,
            notchFlare: Flags.notchFlare
        };
    }

    /** Minutes-since-midnight rendered as HH:MM for the schedule scrubs. */
    function fmtClock(v) {
        var h = Math.floor(v / 60);
        var m = v % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    readonly property var nightModeOptions: [
        { label: "Off", value: "off" },
        { label: "On", value: "on" },
        { label: "Scheduled", value: "scheduled" }
    ]

    /**
     * Rewrites one top-level decoration.lua field to `literal` (already formatted
     * by the caller) and reloads Hyprland so the change takes effect at once.
     */
    function writeDeco(name, literal) {
        var res = SetDeco.setField(root.decoText, name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Same as writeDeco, but for the two opacity fields. A plain reload re-reads
     * the file yet only animates windows on their next focus change, so a window
     * that was inactive when the value changed keeps its stale alpha. Pushing the
     * value through hl.config hits Hyprland's REFRESH_WINDOW_STATES path, which
     * recomputes every existing window's active/inactive alpha at once. Sends both
     * fields so lowering one then restoring the other never leaves a window stuck,
     * and the push fires even when the value lands back on 1.0.
     */
    function writeOpacity(name, literal) {
        writeDeco(name, literal);
        opacityRefresh.command = ["hyprctl", "eval",
            "hl.config({ decoration = { active_opacity = " + root.activeOpacity.toFixed(2)
            + ", inactive_opacity = " + root.inactiveOpacity.toFixed(2) + " } })"];
        opacityRefresh.running = true;
    }

    /**
     * Rewrites one field inside the `blur` block to `literal` and reloads
     * Hyprland. Scoping to the block keeps `enabled` from hitting the sibling
     * `shadow` block's `enabled` first.
     */
    function writeBlur(name, literal) {
        var res = SetDeco.setBlockField(root.decoText, "blur", name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Rewrites one field inside the `shadow` block to `literal` and reloads
     * Hyprland. Scoped to the block so `enabled` lands on shadow, not the sibling
     * `blur` block.
     */
    function writeShadow(name, literal) {
        var res = SetDeco.setBlockField(root.decoText, "shadow", name, literal);
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    /**
     * Adds or removes the pill-blur layer_rule in decoration.lua and reloads
     * Hyprland so the frosted-glass effect behind the pill turns on or off at
     * once. The rule lives in the Lua source (the live config parser rejects a
     * runtime `layerrule` keyword), so it has to be written, not pushed.
     */
    function applyPillBlur(on) {
        var t = root.decoText;
        var res;
        if (on) {
            if (SetDeco.hasNamedRule(t, "pill-blur"))
                return;
            res = SetDeco.addNamedRule(t, root.pillBlurRule);
        } else {
            res = SetDeco.removeNamedRule(t, "pill-blur");
        }
        if (!res.ok)
            return;
        root.decoText = res.text;
        decoWriter.setText(res.text);
        reloadTimer.restart();
    }

    FileView {
        id: decoFile
        path: root.decoPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: decoWriter
        path: root.decoPath
        atomicWrites: true
        printErrors: false
    }

    /**
     * Reload is debounced so a scrub drag writes the file per step but reloads
     * Hyprland once, and captured so a failed reload surfaces as the inline note
     * instead of vanishing with a detached process.
     */
    Timer {
        id: reloadTimer
        interval: 250
        repeat: false
        onTriggered: reloadProc.running = true
    }

    Process {
        id: reloadProc
        command: ["sh", "-c", "sleep 0.3; hyprctl reload"]
        onExited: function (exitCode) {
            root.note = exitCode === 0 ? "" : "Hyprland reload failed. The change is saved but not applied.";
        }
    }

    Process {
        id: opacityRefresh
        command: []
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
            glyph: "飾"
            title: "LOOK"
            showBack: true
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 0

            Group { id: winGrp; s: root.s; title: "Window"; open: true

            FieldRow {
                surface: root
                id: gapsInRow
                label: "Gaps inner"
                caption: "Space between tiled windows"
                icon: "app-window"
                ScrubValue {
                    id: gapsInScrub
                    s: root.s
                    value: root.gapsIn
                    openValue: root.base.gapsIn
                    from: 0; to: 40; step: 1; unit: "px"
                    onEdited: v => {
                        root.gapsIn = v;
                        root.writeDeco("gaps_in", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: gapsOutRow
                label: "Gaps outer"
                caption: "Space to the screen edge"
                icon: "monitor"
                ScrubValue {
                    id: gapsOutScrub
                    s: root.s
                    value: root.gapsOut
                    openValue: root.base.gapsOut
                    from: 0; to: 60; step: 1; unit: "px"
                    onEdited: v => {
                        root.gapsOut = v;
                        root.writeDeco("gaps_out", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: roundRow
                label: "Rounding"
                caption: "Corner radius in pixels"
                icon: "record"
                ScrubValue {
                    id: roundScrub
                    s: root.s
                    value: root.rounding
                    openValue: root.base.rounding
                    from: 0; to: 30; step: 1; unit: "px"
                    onEdited: v => {
                        root.rounding = v;
                        root.writeDeco("rounding", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: roundPowRow
                label: "Rounding power"
                caption: "Higher bends corners to a squircle"
                icon: "sparkles"
                ScrubValue {
                    id: roundPowScrub
                    s: root.s
                    value: root.roundingPower
                    openValue: root.base.roundingPower
                    from: 1; to: 10; step: 1
                    onEdited: v => {
                        root.roundingPower = v;
                        root.writeDeco("rounding_power", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: borderRow
                label: "Border size"
                caption: "Window outline thickness"
                icon: "scaling"
                ScrubValue {
                    id: borderScrub
                    s: root.s
                    value: root.borderSize
                    openValue: root.base.borderSize
                    from: 0; to: 8; step: 1; unit: "px"
                    onEdited: v => {
                        root.borderSize = v;
                        root.writeDeco("border_size", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: resizeRow
                label: "Resize on border"
                caption: "Drag a window edge to resize"
                icon: "mouse"
                LinkToggle {
                    s: root.s
                    on: root.resizeOnBorder
                    onToggled: {
                        root.resizeOnBorder = !root.resizeOnBorder;
                        root.writeDeco("resize_on_border", root.resizeOnBorder ? "true" : "false");
                    }
                }
            }

            FieldRow {
                surface: root
                id: layoutRow
                label: "Layout"
                caption: "Window tiling layout"
                icon: "mixer"
                SettingsSeg {
                    s: root.s
                    options: root.layoutOptions
                    value: root.layout
                    onPicked: v => {
                        root.layout = v;
                        root.writeDeco("layout", "\"" + v + "\"");
                    }
                }
            }

            }

            Group { id: nightGrp; s: root.s; title: "Night light"

            FieldRow {
                surface: root
                id: nlModeRow
                label: "Mode"
                caption: "Off, warm, or auto"
                icon: "moon"
                SettingsSeg {
                    s: root.s
                    options: root.nightModeOptions
                    value: Flags.nightLightMode
                    onPicked: v => NightLight.setMode(v)
                }
            }

            FieldRow {
                surface: root
                id: nlTempRow
                label: "Temperature"
                caption: "Lower is warmer"
                icon: "sun"
                collapsed: Flags.nightLightMode === "off"
                ScrubValue {
                    id: nlTempScrub
                    s: root.s
                    value: Flags.nightLightTemp
                    openValue: root.base.nlTemp
                    from: 2200; to: 6000; step: 100; unit: "K"
                    onEdited: v => NightLight.setTemp(v)
                }
            }

            FieldRow {
                surface: root
                id: nlOnRow
                label: "On at"
                caption: "Warm tint starts"
                icon: "clock"
                collapsed: Flags.nightLightMode !== "scheduled"
                ScrubValue {
                    id: nlOnScrub
                    s: root.s
                    value: Flags.nightLightOnMin
                    openValue: root.base.nlOnMin
                    from: 0; to: 1425; step: 15
                    fmt: root.fmtClock
                    onEdited: v => NightLight.setOnMin(v)
                }
            }

            FieldRow {
                surface: root
                id: nlOffRow
                label: "Off at"
                caption: "Back to neutral"
                icon: "stopwatch"
                collapsed: Flags.nightLightMode !== "scheduled"
                ScrubValue {
                    id: nlOffScrub
                    s: root.s
                    value: Flags.nightLightOffMin
                    openValue: root.base.nlOffMin
                    from: 0; to: 1425; step: 15
                    fmt: root.fmtClock
                    onEdited: v => NightLight.setOffMin(v)
                }
            }

            }

            Group { id: shadowGrp; s: root.s; title: "Shadow"

            FieldRow {
                surface: root
                id: shEnRow
                label: "Enabled"
                caption: "Drop shadow under windows"
                icon: "cloud"
                LinkToggle {
                    s: root.s
                    on: root.shadowOn
                    onToggled: {
                        root.shadowOn = !root.shadowOn;
                        root.writeShadow("enabled", root.shadowOn ? "true" : "false");
                    }
                }
            }

            FieldRow {
                surface: root
                id: shRangeRow
                label: "Range"
                caption: "How far the shadow spreads"
                icon: "scaling"
                collapsed: !root.shadowOn
                ScrubValue {
                    id: shRangeScrub
                    s: root.s
                    value: root.shadowRange
                    openValue: root.base.shadowRange
                    from: 0; to: 50; step: 1; unit: "px"
                    onEdited: v => {
                        root.shadowRange = v;
                        root.writeShadow("range", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: shPowRow
                label: "Render power"
                caption: "Shadow falloff sharpness"
                icon: "bolt"
                collapsed: !root.shadowOn
                ScrubValue {
                    id: shPowScrub
                    s: root.s
                    value: root.shadowRenderPower
                    openValue: root.base.shadowRenderPower
                    from: 1; to: 4; step: 1
                    onEdited: v => {
                        root.shadowRenderPower = v;
                        root.writeShadow("render_power", String(v));
                    }
                }
            }

            }

            Group { id: blurGrp; s: root.s; title: "Blur"

            FieldRow {
                surface: root
                id: blEnRow
                label: "Enabled"
                caption: "Blur behind transparent windows"
                icon: "droplet"
                LinkToggle {
                    s: root.s
                    on: root.blurOn
                    onToggled: {
                        root.blurOn = !root.blurOn;
                        root.writeBlur("enabled", root.blurOn ? "true" : "false");
                    }
                }
            }

            FieldRow {
                surface: root
                id: blSizeRow
                label: "Strength"
                caption: "Blur radius"
                icon: "waves"
                collapsed: !root.blurOn
                ScrubValue {
                    id: blSizeScrub
                    s: root.s
                    value: root.blurSize
                    openValue: root.base.blurSize
                    from: 1; to: 20; step: 1; unit: "px"
                    onEdited: v => {
                        root.blurSize = v;
                        root.writeBlur("size", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: blPassRow
                label: "Passes"
                caption: "More passes, smoother blur"
                icon: "reboot"
                collapsed: !root.blurOn
                ScrubValue {
                    id: blPassScrub
                    s: root.s
                    value: root.blurPasses
                    openValue: root.base.blurPasses
                    from: 1; to: 5; step: 1
                    onEdited: v => {
                        root.blurPasses = v;
                        root.writeBlur("passes", String(v));
                    }
                }
            }

            FieldRow {
                surface: root
                id: blVibRow
                label: "Vibrancy"
                caption: "Color saturation behind the blur"
                icon: "palette"
                collapsed: !root.blurOn
                ScrubValue {
                    id: blVibScrub
                    s: root.s
                    value: root.blurVibrancy
                    openValue: root.base.blurVibrancy
                    from: 0; to: 1; step: 0.01; decimals: 2
                    onEdited: v => {
                        root.blurVibrancy = v;
                        root.writeBlur("vibrancy", v.toFixed(2));
                    }
                }
            }

            FieldRow {
                surface: root
                id: blNoiseRow
                label: "Noise"
                caption: "Grain mixed into the blur"
                icon: "cloud-fog"
                collapsed: !root.blurOn
                ScrubValue {
                    id: blNoiseScrub
                    s: root.s
                    value: root.blurNoise
                    openValue: root.base.blurNoise
                    from: 0; to: 0.2; step: 0.01; decimals: 2
                    onEdited: v => {
                        root.blurNoise = v;
                        root.writeBlur("noise", v.toFixed(2));
                    }
                }
            }

            }

            Group { id: opGrp; s: root.s; title: "Opacity"

            FieldRow {
                surface: root
                id: opActRow
                label: "Active window"
                caption: "Focused window transparency"
                icon: "awake"
                ScrubValue {
                    id: opActScrub
                    s: root.s
                    value: root.activeOpacity
                    openValue: root.base.activeOpacity
                    from: 0.5; to: 1.0; step: 0.05; decimals: 2
                    onEdited: v => {
                        root.activeOpacity = v;
                        root.writeOpacity("active_opacity", v.toFixed(2));
                    }
                }
            }

            FieldRow {
                surface: root
                id: opInactRow
                label: "Inactive window"
                caption: "Unfocused window transparency"
                icon: "moon"
                ScrubValue {
                    id: opInactScrub
                    s: root.s
                    value: root.inactiveOpacity
                    openValue: root.base.inactiveOpacity
                    from: 0.5; to: 1.0; step: 0.05; decimals: 2
                    onEdited: v => {
                        root.inactiveOpacity = v;
                        root.writeOpacity("inactive_opacity", v.toFixed(2));
                    }
                }
            }

            }

            Group { id: pillGrp; s: root.s; title: "Pill"; open: true

            FieldRow {
                surface: root
                id: pillGapRow
                label: "Pill gap"
                caption: "Space above pill. Lower moves it up."
                icon: "chevron-up"
                ScrubValue {
                    id: pillGapScrub
                    s: root.s
                    value: Flags.topGap
                    openValue: root.base.topGap
                    from: -1; to: 2; step: 0.1; decimals: 1
                    onEdited: v => Flags.topGap = v
                }
            }

            FieldRow {
                surface: root
                id: appGapRow
                label: "App gap"
                caption: "Space under pill. Lower moves view up."
                icon: "chevron-down"
                ScrubValue {
                    id: appGapScrub
                    s: root.s
                    value: Flags.appGap
                    openValue: root.base.appGap
                    from: 0; to: 2; step: 0.1; decimals: 1
                    onEdited: v => Flags.appGap = v
                }
            }

            FieldRow {
                surface: root
                id: pillOpRow
                label: "Pill opacity"
                caption: "How see-through the pill sits"
                icon: "sun"
                ScrubValue {
                    id: pillOpScrub
                    s: root.s
                    value: Flags.pillOpacity
                    openValue: root.base.pillOpacity
                    from: 0.55; to: 1.0; step: 0.05; decimals: 2
                    onEdited: v => Flags.pillOpacity = v
                }
            }

            FieldRow {
                surface: root
                id: pillBlurRow
                label: "Pill blur"
                caption: "Frosts pill. Needs opacity under 100%."
                icon: "sparkles"
                LinkToggle {
                    s: root.s
                    on: Flags.pillBlur
                    onToggled: {
                        Flags.pillBlur = !Flags.pillBlur;
                        root.applyPillBlur(Flags.pillBlur);
                    }
                }
            }

            FieldRow {
                surface: root
                id: notchFlareRow
                label: "Notch flare"
                caption: "Flare of both notch ears."
                icon: "bolt"
                collapsed: !Flags.notchStyle
                ScrubValue {
                    id: notchFlareScrub
                    s: root.s
                    value: Flags.notchFlare
                    openValue: root.base.notchFlare
                    from: -7; to: 10; step: 0.25; decimals: 2; unit: "px"
                    onEdited: v => Flags.notchFlare = v
                }
            }

            }

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
}

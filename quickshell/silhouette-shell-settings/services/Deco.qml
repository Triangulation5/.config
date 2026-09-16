pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../utils/lua/deco.js" as SetDeco
import "../utils/lua/anim.js" as SetAnim

/**
 * `~/.config/hypr/modules/decorations.lua` as a live document — the window
 * decoration, blur, shadow, opacity and animation knobs the shell's Look and
 * Animation surfaces edit. (This config keeps the animations table in the same
 * file as the decoration table, so one service owns both rather than two
 * writers racing each other on one path.)
 *
 * Every value is seeded from the file once and kept in memory after that:
 * re-reading while writing would race the writer FileView on the same path and
 * revert a value that was just set. Writes rewrite the field in place and reload
 * Hyprland, so a change applies now and survives a restart. The two opacities
 * are the exception — they also go through `hyprctl eval hl.config(...)`, which
 * is how the shell makes an opacity change land without a full reload.
 *
 * The pill's frost is not a field here: the shell expresses it as a named
 * `hl.layer_rule`, which lives in its own small file (`Paths.pillRule`), so
 * `pillBlur` is derived from that file's text rather than read from a field.
 */
Singleton {
    id: root

    /** Gaps, rounding, border, blur, shadow, opacity, animations. */
    readonly property string path: Paths.decorations
    /** Where the pill's frost layer rule lives. */
    readonly property string rulePath: Paths.pillRule

    /** The document's text as last read or written — the base every write edits. */
    property string text: ""
    property string ruleText: ""
    property bool loaded: false
    /** Non-empty when a write could not be made. */
    property string note: ""

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
    property int shadowPower: 3

    property real activeOpacity: 1.0
    property real inactiveOpacity: 1.0

    property bool animOn: true
    property real animSpeed: 3
    /** The animation set this config builds: liquid, pill or macos. */
    property string animStyle: "macos"

    readonly property var animStyles: ["liquid", "pill", "macos"]
    readonly property var layouts: ["dwindle", "master"]

    /** Derived: whether the pill's frost layer rule is present. */
    property bool pillBlur: true

    /** The layer rule the shell adds and removes for the pill. */
    readonly property string pillBlurRule: 'hl.layer_rule({ name = "pill-blur", match = { namespace = "pill" }, blur = true, ignore_alpha = 0.5 })\n'

    /**
     * Where each field lives in the document: the lua name and the block it
     * belongs to (empty = matched anywhere in the file). Scoping matters because
     * blur and shadow both have an `enabled`.
     */
    readonly property var fieldTargets: ({
        gapsIn: { name: "gaps_in", block: "" },
        gapsOut: { name: "gaps_out", block: "" },
        rounding: { name: "rounding", block: "" },
        roundingPower: { name: "rounding_power", block: "" },
        borderSize: { name: "border_size", block: "" },
        resizeOnBorder: { name: "resize_on_border", block: "" },
        layout: { name: "layout", block: "" },
        blurOn: { name: "enabled", block: "blur" },
        blurSize: { name: "size", block: "blur" },
        blurPasses: { name: "passes", block: "blur" },
        blurVibrancy: { name: "vibrancy", block: "blur" },
        blurNoise: { name: "noise", block: "blur" },
        shadowOn: { name: "enabled", block: "shadow" },
        shadowRange: { name: "range", block: "shadow" },
        shadowPower: { name: "render_power", block: "shadow" },
        activeOpacity: { name: "active_opacity", block: "" },
        inactiveOpacity: { name: "inactive_opacity", block: "" },
        animStyle: { name: "animationStyle", block: "" }
    })

    /** The lua literal one field's value is written as. */
    function literal(field, value) {
        switch (field) {
        case "layout":
        case "animStyle":
            return "\"" + value + "\"";
        case "resizeOnBorder":
        case "blurOn":
        case "shadowOn":
            return value ? "true" : "false";
        case "blurVibrancy":
        case "blurNoise":
        case "activeOpacity":
        case "inactiveOpacity":
            return Number(value).toFixed(2);
        }
        return String(Math.round(value));
    }

    /**
     * Write one field and apply it. This is the only write path rows use, so a
     * `switch` on the field name is the whole write surface of the app.
     */
    function write(field, value) {
        if (field === "pillBlur") {
            writePillBlur(value);
            return;
        }
        if (field === "animOn" || field === "animSpeed") {
            var animRes = field === "animOn"
                ? SetAnim.setEnabled(root.text, value ? "true" : "false")
                : SetAnim.setAllSpeeds(root.text, String(value));
            if (!animRes.ok)
                return;
            root[field] = value;
            root.text = animRes.text;
            writer.setText(animRes.text);
            Hypr.reload();
            return;
        }

        var target = root.fieldTargets[field];
        if (!target)
            return;
        var res = target.block.length > 0
            ? SetDeco.setBlockField(root.text, target.block, target.name, root.literal(field, value))
            : SetDeco.setField(root.text, target.name, root.literal(field, value));
        if (!res.ok) {
            root.note = "Could not find " + target.name + " in " + root.path + ".";
            return;
        }
        root.note = "";
        root[field] = value;
        root.text = res.text;
        writer.setText(res.text);
        if (field === "activeOpacity" || field === "inactiveOpacity")
            applyOpacity();
        else
            Hypr.reload();
    }

    /** Add or remove the pill's frost layer rule, as the shell's Pill group does. */
    function writePillBlur(on) {
        var res;
        if (on) {
            if (SetDeco.hasNamedRule(root.ruleText, "pill-blur"))
                return;
            res = SetDeco.addNamedRule(root.ruleText, root.pillBlurRule);
        } else {
            res = SetDeco.removeNamedRule(root.ruleText, "pill-blur");
        }
        if (!res.ok)
            return;
        root.pillBlur = on;
        root.ruleText = res.text;
        ruleWriter.setText(res.text);
        Hypr.reload();
    }

    /** Opacity lands without a reload: hand the pair straight to the compositor. */
    function applyOpacity() {
        opacityApply.command = ["hyprctl", "eval",
            "hl.config({ decoration = { active_opacity = " + root.activeOpacity.toFixed(2)
            + ", inactive_opacity = " + root.inactiveOpacity.toFixed(2) + " } })"];
        opacityApply.running = true;
    }

    /** Seed every control from the file, falling back to the shipped values. */
    function seed() {
        var t = docFile.text();
        root.text = t;

        root.gapsIn = intOr(SetDeco.getField(t, "gaps_in"), 6);
        root.gapsOut = intOr(SetDeco.getField(t, "gaps_out"), 12);
        root.rounding = intOr(SetDeco.getField(t, "rounding"), 12);
        root.roundingPower = intOr(SetDeco.getField(t, "rounding_power"), 4);
        root.borderSize = intOr(SetDeco.getField(t, "border_size"), 2);
        root.resizeOnBorder = SetDeco.getField(t, "resize_on_border") === "true";
        var lo = SetDeco.getField(t, "layout");
        root.layout = lo.length > 0 ? lo : "dwindle";

        root.blurOn = SetDeco.getBlockField(t, "blur", "enabled") === "true";
        root.blurSize = intOr(SetDeco.getBlockField(t, "blur", "size"), 8);
        root.blurPasses = intOr(SetDeco.getBlockField(t, "blur", "passes"), 3);
        root.blurVibrancy = realOr(SetDeco.getBlockField(t, "blur", "vibrancy"), 0.17);
        root.blurNoise = realOr(SetDeco.getBlockField(t, "blur", "noise"), 0.01);

        root.shadowOn = SetDeco.getBlockField(t, "shadow", "enabled") === "true";
        root.shadowRange = intOr(SetDeco.getBlockField(t, "shadow", "range"), 12);
        root.shadowPower = intOr(SetDeco.getBlockField(t, "shadow", "render_power"), 3);

        root.activeOpacity = realOr(SetDeco.getField(t, "active_opacity"), 1.0);
        root.inactiveOpacity = realOr(SetDeco.getField(t, "inactive_opacity"), 1.0);

        root.animOn = SetAnim.getEnabled(t) === "true";
        var style = SetDeco.getField(t, "animationStyle");
        root.animStyle = style.length > 0 ? style : "macos";
        // The file defines a whole set of curves and leaves per style, one
        // branch after another, so the leaves of the *active* branch are the
        // ones to read: scope the search from the active style's marker.
        var branchAt = t.indexOf('animationStyle == "' + root.animStyle + '"');
        var scoped = branchAt >= 0 ? t.slice(branchAt) : t;
        root.animSpeed = realOr(SetAnim.getLeafSpeed(scoped, "global"), 3);

        root.loaded = true;
    }

    /** Seed the pill's frost state from its own file. */
    function seedRule() {
        root.ruleText = ruleFile.text();
        root.pillBlur = SetDeco.hasNamedRule(root.ruleText, "pill-blur");
    }

    /** `raw` as an integer, or `fallback` when the field is missing or unparsable. */
    function intOr(raw, fallback) {
        var v = parseInt(raw, 10);
        return isNaN(v) ? fallback : v;
    }

    /** `raw` as a number, or `fallback`. */
    function realOr(raw, fallback) {
        var v = parseFloat(raw);
        return isNaN(v) ? fallback : v;
    }

    FileView {
        id: docFile
        path: root.path
        blockLoading: true
        printErrors: false
        onLoaded: root.seed()
    }

    FileView {
        id: writer
        path: root.path
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: ruleFile
        path: root.rulePath
        blockLoading: true
        printErrors: false
        onLoaded: root.seedRule()
    }

    FileView {
        id: ruleWriter
        path: root.rulePath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: opacityApply
        command: []
    }
}

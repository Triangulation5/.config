pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.services
import "../../../utils/lua/setInput.js" as SetInput
import "../../../utils/settings/fields.js" as Fields
import "../utils/lua/insert.js" as Insert

/**
 * The pointer, keyboard and cursor settings, across the three files they live
 * in: `input.lua` (sensitivity, acceleration, layout, repeat, numlock),
 * `env.lua` (cursor size and theme) and `autostart.lua` (the `hyprctl setcursor`
 * call that reapplies the cursor at login).
 *
 * Input fields are written to the file and applied with a reload. The cursor is
 * the exception: `hyprctl setcursor` applies a theme/size pair live, so it is
 * persisted to the env file and the autostart line without a reload.
 *
 * A field the file does not carry yet is inserted into the `input` block rather
 * than skipped — the shell's editors no-op in that case, which leaves a control
 * that accepts a drag and does nothing.
 */
Singleton {
    id: root

    readonly property string path: Paths.input
    readonly property string envPath: Paths.env
    readonly property string autostartPath: Paths.autostart

    property string text: ""
    property string envText: ""
    property string autostartText: ""
    property bool loaded: false
    /** Non-empty when a write could not be made, or was inserted. */
    property string note: ""

    /**
     * A field's shipped value, from the table shared with the shell's own Input
     * surface — the value the read below falls back to when the file does not
     * carry the field, and the one the app's Reset writes back.
     */
    function shipped(field) {
        return Fields.get("input", field).reset;
    }

    property real sensitivity: shipped("sensitivity")
    property string accelProfile: shipped("accelProfile")
    property string kbLayout: shipped("kbLayout")
    property int repeatRate: shipped("repeatRate")
    property int repeatDelay: shipped("repeatDelay")
    property bool numlock: shipped("numlock")
    property int cursorSize: shipped("cursorSize")
    property string cursorTheme: shipped("cursorTheme")

    readonly property var accelProfiles: ["flat", "adaptive"]

    /**
     * The common layouts, which the layout row offers — the table shared with the
     * shell's own Input surface, so the two offer the same list.
     */
    readonly property var kbLayouts: Fields.get("input", "kbLayout").options
    /** Those layouts, plus the one the file actually uses when it is not among them. */
    readonly property var kbLayoutOptions: root.kbLayouts.indexOf(root.kbLayout) >= 0
        ? root.kbLayouts : root.kbLayouts.concat([root.kbLayout])
    /** The options upper-cased; this field carries no name list in the table. */
    readonly property var kbLayoutNames: root.kbLayoutOptions.map(function (l) { return l.toUpperCase(); })

    /** field → the lua name it is written as. */
    readonly property var fieldTargets: ({
        sensitivity: "sensitivity",
        accelProfile: "accel_profile",
        kbLayout: "kb_layout",
        repeatRate: "repeat_rate",
        repeatDelay: "repeat_delay",
        numlock: "numlock_by_default"
    })

    /** The lua literal one field's value is written as. */
    function literal(field, value) {
        switch (field) {
        case "accelProfile":
        case "kbLayout":
            return "\"" + value + "\"";
        case "numlock":
            return value ? "true" : "false";
        case "sensitivity":
            return Number(value).toFixed(2);
        }
        return String(Math.round(value));
    }

    /** Write one field: cursor fields apply live, the rest reload. */
    function write(field, value) {
        if (field === "cursorSize" || field === "cursorTheme") {
            applyCursor(field === "cursorTheme" ? value : root.cursorTheme,
                        field === "cursorSize" ? value : root.cursorSize);
            return;
        }
        var name = root.fieldTargets[field];
        if (!name)
            return;

        var lit = root.literal(field, value);
        var res = SetInput.setField(root.text, name, lit);
        var inserted = false;
        if (!res.ok) {
            res = Insert.insertField(root.text, "input", name, lit);
            inserted = res.ok;
        }
        if (!res.ok) {
            root.note = "Could not find the input block in " + root.path + ".";
            return;
        }
        root.note = inserted ? name + " was not in input.lua; added it." : "";
        root[field] = value;
        root.text = res.text;
        inputWriter.setText(res.text);
        Hypr.reload();
    }

    /**
     * Apply and persist a cursor theme/size pair: live through
     * `hyprctl setcursor`, then into the env file (adding the theme line when the
     * file has no XCURSOR_THEME yet) and the autostart call.
     */
    function applyCursor(theme, size) {
        setcursor.theme = theme;
        setcursor.size = size;
        setcursor.running = true;

        var env = root.envText;
        var e1 = SetInput.setEnv(env, "XCURSOR_THEME", theme);
        var afterTheme = e1.ok ? e1.text : env;
        if (!e1.ok) {
            var ins = Insert.insertEnv(env, "XCURSOR_THEME", theme);
            if (ins.ok) {
                afterTheme = ins.text;
                e1 = { text: ins.text, ok: true };
            }
        }
        var e2 = SetInput.setEnv(afterTheme, "XCURSOR_SIZE", String(size));
        var afterSize = e2.ok ? e2.text : afterTheme;
        if (!e2.ok) {
            var insSize = Insert.insertEnv(afterTheme, "XCURSOR_SIZE", String(size));
            if (insSize.ok) {
                afterSize = insSize.text;
                root.note = "Added XCURSOR_SIZE to env.lua.";
            }
        }
        var e3 = SetInput.setEnv(afterSize, "HYPRCURSOR_SIZE", String(size));

        root.cursorTheme = theme;
        root.cursorSize = size;
        if (e1.ok || e2.ok || e3.ok) {
            root.envText = e3.ok ? e3.text : afterSize;
            envWriter.setText(root.envText);
        }

        var auto = SetInput.setCursorLine(root.autostartText, theme, size);
        if (auto.ok) {
            root.autostartText = auto.text;
            autostartWriter.setText(auto.text);
        }
    }

    /** Seed every control from the three files, falling back to the shipped values. */
    function seed() {
        root.text = inputFile.text();
        root.envText = envFile.text();
        root.autostartText = autostartFile.text();

        var inp = root.text;
        root.sensitivity = realOr(SetInput.getField(inp, "sensitivity"), 0);
        var ap = SetInput.getField(inp, "accel_profile");
        root.accelProfile = ap.length > 0 ? ap : "flat";
        var kl = SetInput.getField(inp, "kb_layout");
        root.kbLayout = kl.length > 0 ? kl : "us";
        root.repeatRate = intOr(SetInput.getField(inp, "repeat_rate"), 25);
        root.repeatDelay = intOr(SetInput.getField(inp, "repeat_delay"), 600);
        root.numlock = SetInput.getField(inp, "numlock_by_default") === "true";

        var env = root.envText;
        root.cursorSize = intOr(SetInput.getField(env, "XCURSOR_SIZE"), 24);
        var ct = SetInput.getField(env, "XCURSOR_THEME");
        root.cursorTheme = ct.length > 0 ? ct : "Bibata-Modern-Ice";

        root.loaded = true;
    }

    /** `raw` as an integer, or `fallback`. */
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
        id: inputFile
        path: root.path
        blockLoading: true
        printErrors: false
        onLoaded: root.seed()
    }

    FileView {
        id: inputWriter
        path: root.path
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: envFile
        path: root.envPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: envWriter
        path: root.envPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: autostartFile
        path: root.autostartPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: autostartWriter
        path: root.autostartPath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: setcursor
        property string theme: ""
        property int size: 24
        command: ["hyprctl", "setcursor", setcursor.theme, String(setcursor.size)]
    }
}

.import "fields.js" as Fields

/**
 * Parses `hyprctl monitors -j` into the slim shape the Display surface needs
 * and rewrites a named `hl.monitor({...})` block's mode/position/scale fields.
 * escapeRe comes from fields.js.
 */

/**
 * Parses one availableModes entry like "2560x1440@279.96Hz" into its parts. The
 * Hz is rounded to a whole number for UI grouping and the apply mode string,
 * while `raw` keeps the original entry for reference. Returns null when the
 * entry does not match the WxH@HZHz shape.
 */
var MODE_RE = /^(\d+)x(\d+)@([\d.]+)Hz$/;

function parseMode(raw) {
    var m = MODE_RE.exec(raw);
    if (!m)
        return null;
    return {
        w: Number(m[1]),
        h: Number(m[2]),
        hz: Math.round(Number(m[3])),
        raw: raw
    };
}

/**
 * Parses the `hyprctl monitors -j` text into the slim shape the Display surface
 * needs: per monitor its name, current width/height/refresh/scale/x/y, its
 * identity (make/model), whether it holds the cursor, and the available modes as
 * `{ w, h, hz, raw }`. Refresh is rounded the same way as a mode's Hz so the
 * current mode can be matched against the list. Modes that do not parse are
 * dropped. Returns [] on bad input.
 *
 * The identity fields are kept because the Display page shows a monitor as itself
 * (a shape, its model underneath) rather than as a bare output name; they are
 * empty on backends that do not report them, and every caller treats them as
 * optional.
 */
function parse(jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(data))
        return [];

    var result = new Array(data.length);

    for (var i = 0; i < data.length; i++) {
        var mon = data[i];
        var available = mon.availableModes || [];
        var modes = [];

        for (var j = 0; j < available.length; j++) {
            var mode = parseMode(available[j]);
            if (mode)
                modes.push(mode);
        }

        result[i] = {
            name: mon.name,
            width: mon.width,
            height: mon.height,
            refresh: Math.round(mon.refreshRate),
            scale: mon.scale,
            x: mon.x,
            y: mon.y,
            make: mon.make || "",
            model: mon.model || "",
            description: mon.description || "",
            focused: mon.focused === true,
            modes: modes
        };
    }

    return result;
}

/**
 * The output monitors.lua makes main: the one named by the `hl.workspace_rule`
 * loop that covers workspace 1. Hyprland has no "main monitor" setting of its
 * own, so a config written as a loop declares it this way and that declaration is
 * worth believing. The regex mirrors the shell's own reader so both surfaces agree
 * on the same output.
 *
 * Returns "" when no loop covers workspace 1 — which includes a config that hands
 * workspaces out as individual rules with `monitor = ""`, as this one does. The
 * caller falls back to the compositor for those (see monitorOfWorkspace).
 */
var MAIN_RE = /for\s+i\s*=\s*(\d+)\s*,\s*(\d+)\s+do\s*\n\s*hl\.workspace_rule\(\{[^}]*monitor\s*=\s*"([^"]+)"/g;

function mainFromLua(luaText) {
    if (!luaText)
        return "";
    MAIN_RE.lastIndex = 0;
    var m;
    while ((m = MAIN_RE.exec(luaText)) !== null)
        if (parseInt(m[1], 10) <= 1 && parseInt(m[2], 10) >= 1)
            return m[3];
    return "";
}

/**
 * `hyprctl workspaces -j` slimmed to `{ id, monitor }`: which output each
 * workspace is on right now. Used for the one thing the compositor knows that a
 * config file can leave unsaid — where workspace 1 (the workspace a config
 * written without a main monitor is describing) actually lives.
 *
 * The number is read from `id` when the report carries one and from `name` when it
 * does not: Hyprland versions differ here, and current ones name a numbered
 * workspace "1" with no numeric field at all. Named workspaces (`special:chat`)
 * have no number and are dropped, as is any entry with no monitor.
 */
function parseWorkspaces(jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(data))
        return [];

    var result = [];
    for (var i = 0; i < data.length; i++) {
        var ws = data[i];
        if (!ws.monitor)
            continue;
        var id = typeof ws.id === "number" ? ws.id : parseInt(ws.name, 10);
        if (isNaN(id))
            continue;
        result.push({ id: id, monitor: ws.monitor });
    }
    return result;
}

/** The output workspace `id` is on, or "" when that workspace does not exist. */
function monitorOfWorkspace(workspaces, id) {
    if (!workspaces)
        return "";
    for (var i = 0; i < workspaces.length; i++)
        if (workspaces[i].id === id)
            return workspaces[i].monitor;
    return "";
}

/**
 * Rewrites only the `hl.monitor({...})` block whose `output = "<output>"`,
 * replacing the `mode`, `position` and `scale` field values and leaving every
 * other character of the file byte-identical (other monitors, workspace_rule
 * loops, whitespace, field order). The block is located by its `output` field,
 * then the closest enclosing `hl.monitor({` ... `})` bounds are taken and each
 * of the three fields is substituted in place within those bounds. Returns
 * `{ text, ok, error }`; ok is false (text unchanged) when the output's block or
 * any of the three fields cannot be found.
 */
function setMonitor(luaText, output, mode, position, scale) {
    var outRe = new RegExp('output\\s*=\\s*"' + Fields.escapeRe(output) + '"');
    var outMatch = outRe.exec(luaText);
    if (!outMatch)
        return { text: luaText, ok: false, error: "output not found: " + output };

    var blockStart = luaText.lastIndexOf("hl.monitor({", outMatch.index);
    if (blockStart === -1)
        return { text: luaText, ok: false, error: "no hl.monitor block for " + output };

    var blockEnd = luaText.indexOf("})", outMatch.index);
    if (blockEnd === -1)
        return { text: luaText, ok: false, error: "unterminated block for " + output };

    var head = luaText.slice(0, blockStart);
    var block = luaText.slice(blockStart, blockEnd);
    var tail = luaText.slice(blockEnd);

    var r1 = replaceField(block, "mode", '"' + mode + '"');
    if (!r1.ok)
        return { text: luaText, ok: false, error: "mode field not found for " + output };

    var r2 = replaceField(r1.text, "position", '"' + position + '"');
    if (!r2.ok)
        return { text: luaText, ok: false, error: "position field not found for " + output };

    var r3 = replaceField(r2.text, "scale", String(scale));
    if (!r3.ok)
        return { text: luaText, ok: false, error: "scale field not found for " + output };

    return { text: head + r3.text + tail, ok: true, error: "" };
}

/**
 * Replaces the value of a single `name = <value>` field within a hl.monitor
 * block, preserving the field name, the `=` spacing and any trailing comma. The
 * value run is a complete double-quoted string when the value is quoted (so a
 * comma inside the quotes is not mistaken for the field end), otherwise the run
 * up to the next comma or the block's closing brace. Returns `{ text, ok }`.
 */
var FIELD_RES = {};

function replaceField(block, name, value) {
    var re = FIELD_RES[name];

    if (!re)
        re = FIELD_RES[name] = new RegExp("(" + name + "\\s*=\\s*)(\"[^\"]*\"|[^,}\\\\n]*)");

    if (!re.test(block))
        return { text: block, ok: false };

    return { text: block.replace(re, "$1" + value), ok: true };
}

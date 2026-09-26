/**
 * Read-only reader for the keybind cheat sheet: every `hl.bind(...)` in a binds
 * file as `{ combo, label, action, locked, repeating }`, in file order.
 *
 * It is deliberately not the shell's `binds.js` parse. That one exists to
 * *rewrite* the file, and it resolves a combo through a variable it assumes is
 * named `mod`; this config declares `mainMod`, so its `parse` would hand back the
 * raw `mainMod .. " + Q"` source instead of the chord. The modifier is read off
 * the file here the way the app's own `spacebinds.js` reads it (see there for
 * why), and nothing in this file writes anything: the page it feeds is a
 * reference, not an editor.
 *
 * The line scanner *is* borrowed from that file (`splitArgs`, `closeParenIndex`,
 * `nameComment`): walking a call past quoted strings and nested braces is the
 * same job whichever side of it you are on, and a second copy would be a second
 * thing to keep in step. Only the two config-specific halves — which variable
 * names the modifier, and how a dispatch is named — are stated here.
 */
.import "../../../../utils/keybinds/binds.js" as Scan
.import "spacebinds.js" as Space

/**
 * A short name for an `exec_cmd(...)` argument.
 *
 * The command is usually a Lua variable (`terminal`, `quickshell`) or a concat
 * of one with a literal, so the literal parts are the readable ones:
 * `quickshell .. " launcher"` is "launcher". With no literal at all the
 * identifier is the name the config gave it, which is what the file itself
 * calls it. A quoted command or an `os.getenv` path is reduced to its script or
 * program name.
 */
function execName(arg) {
    var literal = "";
    var re = /"([^"]*)"/g;
    var m;
    while ((m = re.exec(arg)) !== null)
        literal += m[1];
    var raw = literal.trim().length ? literal.trim() : arg.trim();

    var script = /\/scripts\/([^\/]+)\.sh\b/.exec(raw);
    if (script)
        return script[1];
    if (raw.indexOf("/") >= 0)
        raw = raw.replace(/\/+$/, "").split("/").pop();
    raw = raw.replace(/\.sh$/, "");

    var first = raw.split(/\s+/)[0];
    return first.length ? first : "command";
}

/** "addmaster" -> "Add master", and anything else spelled out after "Layout:". */
function layoutName(v) {
    if (v === "addmaster")
        return "Add master";
    if (v === "removemaster")
        return "Remove master";
    if (v === "cycle")
        return "Cycle layouts";
    return "Layout: " + v;
}

/**
 * A workspace dispatch's target, as words. `"e+1"`/`"e-1"` are Hyprland's
 * relative moves, `"special:x"` a scratchpad; a number is that workspace; a bare
 * identifier is the `for i = 1, 10` loop's variable, which is the whole 1–0 row.
 */
function workspaceTarget(expr, move) {
    var e = expr.trim();
    var lit = /^"([^"]*)"$/.exec(e);
    if (lit) {
        var v = lit[1];
        if (v === "e+1")
            return "Next workspace";
        if (v === "e-1")
            return "Previous workspace";
        var sp = /^special:(.+)$/.exec(v);
        if (sp)
            return (move ? "Move to special " : "Special ") + sp[1];
        return (move ? "Move to workspace " : "Workspace ") + v;
    }
    if (/^\d+$/.test(e))
        return (move ? "Move to workspace " : "Workspace ") + e;
    return move ? "Move to workspace" : "Switch workspace";
}

/**
 * What a bind does, in words, for its row's title. Ordered from the shape with
 * the most structure to the least: the dispatch's own verb first, then the few
 * generic forms, then the dispatch as written so nothing is ever hidden. The
 * argument to read here is the `hl.dsp.` part of the second `hl.bind` argument.
 */
function readable(action) {
    var a = action.replace(/^hl\.dsp\./, "");

    var execArg = /^exec_cmd\(([\s\S]*)\)$/.exec(a);
    if (execArg)
        return execName(execArg[1]);

    var glob = /^global\(\s*"([^"]*)"\s*\)$/.exec(a);
    if (glob)
        return "Shell: " + glob[1].replace(/^quickshell:/, "");

    var special = /^workspace\.toggle_special\(\s*"([^"]*)"\s*\)$/.exec(a);
    if (special)
        return "Special workspace: " + special[1];

    var layout = /^layout\(\s*"([^"]*)"\s*\)$/.exec(a);
    if (layout)
        return layoutName(layout[1]);

    if (/^window\.close\(\)$/.test(a))
        return "Close window";
    if (/^window\.fullscreen\(\)$/.test(a))
        return "Fullscreen";
    if (/^window\.pseudo\(\)$/.test(a))
        return "Pseudo-tile";
    if (/^window\.drag\(\)$/.test(a))
        return "Drag window";

    var floatAct = /^window\.float\(\s*\{[^}]*action\s*=\s*"([^"]*)"[^}]*\}\s*\)$/.exec(a);
    if (floatAct)
        return floatAct[1] === "toggle" ? "Toggle floating" : "Float window";

    var focusDir = /^focus\(\s*\{\s*direction\s*=\s*"([^"]*)"\s*\}\s*\)$/.exec(a);
    if (focusDir)
        return "Focus " + focusDir[1];

    var focusWs = /^focus\(\s*\{\s*workspace\s*=\s*(.+?)\s*\}\s*\)$/.exec(a);
    if (focusWs)
        return workspaceTarget(focusWs[1], false);

    // Relative moves (the nudge keys) carry x/y, not a workspace or direction.
    if (/^window\.move\(\s*\{[^}]*relative\s*=\s*true[^}]*\}\s*\)$/.test(a))
        return "Nudge window";

    var moveDir = /^window\.move\(\s*\{\s*direction\s*=\s*"([^"]*)"\s*\}\s*\)$/.exec(a);
    if (moveDir)
        return "Swap window " + moveDir[1];

    var moveWs = /^window\.move\(\s*\{\s*workspace\s*=\s*(.+?)\s*\}\s*\)$/.exec(a);
    if (moveWs)
        return workspaceTarget(moveWs[1], true);

    // Bare `window.resize()` is the mouse-drag form; the keyboard one carries x/y.
    if (/^window\.resize\(/.test(a))
        return "Resize window";

    return a;
}

/**
 * The full chord an `hl.bind` first argument names. A literal (`"Print"`) and a
 * modifier-relative tail (`mainMod .. " + SHIFT + W"`) both go through
 * `Space.comboOf`; the loop's `mainMod .. " + " .. key` resolves through the tail
 * pattern below, keeping its literal parts and standing an ellipsis where the
 * computed key is, so the sheet still accounts for the twenty binds the
 * workspace loop makes rather than quietly dropping them. Anything else is left
 * as the file writes it, so a chord this cannot read is still shown.
 */
function comboOf(arg, mod, modvar) {
    var direct = Space.comboOf(arg, mod);
    if (direct.length > 0)
        return direct;

    var tail = new RegExp("^\\s*" + modvar + "\\s*\\.\\.\\s*\"([^\"]*)\"\\s*\\.\\.\\s*\\w+\\s*$").exec(arg);
    if (tail)
        return mod + tail[1] + "\u2026";

    return arg.trim();
}

/** One `hl.bind(...)` line as a row, or null when the line holds no bind. */
function parseLine(raw, mod, modvar) {
    var open = raw.indexOf("hl.bind(");
    if (open === -1)
        return null;

    var close = Scan.closeParenIndex(raw, open);
    if (close === -1)
        return null;

    var args = Scan.splitArgs(raw.slice(open + "hl.bind(".length, close));
    if (args.length < 2)
        return null;

    var opts = args.length >= 3 ? args.slice(2).join(", ") : "";
    var name = Scan.nameComment(raw, close);
    var combo = comboOf(args[0], mod, modvar);

    return {
        combo: combo,
        label: name.length ? name : readable(args[1]),
        action: args[1].replace(/^hl\.dsp\./, ""),
        locked: /\blocked\s*=\s*true\b/.test(opts),
        repeating: /\brepeating\s*=\s*true\b/.test(opts)
    };
}

/** Every live `hl.bind(...)` in `text`, in file order. Commented lines are not binds. */
function parse(text) {
    var modvar = Space.modVar(text);
    var mod = Space.modValue(text);
    var lines = String(text).split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        if (Space.commented(lines[i]))
            continue;
        var entry = parseLine(lines[i], mod, modvar);
        if (entry)
            out.push(entry);
    }
    return out;
}

/**
 * Special-workspace binds for the Workspaces page: reading which specials a
 * binds file holds, and adding or removing the pair of binds one space needs.
 *
 * The shell's own Workspaces surface keeps spaces in `spaces.lua` and relies on
 * that file being required by the config, where it binds the keys itself. On this
 * config nothing requires it — the spaces live in `modules/binds.lua` by hand —
 * so a space the app creates would toggle nothing. It therefore writes the binds
 * too, right beside the ones already there:
 *
 *     hl.bind(mainMod .. " + M",         hl.dsp.workspace.toggle_special("chat"))
 *     hl.bind(mainMod .. " + SHIFT + M", hl.dsp.window.move({ workspace = "special:chat" }))
 *
 * Both the modifier variable and its value are read off the file rather than
 * assumed, because the two are not the same everywhere: the shell's keybinds
 * editor writes `mod .. " + X"` (its config declares `local mod = "SUPER"`),
 * while this one declares `local mainMod`. A generated line naming the wrong
 * variable is a reload error, not a missing keybind.
 *
 * Pure string work, no imports: the service that calls these holds the file
 * readers.
 *
 * The key-clash check is here rather than the shell's `Binds.inUse` because that
 * one resolves a combo through the file's own modifier variable, and it only
 * knows the name `mod` — this config declares `mainMod`, so every lookup of a
 * real chord came back "not bound" and the page would have written a second
 * Super+S. `inUse` below reads the variable name off the file like everything
 * else here.
 */

/** The variable a binds file declares its modifier as, e.g. `mainMod`. */
function modVar(text) {
    var m = /local\s+(\w+)\s*=\s*"(SUPER|[A-Z]+)"/.exec(text);
    return m ? m[1] : "mainMod";
}

/** The value of that variable, e.g. `SUPER`. */
function modValue(text) {
    var m = /local\s+\w+\s*=\s*"([A-Z]+)"/.exec(text);
    return m ? m[1] : "SUPER";
}

/** True when the line is commented out — a commented bind is not a live one. */
function commented(line) {
    return /^\s*--/.test(line);
}

/**
 * One bind's first argument, as the file writes it: a literal combo, or a
 * modifier-relative tail. `mainMod .. " + SHIFT + S"` is relative with the tail
 * "SHIFT + S"; `"ALT + RIGHT"` is a literal and already complete.
 */
function comboArg(arg) {
    var literal = /^\s*"([^"]*)"\s*$/.exec(arg);
    if (literal)
        return { name: literal[1], relative: false };
    var tail = /"([^"]*)"\s*$/.exec(arg);
    if (!tail)
        return { name: "", relative: false };
    return { name: tail[1].replace(/^\s*\+\s*/, ""), relative: true };
}

/** `arg` as a complete combo, e.g. `mainMod .. " + SHIFT + S"` -> "SUPER + SHIFT + S". */
function comboOf(arg, mod) {
    var c = comboArg(arg);
    if (c.name.length === 0)
        return "";
    return c.relative ? mod + " + " + c.name : c.name;
}

/** `arg` without its modifier: `mainMod .. " + SHIFT + S"` -> "SHIFT + S". */
function chordOf(arg, mod) {
    var full = comboOf(arg, mod);
    var prefix = mod + " + ";
    return full.indexOf(prefix) === 0 ? full.slice(prefix.length) : full;
}

/**
 * Every combo `text` binds, in file order. A bind whose combo is built at
 * runtime (the `for i = 1, 10` workspace loop) resolves to nothing and is left
 * out: it is not a single chord, so nothing can clash with it by name.
 */
function combos(text) {
    var mod = modValue(text);
    var lines = text.split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        if (commented(lines[i]))
            continue;
        var args = /hl\.bind\(\s*([^,]+),/.exec(lines[i]);
        if (!args)
            continue;
        var combo = comboOf(args[1], mod);
        if (combo.length > 0)
            out.push(combo);
    }
    return out;
}

/** True when `combo` — "SUPER + M" — is already bound in `text`. */
function inUse(text, combo) {
    return combos(text).indexOf(combo) >= 0;
}

/**
 * Every special workspace `text` binds: `{ id, combo, key, lineIndex }` in file
 * order, from the `toggle_special("id")` binds. The combo covers the whole chord
 * minus the modifier — "M" or "SHIFT + M" — so a row can show what it answers to.
 */
function specials(text) {
    var mod = modValue(text);
    var lines = text.split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        if (commented(lines[i]))
            continue;
        var toggle = /toggle_special\(\s*"([^"]+)"\s*\)/.exec(lines[i]);
        if (!toggle)
            continue;
        var args = /hl\.bind\(\s*([^,]+),/.exec(lines[i]);
        var combo = args ? chordOf(args[1], mod) : "";
        out.push({ id: toggle[1], combo: combo, key: combo.replace(/^SHIFT\s*\+\s*/, ""), lineIndex: i });
    }
    return out;
}

/** True when `text` already binds a toggle for `id`. */
function has(text, id) {
    var list = specials(text);
    for (var i = 0; i < list.length; i++)
        if (list[i].id === id)
            return true;
    return false;
}

/** `s` padded with spaces out to `width`, for the file's aligned dispatches. */
function pad(s, width) {
    var out = s;
    while (out.length < width)
        out += " ";
    return out;
}

/**
 * The two lines one space needs — a toggle for the key and a move for the same
 * key with SHIFT — as the file writes them: the modifier variable, then the
 * dispatches aligned on the longer of the two combos.
 */
function lines(mod, id, key) {
    var toggle = "hl.bind(" + mod + ' .. " + ' + key + '",';
    var move = "hl.bind(" + mod + ' .. " + SHIFT + ' + key + '",';
    var width = Math.max(toggle.length, move.length) + 1;
    return [
        pad(toggle, width) + 'hl.dsp.workspace.toggle_special("' + id + '"))',
        pad(move, width) + 'hl.dsp.window.move({ workspace = "special:' + id + '" }))'
    ];
}

/**
 * Adds the toggle/move pair for `id`. The pair goes after the last line that
 * mentions a special workspace, so the file keeps its spaces in one place, and at
 * the end of the file when there is no special in it yet. Returns `{ text, ok }`.
 */
function add(text, id, key) {
    if (has(text, id))
        return { text: text, ok: false, error: "already bound" };

    var lines_ = text.split("\n");
    var at = lines_.length;
    for (var i = lines_.length - 1; i >= 0; i--) {
        if (commented(lines_[i]))
            continue;
        if (/toggle_special|special:/.test(lines_[i])) {
            at = i + 1;
            break;
        }
    }
    // No special in the file: land after the last line that has content, so the
    // pair is never wedged into the file's trailing blank lines.
    if (at === lines_.length) {
        var last = -1;
        for (var j = 0; j < lines_.length; j++)
            if (lines_[j].trim().length > 0)
                last = j;
        at = last + 1;
    }

    var pair = lines(modVar(text), id, key);
    var out = lines_.slice(0, at).concat(pair).concat(lines_.slice(at));
    return { text: out.join("\n"), ok: true, error: "" };
}

/**
 * Removes every live line binding `id` — the toggle and the move. A commented
 * line is left alone: it is the user's own note, not something this page wrote.
 */
function remove(text, id) {
    var lines = text.split("\n");
    var kept = [];
    var dropped = 0;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var drop = !commented(line)
            && (new RegExp('toggle_special\\(\\s*"' + id + '"\\s*\\)').test(line)
                || new RegExp('special:' + id + '\\b').test(line));
        if (drop)
            dropped++;
        else
            kept.push(line);
    }
    return { text: kept.join("\n"), ok: dropped > 0, error: dropped > 0 ? "" : "not in the file" };
}

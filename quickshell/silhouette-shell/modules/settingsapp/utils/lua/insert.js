/**
 * Helpers the shell's field editors do not have: inserting a field that is not
 * in the file yet.
 *
 * `setField` (fields.js) is a no-op when the field is absent, which is the right
 * default for a config the user hand-trimmed — but it also means a setting whose
 * option was never written (this config's input.lua carries no `accel_profile`,
 * `repeat_rate`, `repeat_delay` or `numlock_by_default`) would accept a drag and
 * change nothing. These add the entry inside the block it belongs to, matching
 * the indentation of the entries already there, and are only called after
 * `setField` reports the field missing.
 */

/** The indentation of a block body's first non-empty line, or 4 spaces. */
function firstIndent(body) {
    var lines = body.split("\n");
    for (var i = 1; i < lines.length; i++) {
        var m = /^([ \t]*)\S/.exec(lines[i]);
        if (m)
            return m[1];
    }
    return "    ";
}

/**
 * Adds `name = valueLiteral` as the last entry of the `blockName = { ... }`
 * table, before the closing brace and on a line of its own, inheriting the
 * indentation of the entries already in the block. Returns `{ text, ok }`; ok is
 * false when the block is absent.
 */
function insertField(text, blockName, name, valueLiteral) {
    var head = new RegExp(blockName + "\\s*=\\s*\\{");
    var m = head.exec(text);
    if (!m)
        return { text: text, ok: false };

    var open = m.index + m[0].length - 1;
    var depth = 0;
    for (var i = open; i < text.length; i++) {
        var c = text.charAt(i);
        if (c === "{") {
            depth++;
        } else if (c === "}") {
            depth--;
            if (depth === 0)
                break;
        }
    }
    if (depth !== 0)
        return { text: text, ok: false };

    var body = text.slice(open + 1, i);
    var indent = firstIndent(body);
    var entry = "\n" + indent + name + " = " + valueLiteral + ",";
    // Splice in before the whitespace that sets the closing brace on its own
    // line, so the new entry lands after the last existing one.
    var trailing = /(\n[ \t]*)$/.exec(body);
    var at = trailing ? open + 1 + trailing.index : i;
    return { text: text.slice(0, at) + entry + text.slice(at), ok: true };
}

/**
 * Adds a `hl.env("KEY", "value")` line to env.lua directly after the last env
 * call, so the cursor variables stay together. Returns `{ text, ok }`.
 */
function insertEnv(text, key, valueRaw) {
    var re = /hl\.env\(\s*"[^"]*"\s*,\s*"[^"]*"\s*\)/g;
    var last = null;
    var m;
    while ((m = re.exec(text)) !== null)
        last = m;

    var line = 'hl.env("' + key + '", "' + valueRaw + '")';
    if (!last)
        return { text: text.length === 0 ? line + "\n" : text + "\n" + line + "\n", ok: true };

    var end = last.index + last[0].length;
    return { text: text.slice(0, end) + "\n" + line + text.slice(end), ok: true };
}

/**
 * Appends a monitor block for `output` to monitors.lua. Used when the file only
 * carries the catch-all `output = ""` block: a block naming the output applies
 * to it, and being last it wins over the catch-all.
 */
function appendMonitor(text, output, mode, position, scale) {
    var block = "hl.monitor({\n"
        + "    output   = \"" + output + "\",\n"
        + "    mode     = \"" + mode + "\",\n"
        + "    position = \"" + position + "\",\n"
        + "    scale    = " + scale + ",\n"
        + "})\n";
    var sep = text.length === 0 || text.charAt(text.length - 1) === "\n" ? "\n" : "\n\n";
    return { text: text + sep + block, ok: true };
}

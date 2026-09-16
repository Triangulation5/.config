.import "fields.js" as Fields

/**
 * Read/write helpers for input.lua and the cursor env lines. The shared
 * getField / setField helpers live in fields.js and are re-exported here so the
 * QML side keeps calling SetInput.getField / setField unchanged; setEnv and
 * setCursorLine are specific to this config.
 */

/** Re-exported shared field helpers (see fields.js). */
function getField(text, name) {
    return Fields.getField(text, name);
}

/** Re-exported shared field helpers (see fields.js). */
function setField(text, name, valueLiteral) {
    return Fields.setField(text, name, valueLiteral);
}

/**
 * Replaces the second argument of a `hl.env("KEY", "<old>")` call with the raw
 * value, re-quoted. Returns `{ text, ok }`; ok is false when the key's env call is
 * absent.
 */
function setEnv(text, key, valueRaw) {
    var re = new RegExp("(hl\\.env\\(\\s*\"" + Fields.escapeRe(key) + "\"\\s*,\\s*)\"[^\"]*\"");
    if (!re.test(text))
        return { text: text, ok: false };
    return { text: text.replace(re, "$1\"" + valueRaw + "\""), ok: true };
}

/**
 * Replaces the theme name and size in a `hyprctl setcursor <theme> <size>` call.
 * Returns `{ text, ok }`; ok is false when the call is absent.
 */
function setCursorLine(text, theme, size) {
    var re = /setcursor\s+\S+\s+\d+/;
    if (!re.test(text))
        return { text: text, ok: false };
    return { text: text.replace(re, "setcursor " + theme + " " + size), ok: true };
}

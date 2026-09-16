/**
 * Shared Lua-config field helpers: read and rewrite a `name = <value>` field in
 * place, and escape regex specials. Single source of truth for the helpers the
 * per-target config editors (setDeco / setInput / monitors) previously each
 * carried their own copy of; those files import this one via `.import` and
 * re-export getField/setField so their QML namespaces keep the same API.
 */

/**
 * Reads the current value of a top-level `name = <value>` Lua field. A
 * double-quoted value is returned unquoted; any other run is trimmed. Returns ""
 * when the field is absent.
 */
function getField(text, name) {
    var re = new RegExp("\\b" + name + "\\s*=\\s*(\"[^\"]*\"|[^,}\\n]*)");
    var m = re.exec(text);
    if (!m)
        return "";
    var v = m[1].trim();
    if (v.length >= 2 && v.charAt(0) === "\"" && v.charAt(v.length - 1) === "\"")
        return v.slice(1, -1);
    return v;
}

/**
 * Replaces the value of a single top-level `name = <value>` field in place,
 * preserving the field name, the `=` spacing and any trailing comma. A quoted
 * value run is taken whole so a comma inside the quotes is not mistaken for the
 * field end; otherwise the run goes up to the next comma, brace or newline.
 * `valueLiteral` is already formatted by the caller (a number/bool as-is, a
 * string already double-quoted). Returns `{ text, ok }`; ok is false (text
 * unchanged) when the field is absent.
 */
function setField(text, name, valueLiteral) {
    var re = new RegExp("(\\b" + name + "\\s*=\\s*)(\"[^\"]*\"|[^,}\\n]*)");
    if (!re.test(text))
        return { text: text, ok: false };
    return { text: text.replace(re, "$1" + valueLiteral), ok: true };
}


function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

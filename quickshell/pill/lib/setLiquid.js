/**
 * Sets the `local liquidMotion = <bool>` flag in decorations.lua.
 * Returns { text, ok } where ok is false if the flag wasn't found.
 */
function setLiquidMotion(text, enabled) {
    var value = enabled ? "true" : "false";
    var re = /(local\s+liquidMotion\s*=\s*)(true|false)/;

    if (!re.test(text))
        return { text: text, ok: false };

    return {
        text: text.replace(re, "$1" + value),
        ok: true
    };
}

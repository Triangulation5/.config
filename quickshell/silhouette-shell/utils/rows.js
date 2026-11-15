.import "settings/rows.js" as Rows

/**
 * Re-exported settings row builders (see settings/rows.js).
 */

function of(source, field, type, label, caption, unit, extra) {
    return Rows.of(source, field, type, label, caption, unit, extra);
}

function flag(field, type, label, caption, unit, extra) {
    return Rows.flag(field, type, label, caption, unit, extra);
}

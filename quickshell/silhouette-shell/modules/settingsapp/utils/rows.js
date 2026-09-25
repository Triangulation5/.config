.import "../../../utils/settings/fields.js" as Fields

/**
 * The settings app's row builders.
 *
 * A row states what edits a value — its type, label, caption and unit — and,
 * through `Sources`, where the value lives. What the value *accepts* is a
 * property of the field, shared with the shell's own settings surfaces, and
 * lives in one table (`utils/settings/fields.js`); `of()` reads a row's bounds,
 * step, default and option list from it, so the two UIs cannot offer one field
 * different ranges.
 *
 * It lives here rather than in each page so the builder, and the `key` versus
 * `source`+`field` choice that goes with it, is stated once instead of copied
 * into every page that has a shared field. A `flags` row is named by `key` — the
 * source the app defaults to — and every other source by `source` and `field`,
 * which is what `Pages.rowKey` and `Sources.handler` read.
 */

/**
 * One row for `<source>.<field>`, with its bounds, step, default and option list
 * taken from the shared table. `unit` is passed through rather than read from the
 * table: it is how a control formats a value, not what the field accepts. `extra`
 * carries the rest of that kind of thing (`displayScale`, `format`, `placeholder`)
 * and wins over anything above.
 */
function of(source, field, type, label, caption, unit, extra) {
    const m = Fields.get(source, field) || {};
    var r = {
        type: type, label: label, caption: caption, unit: unit,
        min: m.min, max: m.max, step: m.step,
        options: m.options, names: m.names, reset: m.reset
    };
    if (source === "flags") {
        r.key = field;
    } else {
        r.source = source;
        r.field = field;
    }
    for (var k in (extra || {}))
        r[k] = extra[k];
    return r;
}

/** A row for the flag `field` — the default source, so the row carries `key`. */
function flag(field, type, label, caption, unit, extra) {
    return of("flags", field, type, label, caption, unit, extra);
}

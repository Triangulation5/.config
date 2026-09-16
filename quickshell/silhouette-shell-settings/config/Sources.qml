pragma Singleton

import QtQuick
import Quickshell
import qs.config
import qs.services

/**
 * The one door between a row and the value it edits. A row says where its value
 * lives (`source`: a shell flag in `flags.json`, a field in a Hyprland config
 * file) and this resolves that to a reader and a writer, so no editor has to
 * know which backend it is talking to and no page has to carry a control.
 *
 * `flags` (the default) is the app's own mirror of the shell's state file;
 * `deco` and `input` are the Hyprland config documents (see the services). A
 * fourth source is one entry in the `handlers` map plus the service behind it.
 *
 * A row may also carry its own `get`/`set` closures, which wins over `source` —
 * that is how a page renders rows it can only build at runtime (the per-monitor
 * display rows depend on what is plugged in).
 *
 * Reads happen inside bindings, so they must touch the underlying property
 * directly rather than caching it: `Deco[row.field]` is what makes a row update
 * when the shell, the compositor or another surface changes the value.
 */
Singleton {
    id: root

    /** Rows without an explicit `source` edit a shell flag. */
    readonly property string defaultSource: "flags"

    /** source → { read(row), write(row, value) }. */
    readonly property var handlers: ({
        flags: {
            read: function (row) { return Store.adapter[row.key]; },
            write: function (row, value) { Store.set(row.key, value); }
        },
        deco: {
            read: function (row) { return Deco[row.field]; },
            write: function (row, value) { Deco.write(row.field, value); }
        },
        input: {
            read: function (row) { return Input[row.field]; },
            write: function (row, value) { Input.write(row.field, value); }
        }
    })

    /** The handler a row resolves to, or undefined when it names an unknown source. */
    function handler(row) {
        if (!row)
            return undefined;
        return root.handlers[row.source !== undefined ? row.source : root.defaultSource];
    }

    /** The row's current value, as the row's editor binds it. */
    function read(row) {
        if (!row)
            return undefined;
        if (typeof row.get === "function")
            return row.get();
        var h = root.handler(row);
        return h ? h.read(row) : undefined;
    }

    /** Write `value` back through the row's source. */
    function write(row, value) {
        if (!row)
            return;
        if (typeof row.set === "function") {
            row.set(value);
            return;
        }
        var h = root.handler(row);
        if (h)
            h.write(row, value);
    }

    /** True when the row can be read and written at all. */
    function known(row) {
        if (!row)
            return false;
        if (typeof row.get === "function" && typeof row.set === "function")
            return true;
        return root.handler(row) !== undefined;
    }

    /** The first thing a source had to say about a failed write, or "". */
    readonly property string note: Hypr.note || Deco.note || Input.note || Monitors.note || Spaces.note

    /**
     * The pill's frost is expressed as a layer rule in the config file, but the
     * shell reads its own flag for it: keep the flag in step whenever the file
     * says something different, the way the shell's own seed does.
     */
    Connections {
        target: Deco

        function onPillBlurChanged() {
            Store.set("pillBlur", Deco.pillBlur);
        }
    }
}

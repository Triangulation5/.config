pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

/**
 * Window switcher controller for the launcher (`:w` prefix mode).
 * Filters open Hyprland toplevels by title or class and dispatches focus.
 */
QtObject {
    id: root

    property bool active: false
    property string query: ""

    readonly property var results: {
        if (!root.active)
            return [];
        var tl = Hyprland.toplevels.values;
        var out = [];
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (!t || !t.address || !t.title)
                continue;
            var ipc = t.lastIpcObject;
            out.push({
                address: t.address,
                title: t.title || "",
                cls: (ipc && ipc.class) ? ipc.class : "",
                workspace: (ipc && ipc.workspace) ? ipc.workspace.name : ""
            });
        }
        var q = root.query.toLowerCase();
        if (q.length === 0)
            return out;
        var filtered = [];
        for (var j = 0; j < out.length; j++) {
            var w = out[j];
            if (w.title.toLowerCase().indexOf(q) !== -1 || w.cls.toLowerCase().indexOf(q) !== -1)
                filtered.push(w);
        }
        return filtered;
    }

    function iconForWindow(cls) {
        return AppLauncher.iconForWindow(cls);
    }

    function focusAt(index) {
        if (!root.active || root.results.length === 0 || index < 0 || index >= root.results.length)
            return false;
        var addr = root.results[index].address;
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })');
        return true;
    }
}

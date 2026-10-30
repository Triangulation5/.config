pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    signal layoutChanged()

    property bool editing: false

    readonly property var catalog: [
        { id: "clock", label: "Analog clock", description: "Scalloped analog clock face", minW: 120, minH: 120, maxW: 260, maxH: 260, x: 78, y: 142, w: 164, h: 164 },
        { id: "system", label: "System load", description: "CPU history with memory, GPU, and disk readings", minW: 220, minH: 145, maxW: 420, maxH: 280, x: 304, y: 138, w: 260, h: 168 },
        { id: "moon", label: "Moon calendar", description: "Lunar phase, illumination, and monthly calendar", minW: 250, minH: 160, maxW: 440, maxH: 240, x: 29, y: 321, w: 258, h: 166 },
        { id: "weather", label: "Hourly weather", description: "Current conditions and an hourly temperature chart", minW: 240, minH: 150, maxW: 480, maxH: 280, x: 304, y: 321, w: 260, h: 166 },
        { id: "music", label: "Music", description: "Choose a ticket or a minimal music line", minW: 420, minH: 112, maxW: 720, maxH: 190, x: 29, y: 503, w: 535, h: 122, musicStyle: "ticket" }
    ]

    readonly property var widgets: {
        var saved = Array.isArray(Flags.desktopWidgets) ? Flags.desktopWidgets : [];
        var out = [];
        for (var i = 0; i < root.catalog.length; i++) {
            var spec = root.catalog[i];
            var entry = null;
            for (var j = 0; j < saved.length; j++) {
                if (saved[j] && saved[j].id === spec.id) {
                    entry = saved[j];
                    break;
                }
            }
            var resolved = Object.assign({}, spec, entry || {});
            if (typeof resolved.x !== "number" || !isFinite(resolved.x))
                resolved.x = spec.x;
            if (typeof resolved.y !== "number" || !isFinite(resolved.y))
                resolved.y = spec.y;
            if (typeof resolved.w !== "number" || !isFinite(resolved.w))
                resolved.w = spec.w;
            if (typeof resolved.h !== "number" || !isFinite(resolved.h))
                resolved.h = spec.h;
            out.push(Object.assign(resolved, {
                enabled: entry ? entry.enabled !== false : true
            }));
        }
        return out;
    }

    readonly property var enabledWidgets: {
        var out = [];
        for (var i = 0; i < root.widgets.length; i++)
            if (root.widgets[i].enabled)
                out.push(root.widgets[i]);
        return out;
    }

    readonly property string musicStyle: {
        for (var i = 0; i < root.widgets.length; i++)
            if (root.widgets[i].id === "music")
                return root.widgets[i].musicStyle === "line" ? "line" : "ticket";
        return "ticket";
    }

    function isEnabled(widgetId) {
        for (var i = 0; i < root.widgets.length; i++)
            if (root.widgets[i].id === widgetId)
                return root.widgets[i].enabled;
        return false;
    }

    function widget(widgetId) {
        for (var i = 0; i < root.widgets.length; i++)
            if (root.widgets[i].id === widgetId)
                return root.widgets[i];
        return null;
    }

    function update(widgetId, patch) {
        var next = [];
        for (var i = 0; i < root.widgets.length; i++) {
            var current = root.widgets[i];
            var value = current.id === widgetId ? Object.assign({}, current, patch) : current;
            next.push({
                id: value.id,
                enabled: value.enabled,
                x: value.x,
                y: value.y,
                w: value.w,
                h: value.h,
                musicStyle: value.musicStyle
            });
        }
        Flags.desktopWidgets = next;
        root.layoutChanged();
    }

    function setEnabled(widgetId, enabled) {
        root.update(widgetId, { enabled: enabled });
    }

    function setMusicStyle(style) {
        if (style === "ticket" || style === "line")
            root.update("music", { musicStyle: style });
    }

    function saveGeometry(widgetId, x, y, width, height) {
        root.update(widgetId, {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.round(width),
            h: Math.round(height)
        });
    }

    function resetLayout() {
        var defaults = [
            { id: "clock", enabled: true, x: 78, y: 142, w: 164, h: 164 },
            { id: "system", enabled: true, x: 304, y: 138, w: 260, h: 168 },
            { id: "moon", enabled: true, x: 29, y: 321, w: 258, h: 166 },
            { id: "weather", enabled: true, x: 304, y: 321, w: 260, h: 166 },
            { id: "music", enabled: true, x: 29, y: 503, w: 535, h: 122, musicStyle: "ticket" }
        ];
        Flags.desktopWidgets = defaults;
        root.layoutChanged();
    }

    function startEditing() {
        if (Theme.material)
            root.editing = true;
    }

    function finishEditing() {
        root.editing = false;
    }

    Connections {
        target: Flags
        function onDesktopWidgetsChanged() {
            root.layoutChanged();
        }
        function onStyleChanged() {
            if (!Theme.material)
                root.finishEditing();
        }
    }

    IpcHandler {
        target: "desktop-widgets"
        function edit(): void { root.startEditing(); }
        function close(): void { root.finishEditing(); }
        function toggle(): void {
            if (root.editing)
                root.finishEditing();
            else
                root.startEditing();
        }
    }
}

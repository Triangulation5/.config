pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    signal layoutChanged()

    property bool editing: false
    property bool enabledFlagsMigrated: false

    readonly property var catalog: [
        { id: "clock", label: "Analog clock", description: "Scalloped analog clock face", minW: 120, minH: 120, x: 78, y: 142, w: 164, h: 164 },
        { id: "system", label: "System load", description: "CPU history with memory, GPU, and disk readings", minW: 220, minH: 145, x: 304, y: 138, w: 260, h: 168 },
        { id: "moon", label: "Moon calendar", description: "Lunar phase, illumination, and monthly calendar", minW: 250, minH: 160, x: 29, y: 321, w: 258, h: 166 },
        { id: "weather", label: "Hourly weather", description: "Current conditions and an hourly temperature chart", minW: 240, minH: 150, x: 304, y: 321, w: 260, h: 166 },
        { id: "music", label: "Music", description: "Choose a ticket or a minimal music line", minW: 420, minH: 112, x: 29, y: 503, w: 535, h: 122, musicStyle: "ticket" }
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
                enabled: root.isEnabled(spec.id)
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
    readonly property string clockStyle: ["nebula", "organic", "circle"].indexOf(
        Flags.desktopWidgetClockStyle) >= 0 ? Flags.desktopWidgetClockStyle : "nebula"

    function isEnabled(widgetId) {
        var flag = enabledFlag(widgetId);
        if (typeof flag === "boolean")
            return flag;
        return legacyEnabled(widgetId);
    }

    function legacyEnabled(widgetId) {
        var saved = Array.isArray(Flags.desktopWidgets) ? Flags.desktopWidgets : [];
        for (var j = 0; j < saved.length; j++)
            if (saved[j] && saved[j].id === widgetId)
                return typeof saved[j].enabled === "boolean" ? saved[j].enabled : true;
        return true;
    }

    function migrateEnabledFlags() {
        if (!Flags.ready || root.enabledFlagsMigrated)
            return;
        root.enabledFlagsMigrated = true;
        for (var i = 0; i < root.catalog.length; i++) {
            var widgetId = root.catalog[i].id;
            if (typeof root.enabledFlag(widgetId) !== "boolean")
                root.setEnabledFlag(widgetId, root.legacyEnabled(widgetId));
        }
    }

    function enabledFlag(widgetId) {
        switch (widgetId) {
        case "clock": return Flags.desktopWidgetClockEnabled;
        case "system": return Flags.desktopWidgetSystemEnabled;
        case "moon": return Flags.desktopWidgetMoonEnabled;
        case "weather": return Flags.desktopWidgetWeatherEnabled;
        case "music": return Flags.desktopWidgetMusicEnabled;
        default: return false;
        }
    }

    function setEnabledFlag(widgetId, enabled) {
        switch (widgetId) {
        case "clock": Flags.desktopWidgetClockEnabled = enabled; break;
        case "system": Flags.desktopWidgetSystemEnabled = enabled; break;
        case "moon": Flags.desktopWidgetMoonEnabled = enabled; break;
        case "weather": Flags.desktopWidgetWeatherEnabled = enabled; break;
        case "music": Flags.desktopWidgetMusicEnabled = enabled; break;
        }
        root.layoutChanged();
    }

    function isCatalogWidget(widgetId) {
        for (var i = 0; i < root.catalog.length; i++)
            if (root.catalog[i].id === widgetId)
                return true;
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
    }

    function setEnabled(widgetId, enabled) {
        if (root.isCatalogWidget(widgetId) && typeof enabled === "boolean")
            root.setEnabledFlag(widgetId, enabled);
    }

    function setMusicStyle(style) {
        if (style === "ticket" || style === "line")
            root.update("music", { musicStyle: style });
    }

    function setClockStyle(style) {
        if (style === "nebula" || style === "organic" || style === "circle")
            Flags.desktopWidgetClockStyle = style;
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
        var defaults = [];
        for (var i = 0; i < root.catalog.length; i++) {
            var spec = root.catalog[i];
            var current = root.widget(spec.id);
            defaults.push({
                id: spec.id,
                enabled: current ? current.enabled : true,
                x: spec.x,
                y: spec.y,
                w: spec.w,
                h: spec.h,
                musicStyle: current ? current.musicStyle : spec.musicStyle
            });
        }
        Flags.desktopWidgets = defaults;
    }

    function startEditing() {
        if (Theme.material)
            root.editing = true;
    }

    function finishEditing() {
        root.editing = false;
    }

    Component.onCompleted: root.migrateEnabledFlags()

    Connections {
        target: Flags
        function onReadyChanged() { root.migrateEnabledFlags(); }
        function onDesktopWidgetsChanged() {
            root.layoutChanged();
        }
        function onDesktopWidgetClockEnabledChanged() { root.layoutChanged(); }
        function onDesktopWidgetSystemEnabledChanged() { root.layoutChanged(); }
        function onDesktopWidgetMoonEnabledChanged() { root.layoutChanged(); }
        function onDesktopWidgetWeatherEnabledChanged() { root.layoutChanged(); }
        function onDesktopWidgetMusicEnabledChanged() { root.layoutChanged(); }
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

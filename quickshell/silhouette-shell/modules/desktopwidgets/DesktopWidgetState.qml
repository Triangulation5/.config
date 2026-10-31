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
    /** A reset requested before the local flags file has loaded. */
    property bool resetPending: false
    /** Edits made before flags load, replayed afterward so disk cannot erase them. */
    property var pendingWidgetSettings: ({})
    property string musicStyle: "ticket"
    property string clockStyle: "nebula"
    property string digitalClockStyle: "veil"
    property int focusTimerSeconds: 1500
    property bool focusTimerRunning: false

    Timer {
        interval: 1000
        repeat: true
        running: root.focusTimerRunning
        onTriggered: {
            if (root.focusTimerSeconds > 0)
                root.focusTimerSeconds--;
            if (root.focusTimerSeconds <= 0) {
                root.focusTimerSeconds = 0;
                root.focusTimerRunning = false;
            }
        }
    }

    function formatFocusTimer() {
        var minutes = Math.floor(root.focusTimerSeconds / 60);
        var seconds = root.focusTimerSeconds % 60;
        return (minutes < 10 ? "0" : "") + minutes + ":"
            + (seconds < 10 ? "0" : "") + seconds;
    }

    function toggleFocusTimer() {
        if (root.focusTimerSeconds <= 0)
            root.focusTimerSeconds = 1500;
        root.focusTimerRunning = !root.focusTimerRunning;
    }

    function resetFocusTimer() {
        root.focusTimerRunning = false;
        root.focusTimerSeconds = 1500;
    }

    function makeSpec(id, label, description, category, kind, index) {
        var width = category === "Music" ? 350 : category === "Calendar" ? 258 : 240;
        var height = category === "Music" ? 122 : category === "Calendar" ? 166 : 156;
        if (id === "clock")
            return { id: id, label: label, description: description, category: category, kind: kind,
                minW: 120, minH: 120, x: 1200, y: 40, w: 164, h: 164 };
        if (id === "system")
            return { id: id, label: label, description: description, category: category, kind: kind,
                minW: 220, minH: 145, x: 304, y: 138, w: 260, h: 168 };
        if (id === "moon")
            return { id: id, label: label, description: description, category: category, kind: kind,
                minW: 250, minH: 160, x: 29, y: 321, w: 258, h: 166 };
        if (id === "weather")
            return { id: id, label: label, description: description, category: category, kind: kind,
                minW: 240, minH: 150, x: 304, y: 321, w: 260, h: 166 };
        if (id === "music")
            return { id: id, label: label, description: description, category: category, kind: kind,
                minW: 320, minH: 112, x: 29, y: 503, w: 535, h: 122 };
        return {
            id: id,
            label: label,
            description: description,
            category: category,
            kind: kind,
            minW: Math.min(width, 180),
            minH: 112,
            x: 32 + (index % 5) * 310,
            y: 40 + (Math.floor(index / 5) % 5) * 190,
            w: width,
            h: height
        };
    }

    readonly property var catalog: [
        makeSpec("profileBadge", "Badge", "A compact personal identity card.", "Personal", "profile", 0),
        makeSpec("profileDay", "Your day", "A date and time glance for the day ahead.", "Personal", "date", 1),
        makeSpec("profileStatus", "Status", "A simple personal status card.", "Personal", "status", 2),
        makeSpec("profileMachine", "Machine", "System uptime and device summary.", "Personal", "machine", 3),
        makeSpec("profileShape", "Shape", "A decorative Material shape card.", "Personal", "shape", 4),
        makeSpec("profileRings", "Rings", "A set of live system activity rings.", "Personal", "rings", 5),
        makeSpec("photoFrame", "Photo Frame", "A local image frame; set its path in widget settings.", "Personal", "photo", 6),
        makeSpec("yearAgo", "A year ago", "A date-based year-ago reminder.", "Personal", "yearAgo", 7),
        makeSpec("phone", "Phone", "Connected Bluetooth device and battery glance.", "Personal", "phone", 8),
        makeSpec("countdowns", "Countdowns", "Days remaining until the new year.", "Personal", "countdown", 9),

        makeSpec("music", "Ticket", "Now-playing ticket with transport and seek controls.", "Music", "music", 10),
        makeSpec("musicExpressive", "Expressive", "Now-playing track in an expressive layout.", "Music", "music", 11),
        makeSpec("musicDisc", "Morph Disc", "A circular album-inspired now-playing card.", "Music", "music", 12),
        makeSpec("musicDeck", "Button Deck", "A compact track card with transport actions.", "Music", "music", 13),
        makeSpec("musicRail", "Rail", "A slim now-playing progress rail.", "Music", "music", 14),
        makeSpec("musicPulse", "Pulse", "Now-playing details with a live pulse meter.", "Music", "music", 15),

        makeSpec("digitalClock", "Digital Clock", "A digital clock with selectable face styles.", "Digital Clock", "digitalClock", 16),
        makeSpec("clock", "Analog Clock", "A live analog clock with three selectable faces.", "Analog Clock", "clock", 17),

        makeSpec("weather", "Hourly", "Current conditions and an hourly temperature chart.", "Weather", "weather", 18),
        makeSpec("sunArc", "Sun Arc", "Daylight progress from sunrise to sunset.", "Weather", "sunArc", 19),
        makeSpec("weatherPoster", "Poster", "A weather summary with current conditions.", "Weather", "weatherPoster", 20),
        makeSpec("weatherHours", "Hours", "A compact multi-hour forecast.", "Weather", "weatherHours", 21),
        makeSpec("weatherDayClock", "Day Clock", "A clock face annotated with weather.", "Weather", "weatherDayClock", 22),
        makeSpec("weatherWind", "Wind", "Wind speed and direction at a glance.", "Weather", "weatherWind", 23),

        makeSpec("calendarMini", "Mini", "A compact monthly calendar.", "Calendar", "calendar", 24),
        makeSpec("calendarYarn", "Yarn", "A date-focused calendar with a connected timeline.", "Calendar", "calendar", 25),
        makeSpec("calendarAlmanac", "Almanac", "Month, date, and lunar phase details.", "Calendar", "calendar", 26),
        makeSpec("calendarWindows", "Windows", "A month calendar with week and date markers.", "Calendar", "calendar", 27),
        makeSpec("calendarYear", "Year", "Year progress and current date.", "Calendar", "year", 28),
        makeSpec("moon", "Moon", "Lunar phase, illumination, and monthly calendar.", "Calendar", "moon", 29),

        makeSpec("claudeCode", "Claude Code", "A coding-session status card.", "Productivity", "coding", 30),
        makeSpec("stickyNote", "Note", "A persistent desktop note.", "Productivity", "note", 31),
        makeSpec("pomodoro", "Pomodoro", "A 25-minute focus timer display.", "Productivity", "pomodoro", 32),
        makeSpec("worldClock", "World Clock", "Local time and UTC at a glance.", "Productivity", "worldClock", 33),

        makeSpec("headlines", "Notifications", "Recent notifications from the shell inbox.", "Notifications", "headlines", 34),

        makeSpec("system", "Pulse", "Live CPU history, memory, GPU, and disk readings.", "System", "system", 35),
        makeSpec("sysCores", "Core Garden", "Live CPU, GPU, and memory activity bars.", "System", "cores", 36),
        makeSpec("sysQuad", "Quad Shapes", "Four live system readings in a shape grid.", "System", "quad", 37),
        makeSpec("sysMemory", "Memory Pill", "Memory use and available capacity.", "System", "memory", 38),
        makeSpec("sysBattery", "Battery Capsule", "Battery charge from the system peripheral service.", "System", "battery", 39),
        makeSpec("sysThermals", "Thermals", "CPU and GPU temperatures.", "System", "thermals", 40),
        makeSpec("sysNet", "Net Tide", "Live network upload and download rates.", "System", "network", 41),
        makeSpec("sysOrbit", "Orbit", "Live system load in an orbital display.", "System", "orbit", 42),
        makeSpec("sysChrono", "Chrono", "System uptime in a clock-like display.", "System", "chrono", 43),
        makeSpec("sysSilhouette", "Silhouette", "A compact whole-system status card.", "System", "silhouette", 44)
    ]

    property var widgets: []

    function rebuildWidgets() {
        var saved = root.savedWidgetEntries();
        var out = [];
        for (var i = 0; i < root.catalog.length; i++) {
            out.push(root.resolveWidget(root.catalog[i], saved));
        }
        root.widgets = out;
    }

    readonly property var enabledWidgets: {
        var out = [];
        for (var i = 0; i < root.widgets.length; i++)
            if (root.widgets[i].enabled)
                out.push(root.widgets[i]);
        return out;
    }

    function isEnabled(widgetId) {
        var flag = enabledFlag(widgetId);
        if (typeof flag === "boolean")
            return flag;
        return legacyEnabled(widgetId);
    }

    function savedWidgetEntries() {
        if (!Flags.ready)
            return [];
        var saved = Flags.desktopWidgets;
        return saved && typeof saved.length === "number" ? saved : [];
    }

    function resolveWidget(spec, saved) {
        var entry = null;
        for (var i = 0; i < saved.length; i++) {
            if (saved[i] && saved[i].id === spec.id) {
                entry = saved[i];
                break;
            }
        }
        var pending = root.pendingWidgetSettings[spec.id] || {};
        var resolved = Object.assign({}, spec, entry || {}, pending);
        if (typeof resolved.x !== "number" || !isFinite(resolved.x))
            resolved.x = spec.x;
        if (typeof resolved.y !== "number" || !isFinite(resolved.y))
            resolved.y = spec.y;
        if (typeof resolved.w !== "number" || !isFinite(resolved.w))
            resolved.w = spec.w;
        if (typeof resolved.h !== "number" || !isFinite(resolved.h))
            resolved.h = spec.h;
        resolved.enabled = root.isEnabled(spec.id);
        return resolved;
    }

    function legacyEnabled(widgetId) {
        var pending = root.pendingWidgetSettings[widgetId];
        if (pending && typeof pending.enabled === "boolean")
            return pending.enabled;
        var saved = root.savedWidgetEntries();
        for (var j = 0; j < saved.length; j++)
            if (saved[j] && saved[j].id === widgetId)
                return typeof saved[j].enabled === "boolean" ? saved[j].enabled : true;
        return widgetId === "clock";
    }

    function legacyMusicStyle() {
        var saved = root.savedWidgetEntries();
        for (var i = 0; i < saved.length; i++)
            if (saved[i] && saved[i].id === "music")
                return saved[i].musicStyle === "line" || saved[i].musicStyle === "waveform"
                    ? "waveform" : "ticket";
        return "ticket";
    }

    function syncStyles() {
        root.musicStyle = Flags.desktopWidgetMusicStyle === "waveform"
                || Flags.desktopWidgetMusicStyle === "ticket"
            ? Flags.desktopWidgetMusicStyle : root.legacyMusicStyle();
        root.clockStyle = ["nebula", "organic", "circle"].indexOf(
            Flags.desktopWidgetClockStyle) >= 0 ? Flags.desktopWidgetClockStyle : "nebula";
        var digitalStyles = ["veil", "bloom", "orbit", "script", "stack", "condensed", "display"];
        root.digitalClockStyle = digitalStyles.indexOf(Flags.desktopWidgetDigitalClockStyle) >= 0
            ? Flags.desktopWidgetDigitalClockStyle : "veil";
    }

    function migrateEnabledFlags() {
        if (!Flags.ready || root.enabledFlagsMigrated)
            return;
        root.enabledFlagsMigrated = true;
        var legacyIds = ["clock", "system", "moon", "weather", "music"];
        for (var i = 0; i < legacyIds.length; i++) {
            var widgetId = legacyIds[i];
            if (typeof root.enabledFlag(widgetId) !== "boolean")
                root.setEnabledFlag(widgetId, root.legacyEnabled(widgetId));
        }
        if (Flags.desktopWidgetMusicStyle !== "ticket"
                && Flags.desktopWidgetMusicStyle !== "waveform")
            Flags.desktopWidgetMusicStyle = root.legacyMusicStyle();
        root.syncStyles();
    }

    function enabledFlag(widgetId) {
        switch (widgetId) {
        case "clock": return Flags.desktopWidgetClockEnabled;
        case "system": return Flags.desktopWidgetSystemEnabled;
        case "moon": return Flags.desktopWidgetMoonEnabled;
        case "weather": return Flags.desktopWidgetWeatherEnabled;
        case "music": return Flags.desktopWidgetMusicEnabled;
        default: return null;
        }
    }

    function setEnabledFlag(widgetId, enabled) {
        if (!Flags.ready) {
            root.update(widgetId, { enabled: enabled });
            return;
        }
        switch (widgetId) {
        case "clock": Flags.desktopWidgetClockEnabled = enabled; break;
        case "system": Flags.desktopWidgetSystemEnabled = enabled; break;
        case "moon": Flags.desktopWidgetMoonEnabled = enabled; break;
        case "weather": Flags.desktopWidgetWeatherEnabled = enabled; break;
        case "music": Flags.desktopWidgetMusicEnabled = enabled; break;
        default:
            root.update(widgetId, { enabled: enabled });
            return;
        }
        root.rebuildWidgets();
        root.layoutChanged();
    }

    function isCatalogWidget(widgetId) {
        for (var i = 0; i < root.catalog.length; i++)
            if (root.catalog[i].id === widgetId)
                return true;
        return false;
    }

    function widget(widgetId) {
        var spec = null;
        for (var i = 0; i < root.catalog.length; i++) {
            if (root.catalog[i].id === widgetId) {
                spec = root.catalog[i];
                break;
            }
        }
        if (!spec)
            return null;

        return root.resolveWidget(spec, root.savedWidgetEntries());
    }

    function persistWidgetUpdates(updates) {
        var saved = root.savedWidgetEntries();
        var next = [];
        for (var i = 0; i < root.catalog.length; i++) {
            var spec = root.catalog[i];
            var entry = null;
            for (var j = 0; j < saved.length; j++) {
                if (saved[j] && saved[j].id === spec.id) {
                    entry = saved[j];
                    break;
                }
            }
            var patch = updates[spec.id] || {};
            var value = Object.assign({}, spec, entry || {}, patch);
            var enabled = typeof patch.enabled === "boolean"
                ? patch.enabled : root.isEnabled(spec.id);
            /** Preserve widget-specific settings while updating common geometry. */
            next.push(Object.assign({}, entry || {}, patch, {
                id: spec.id,
                enabled: enabled,
                x: typeof value.x === "number" && isFinite(value.x) ? value.x : spec.x,
                y: typeof value.y === "number" && isFinite(value.y) ? value.y : spec.y,
                w: typeof value.w === "number" && isFinite(value.w) ? value.w : spec.w,
                h: typeof value.h === "number" && isFinite(value.h) ? value.h : spec.h
            }));
        }
        Flags.desktopWidgets = next;
        root.rebuildWidgets();
    }

    function persistPendingWidgetSettings() {
        if (!Flags.ready)
            return;
        var hasPending = false;
        for (var widgetId in root.pendingWidgetSettings) {
            hasPending = true;
            break;
        }
        if (!hasPending)
            return;
        root.persistWidgetUpdates(root.pendingWidgetSettings);
        root.pendingWidgetSettings = ({});
        root.layoutChanged();
    }

    function handleFlagsReady() {
        if (!Flags.ready)
            return;
        if (root.resetPending) {
            root.resetPending = false;
            root.resetLayout();
        }
        root.persistPendingWidgetSettings();
        root.migrateEnabledFlags();
        root.rebuildWidgets();
        root.layoutChanged();
    }

    function update(widgetId, patch) {
        if (!root.isCatalogWidget(widgetId) || !patch)
            return;
        var updates = Object.assign({}, root.pendingWidgetSettings);
        updates[widgetId] = Object.assign({}, updates[widgetId] || {}, patch);
        if (!Flags.ready) {
            root.pendingWidgetSettings = updates;
            root.rebuildWidgets();
            root.layoutChanged();
            return;
        }
        root.persistWidgetUpdates(updates);
        root.pendingWidgetSettings = ({});
        root.layoutChanged();
    }

    function setEnabled(widgetId, enabled) {
        if (!root.isCatalogWidget(widgetId) || typeof enabled !== "boolean")
            return;
        if (root.enabledFlag(widgetId) !== null)
            root.setEnabledFlag(widgetId, enabled);
        else
            root.update(widgetId, { enabled: enabled });
    }

    function setMusicStyle(style) {
        if (style === "ticket" || style === "waveform" || style === "line")
            style = style === "line" ? "waveform" : style;
        else
            return;
        if (Flags.desktopWidgetMusicStyle !== style) {
            Flags.desktopWidgetMusicStyle = style;
        }
        root.musicStyle = style;
        root.layoutChanged();
    }

    function setClockStyle(style) {
        if ((style === "nebula" || style === "organic" || style === "circle")
                && Flags.desktopWidgetClockStyle !== style) {
            Flags.desktopWidgetClockStyle = style;
        }
        if (style === "nebula" || style === "organic" || style === "circle") {
            root.clockStyle = style;
            root.layoutChanged();
        }
    }

    function setDigitalClockStyle(style) {
        var styles = ["veil", "bloom", "orbit", "script", "stack", "condensed", "display"];
        if (styles.indexOf(style) < 0)
            return;
        Flags.desktopWidgetDigitalClockStyle = style;
        root.digitalClockStyle = style;
        root.layoutChanged();
    }

    function isCategoryEnabled(category) {
        for (var i = 0; i < root.catalog.length; i++)
            if (root.catalog[i].category === category && root.isEnabled(root.catalog[i].id))
                return true;
        return false;
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
        if (!Flags.ready) {
            root.pendingWidgetSettings = ({});
            root.resetPending = true;
            return;
        }
        var defaults = [];
        for (var i = 0; i < root.catalog.length; i++) {
            var spec = root.catalog[i];
            defaults.push({
                id: spec.id,
                enabled: spec.id === "clock",
                x: spec.x,
                y: spec.y,
                w: spec.w,
                h: spec.h
            });
        }
        Flags.desktopWidgets = defaults;
        root.rebuildWidgets();
        Flags.desktopWidgetClockEnabled = true;
        Flags.desktopWidgetSystemEnabled = false;
        Flags.desktopWidgetMoonEnabled = false;
        Flags.desktopWidgetWeatherEnabled = false;
        Flags.desktopWidgetMusicEnabled = false;
        Flags.desktopWidgetDigitalClockStyle = "veil";
        root.digitalClockStyle = "veil";
        root.setClockStyle("nebula");
        root.setMusicStyle("ticket");
    }

    function startEditing() {
        if (Theme.material)
            root.editing = true;
    }

    function finishEditing() {
        root.editing = false;
    }

    Component.onCompleted: {
        root.rebuildWidgets();
        root.migrateEnabledFlags();
        if (Flags.ready)
            root.handleFlagsReady();
    }

    Connections {
        target: Flags
        function onReadyChanged() { root.handleFlagsReady(); }
        function onDesktopWidgetsChanged() {
            root.rebuildWidgets();
            root.layoutChanged();
        }
        function onDesktopWidgetClockEnabledChanged() { root.rebuildWidgets(); root.layoutChanged(); }
        function onDesktopWidgetSystemEnabledChanged() { root.rebuildWidgets(); root.layoutChanged(); }
        function onDesktopWidgetMoonEnabledChanged() { root.rebuildWidgets(); root.layoutChanged(); }
        function onDesktopWidgetWeatherEnabledChanged() { root.rebuildWidgets(); root.layoutChanged(); }
        function onDesktopWidgetMusicEnabledChanged() { root.rebuildWidgets(); root.layoutChanged(); }
        function onDesktopWidgetDigitalClockStyleChanged() {
            root.syncStyles();
            root.layoutChanged();
        }
        function onDesktopWidgetMusicStyleChanged() {
            root.syncStyles();
            root.layoutChanged();
        }
        function onDesktopWidgetClockStyleChanged() {
            root.syncStyles();
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

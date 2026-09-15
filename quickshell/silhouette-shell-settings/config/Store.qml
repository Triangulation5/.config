pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The settings app's view of the shell's flags: read/write of the shell's
 * own state file (~/.local/state/ricelin/flags.json) - the same file the
 * shell's Flags service watches (watchChanges + onFileChanged: reload), so
 * a change here is picked up by the live shell instantly: no reload, no
 * IPC. The JsonAdapter mirrors the shell's schema exactly - every property
 * the shell's adapter declares exists here with the same name, type and
 * default - so a write round-trips keys the app never edits (gamePrev*,
 * recordClearedBefore) without dropping them.
 *
 * Reactive access: rows bind Store.adapter.<key> directly (the adapter is a
 * QObject with notifiable properties, so bindings re-evaluate on change -
 * including changes made from the shell side or by Reset). Writes go
 * through set(key, value), which also snapshots into `doc` so the reload
 * diff can ignore our own echoes; `changed(key)` fires only for real
 * external changes.
 */
Singleton {
    id: root

    /** Emitted per key whose value actually changed from outside the app. */
    signal changed(string key)

    /** True once the first load has populated the adapter. */
    readonly property bool ready: loaded

    /** The live flag document: rows bind Store.adapter.<key>. */
    readonly property alias adapter: dataAdapter
    property bool loaded: false
    /** Snapshot of the last-known document, for the reload diff. */
    property var doc: ({})
    /** Monotonic stamp bumped on every external diff change. */
    property int rev: 0

    /**
     * The one write path. Writing the adapter property updates the JSON
     * document and (after a short debounce that coalesces slider drags)
     * hits disk.
     */
    function set(key, value) {
        if (dataAdapter[key] === value)
            return;
        dataAdapter[key] = value;
        root.doc[key] = value;
        root.changed(key);
        saveTimer.restart();
    }

    /** Read one flag - equivalent to binding adapter.<key> directly. */
    function get(key) {
        return dataAdapter[key];
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        onLoaded: root.syncFromDisk()

        JsonAdapter {
            id: dataAdapter
            // == mirrored from the shell's Flags.qml - keep in sync ==
            property bool dnd: false
            property bool keepAwake: false
            property bool time12h: true
            property bool clockSeconds: false
            property bool showGlyphs: false
            property string paletteMode: "static"
            property string wallpaperDir: ""
            property real uiScale: 1.1
            property bool reduceMotion: false
            property int manualHue: 0
            property bool manualDark: true
            property real manualSat: 0.5
            property string uiFont: "JetBrainsMono Nerd Font Mono"
            property real pillOpacity: 1.0
            property bool pillBlur: true
            property real topGap: 0.7
            property real appGap: 1.0
            property bool notchStyle: false
            property real notchFlare: 1
            property bool autoHide: false
            property bool vimKeys: true
            property int recordCountdown: 5
            property string recordDir: ""
            property int recordFps: 60
            property string recordQuality: "high"
            property bool recordCursor: true
            property bool recordMic: true
            property bool recordDesktop: true
            property real recordClearedBefore: 0
            property int idleLockMin: 3
            property int idleScreenOffMin: 0
            property int idleSuspendMin: 0
            property string lockDotsMode: "gpixel"
            property string weatherCity: "WELLAND"
            property bool musicViz: true
            property string vizStyle: "bars"
            property int vizFps: 60
            property string mediaStyle: "bleed"
            property bool gameMode: false
            property bool gamePrevDnd: false
            property bool gamePrevViz: true
            property bool gamePrevAwake: false
            property string nightLightMode: "scheduled"
            property int nightLightTemp: 3600
            property int nightLightOnMin: 1200
            property int nightLightOffMin: 420
        }
    }

    /** Diff the freshly loaded document against our snapshot. */
    function syncFromDisk() {
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i];
            var v = dataAdapter[k];
            if (root.doc[k] !== v) {
                root.doc[k] = v;
                root.changed(k);
                root.rev++;
            }
        }
        root.loaded = true;
    }

    /** Every mirrored flag key, in schema order. */
    readonly property var keys: [
        "dnd", "keepAwake", "time12h", "clockSeconds", "showGlyphs",
        "paletteMode", "wallpaperDir", "uiScale", "reduceMotion",
        "manualHue", "manualDark", "manualSat", "uiFont",
        "pillOpacity", "pillBlur", "topGap", "appGap",
        "notchStyle", "notchFlare", "autoHide", "vimKeys",
        "recordCountdown", "recordDir", "recordFps", "recordQuality",
        "recordCursor", "recordMic", "recordDesktop", "recordClearedBefore",
        "idleLockMin", "idleScreenOffMin", "idleSuspendMin", "lockDotsMode",
        "weatherCity", "musicViz", "vizStyle", "vizFps", "mediaStyle",
        "gameMode", "gamePrevDnd", "gamePrevViz", "gamePrevAwake",
        "nightLightMode", "nightLightTemp", "nightLightOnMin", "nightLightOffMin"
    ]

    Timer {
        id: saveTimer
        interval: 120
        onTriggered: file.writeAdapter()
    }
}

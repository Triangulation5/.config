pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The settings app's view of the shell's flags: read/write of the shell's
 * own state file (~/.local/state/silhouette/flags.json) - the same file the
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
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/silhouette/flags.json"
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
            // The defaults below are the shipped values; Pages' row `reset`
            // fields mirror them for the "Reset to Defaults" button.
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
            property bool auraOn: false
            property real auraStrength: 1.0
            property bool auraShadow: true
            property bool gameMode: false
            property bool gamePrevDnd: false
            property bool gamePrevViz: true
            property bool gamePrevAwake: false
            property string nightLightMode: "scheduled"
            property int nightLightTemp: 3600
            property int nightLightOnMin: 1200
            property int nightLightOffMin: 420
            // -- pill geometry and lifecycle, mirrored from Flags.qml --
            property real pillRestW: 160
            property real pillRestH: 38
            property real pillRestCorner: 28
            property real pillNotchCorner: 18
            property real pillHoverPad: 20
            property real pillHoverH: 172
            property real pillMixerH: 214
            property real pillLauncherW: 360
            property real pillLauncherH: 332
            property real pillClipboardW: 360
            property real pillClipboardH: 332
            property real pillPowerW: 330
            property real pillPowerH: 150
            property real pillBatteryW: 316
            property real pillMediaH: 150
            property real pillTimerW: 340
            property real pillTimerH: 460
            property real pillWallpaperW: 720
            property real pillWallpaperH: 172
            property real pillSettingsW: 392
            property real pillKeybindsW: 460
            property real pillWorkspacesW: 392
            property real pillStashW: 392
            property real pillSpaceappsW: 392
            property real pillSysmonW: 392
            property real pillAppearanceW: 392
            property real pillUpdatesW: 360
            property real pillDisplayW: 392
            property real pillInputW: 392
            property real pillLookW: 392
            property real pillIdlelockW: 392
            property real pillAnimationW: 392
            property real pillRecorderW: 384
            property real pillFontpickerW: 360
            property real pillWeatherW: 400
            property real pillPolkitW: 440
            property real pillOpenCorner: 22
            property real pillToastW: 342
            property real pillQuickChooseW: 344
            property real pillQuickChooseH: 76
            property real pillQuickCountW: 150
            property real pillQuickCountH: 64
            property real pillDragOverW: 300
            property real pillDragOverH: 126
            property real pillGameH: 34
            property bool memorySaver: true
            property int pillSurfaceIdleTimeout: 12
            // -- the shell's own timing, geometry and motion, mirrored from Flags.qml --
            property real cornerNotchRadius: 12
            property real cornerNormalRadius: 8
            property real cornerGameRadius: 0
            property int cornerMorphMs: 1500
            property real cornerShadowSize: 8
            property real motionSpeed: 1.0
            property int pillCleanupSec: 10
            property int pillHoverGraceMs: 300
            property int osdHoldMs: 1800
            property int notifMs: 6000
            property int notifLowMs: 4000
            property real lockPillW: 176
            property real lockPillH: 42
            property real lockAvatarSize: 120
            property int lockBeadMs: 350
            property real lockBlurSpread: 2.4
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
        "auraOn", "auraStrength", "auraShadow",
        "gameMode", "gamePrevDnd", "gamePrevViz", "gamePrevAwake",
        "nightLightMode", "nightLightTemp", "nightLightOnMin", "nightLightOffMin",
        "pillRestW", "pillRestH", "pillRestCorner", "pillNotchCorner", "pillHoverPad",
        "pillHoverH", "pillMixerH", "pillLauncherW", "pillLauncherH", "pillClipboardW",
        "pillClipboardH", "pillPowerW", "pillPowerH", "pillBatteryW", "pillMediaH",
        "pillTimerW", "pillTimerH", "pillWallpaperW",
        "pillWallpaperH", "pillSettingsW", "pillKeybindsW", "pillWorkspacesW", "pillStashW",
        "pillSpaceappsW", "pillSysmonW", "pillAppearanceW", "pillUpdatesW", "pillDisplayW",
        "pillInputW", "pillLookW", "pillIdlelockW", "pillAnimationW", "pillRecorderW",
        "pillFontpickerW", "pillWeatherW", "pillPolkitW", "pillOpenCorner", "pillToastW",
        "pillQuickChooseW", "pillQuickChooseH", "pillQuickCountW", "pillQuickCountH",
        "pillDragOverW", "pillDragOverH", "pillGameH", "memorySaver", "pillSurfaceIdleTimeout",
        "cornerNotchRadius", "cornerNormalRadius", "cornerGameRadius",
        "cornerMorphMs", "cornerShadowSize", "motionSpeed",
        "pillCleanupSec", "pillHoverGraceMs", "osdHoldMs", "notifMs", "notifLowMs",
        "lockPillW", "lockPillH", "lockAvatarSize", "lockBeadMs", "lockBlurSpread"
    ]

    Timer {
        id: saveTimer
        interval: 120
        onTriggered: file.writeAdapter()
    }
}

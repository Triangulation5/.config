pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared session flags persisted to a small JSON file and watched for external
 * change, so every shell daemon (pill, lock) reads and writes the same
 * Do-Not-Disturb and Keep-Awake state live without a second notification server
 * or idle inhibitor. Toggling in one surface updates the others on the next file
 * event, and the state survives a daemon restart.
 */
Singleton {
    id: root

    property alias dnd: adapter.dnd
    property alias keepAwake: adapter.keepAwake
    property alias time12h: adapter.time12h
    property alias clockSeconds: adapter.clockSeconds
    property alias showGlyphs: adapter.showGlyphs
    property alias paletteMode: adapter.paletteMode
    property alias wallpaperDir: adapter.wallpaperDir
    property alias uiScale: adapter.uiScale
    property alias reduceMotion: adapter.reduceMotion
    property alias manualHue: adapter.manualHue
    property alias manualDark: adapter.manualDark
    property alias manualSat: adapter.manualSat
    property alias uiFont: adapter.uiFont
    property alias pillOpacity: adapter.pillOpacity
    property alias pillBlur: adapter.pillBlur
    property alias topGap: adapter.topGap
    property alias appGap: adapter.appGap
    property alias notchStyle: adapter.notchStyle
    property alias notchFlare: adapter.notchFlare
    property alias autoHide: adapter.autoHide
    property alias vimKeys: adapter.vimKeys
    property alias recordCountdown: adapter.recordCountdown
    property alias recordDir: adapter.recordDir
    property alias recordFps: adapter.recordFps
    property alias recordQuality: adapter.recordQuality
    property alias recordCursor: adapter.recordCursor
    property alias recordMic: adapter.recordMic
    property alias recordDesktop: adapter.recordDesktop
    property alias recordClearedBefore: adapter.recordClearedBefore
    property alias idleLockMin: adapter.idleLockMin
    property alias idleScreenOffMin: adapter.idleScreenOffMin
    property alias idleSuspendMin: adapter.idleSuspendMin
    property alias lockDotsMode: adapter.lockDotsMode
    property alias weatherCity: adapter.weatherCity
    property alias musicViz: adapter.musicViz
    property alias vizStyle: adapter.vizStyle
    property alias vizFps: adapter.vizFps
    property alias mediaStyle: adapter.mediaStyle
    property alias auraOn: adapter.auraOn
    property alias auraStrength: adapter.auraStrength
    property alias auraShadow: adapter.auraShadow
    property alias gameMode: adapter.gameMode
    property alias gamePrevDnd: adapter.gamePrevDnd
    property alias gamePrevViz: adapter.gamePrevViz
    property alias gamePrevAwake: adapter.gamePrevAwake
    property alias nightLightMode: adapter.nightLightMode
    property alias nightLightTemp: adapter.nightLightTemp
    property alias nightLightOnMin: adapter.nightLightOnMin
    property alias nightLightOffMin: adapter.nightLightOffMin
    // pill geometry and lifecycle: one flag per tunable size the pill ships with
    property alias pillRestW: adapter.pillRestW
    property alias pillRestH: adapter.pillRestH
    property alias pillRestCorner: adapter.pillRestCorner
    property alias pillNotchCorner: adapter.pillNotchCorner
    property alias pillHoverPad: adapter.pillHoverPad
    property alias pillHoverH: adapter.pillHoverH
    property alias pillMixerH: adapter.pillMixerH
    property alias pillLauncherW: adapter.pillLauncherW
    property alias pillLauncherH: adapter.pillLauncherH
    property alias pillClipboardW: adapter.pillClipboardW
    property alias pillClipboardH: adapter.pillClipboardH
    property alias pillPowerW: adapter.pillPowerW
    property alias pillPowerH: adapter.pillPowerH
    property alias pillBatteryW: adapter.pillBatteryW
    property alias pillMediaH: adapter.pillMediaH
    property alias pillCallW: adapter.pillCallW
    property alias pillCallH: adapter.pillCallH
    property alias pillTimerW: adapter.pillTimerW
    property alias pillTimerH: adapter.pillTimerH
    property alias pillWallpaperW: adapter.pillWallpaperW
    property alias pillWallpaperH: adapter.pillWallpaperH
    property alias pillSettingsW: adapter.pillSettingsW
    property alias pillKeybindsW: adapter.pillKeybindsW
    property alias pillWorkspacesW: adapter.pillWorkspacesW
    property alias pillStashW: adapter.pillStashW
    property alias pillSpaceappsW: adapter.pillSpaceappsW
    property alias pillSysmonW: adapter.pillSysmonW
    property alias pillAppearanceW: adapter.pillAppearanceW
    property alias pillUpdatesW: adapter.pillUpdatesW
    property alias pillDisplayW: adapter.pillDisplayW
    property alias pillInputW: adapter.pillInputW
    property alias pillLookW: adapter.pillLookW
    property alias pillIdlelockW: adapter.pillIdlelockW
    property alias pillAnimationW: adapter.pillAnimationW
    property alias pillRecorderW: adapter.pillRecorderW
    property alias pillFontpickerW: adapter.pillFontpickerW
    property alias pillWeatherW: adapter.pillWeatherW
    property alias pillPolkitW: adapter.pillPolkitW
    property alias pillOpenCorner: adapter.pillOpenCorner
    property alias pillToastW: adapter.pillToastW
    property alias pillQuickChooseW: adapter.pillQuickChooseW
    property alias pillQuickChooseH: adapter.pillQuickChooseH
    property alias pillQuickCountW: adapter.pillQuickCountW
    property alias pillQuickCountH: adapter.pillQuickCountH
    property alias pillDragOverW: adapter.pillDragOverW
    property alias pillDragOverH: adapter.pillDragOverH
    property alias pillGameH: adapter.pillGameH
    property alias memorySaver: adapter.memorySaver
    property alias pillSurfaceIdleTimeout: adapter.pillSurfaceIdleTimeout
    /*
     * The shell's own timings, sizes and motion — constants that used to be
     * minutes-of-thought baked into the components that use them (the corner
     * overlay's radii, the lock surface's box, every duration Motion hands out).
     * Same reason the pill's geometry is flags: what the settings app cannot
     * reach is not a setting, it is a rebuild.
     */
    property alias cornerNotchRadius: adapter.cornerNotchRadius
    property alias cornerNormalRadius: adapter.cornerNormalRadius
    property alias cornerGameRadius: adapter.cornerGameRadius
    property alias cornerMorphMs: adapter.cornerMorphMs
    property alias cornerShadowSize: adapter.cornerShadowSize
    property alias motionSpeed: adapter.motionSpeed
    property alias pillCleanupSec: adapter.pillCleanupSec
    property alias pillHoverGraceMs: adapter.pillHoverGraceMs
    property alias osdHoldMs: adapter.osdHoldMs
    property alias notifMs: adapter.notifMs
    property alias notifLowMs: adapter.notifLowMs
    property alias lockPillW: adapter.lockPillW
    property alias lockPillH: adapter.lockPillH
    property alias lockAvatarSize: adapter.lockAvatarSize
    property alias lockBeadMs: adapter.lockBeadMs
    property alias lockBlurSpread: adapter.lockBlurSpread

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/silhouette/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property bool dnd: false
            property bool keepAwake: false
            property bool time12h: true
            property bool clockSeconds: false
            property bool showGlyphs: false
            property string paletteMode: "static"
            /**
             * Folder the wallpaper strip reads and picks land in. Kept exactly
             * as typed, so a leading ~ is expanded by whoever reads it —
             * Walls.wpDir in the shell, wallpaper.sh in the scripts — because a
             * tilde that arrives in a value is never expanded by the shell and
             * would otherwise be taken as a relative path. Empty means
             * autodetect: ~/Pictures first, then an existing collection in
             * ~/Pictures/rice-wallpapers, ~/Pictures/Wallpapers,
             * ~/Pictures/wallpapers, ~/Wallpapers or ~/wallpapers, else
             * ~/Pictures again (see wallpaper.sh for the chain). Lives in user
             * state so an in-app update never clobbers a custom folder.
             */
            property string wallpaperDir: ""
            property real uiScale: 1.1
            property bool reduceMotion: false
            property int manualHue: 0
            property bool manualDark: true
            property real manualSat: 0.5
            property string uiFont: "JetBrainsMono Nerd Font Mono"
            property real pillOpacity: 1.0
            property bool pillBlur: true
            /** Top margin as a fraction of the shipped 8px. 0 sits the pill flush to the screen edge. */
            property real topGap: 0.7
            /** Pill-to-window band as a fraction of the shipped 12px. 0 tucks the windows flush under the pill. */
            property real appGap: 1.0
            /** True renders the pill as a notch-style bar (ears out, square top corners); false keeps the rounded pill. */
            property bool notchStyle: false
            /** Notch ear flare offset (px). Higher flares both notch ears out. */
            property real notchFlare: 1
            /** Retract the pill off the top edge until the pointer touches it. */
            property bool autoHide: false
            /** hjkl navigation instead of arrow keys in the pill menus. */
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
            /** Lock-screen password bead entrance: "drop", "pulse", or "gpixel". */
            property string lockDotsMode: "gpixel"
            property string weatherCity: "WELLAND"
            property bool musicViz: true
            /** Rest-pill spectrum renderer: bars, centered bars, or the flowing string. */
            property string vizStyle: "bars"
            /** Spectrum capture framerate (the pill EQ is visually identical at 30). */
            property int vizFps: 60
            /** Now-playing card backdrop: "bleed" blurred album art over a wallpaper-derived tint, "wash" the legacy warm tint, or "none" fully transparent. */
            property string mediaStyle: "bleed"
            /** Rest-pill ambient aura: the cover's colour bled around the pill. Off on mediaStyle "none" whatever this says, and off by default so a fresh install gets the bare pill until it is asked for. */
            property bool auraOn: false
            /** Multiplier on the backdrop mode's base aura opacity (bleed 0.32, wash 0.18). */
            property real auraStrength: 1.0
            /** Whether the cover's dominant colour also darkens the pill's shadow. */
            property bool auraShadow: true
            property bool gameMode: false
            property bool gamePrevDnd: false
            property bool gamePrevViz: true
            property bool gamePrevAwake: false
            property string nightLightMode: "scheduled"
            property int nightLightTemp: 3600
            property int nightLightOnMin: 1200
            property int nightLightOffMin: 420
            /*
             * Pill geometry and lifecycle. Each is the shipped size in logical
             * pixels, multiplied by uiScale where the pill draws it, so the app's
             * sliders change the surface itself rather than a global zoom.
             */
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
            property real pillCallW: 380
            property real pillCallH: 150
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
            /**
             * Memory saver: free a closed surface's object tree once its own
             * idle tier has passed (see the tier table in Pill.qml). Off holds
             * every closed surface resident for the rest of the session, so
             * reopening one is instant at the cost of the memory it keeps.
             */
            property bool memorySaver: true
            /**
             * Base tail in seconds for a closed surface. The two heaviest
             * surfaces (wallpaper, mixer) are reclaimed at exactly this; every
             * other surface gets double, so a quick re-toggle stays instant.
             * Floored at 10 s by Pill.qml, and only consulted while memory
             * saver is on.
             */
            property int pillSurfaceIdleTimeout: 12
            /** Screen-corner overlay: the radius each mode rounds the display to. */
            property real cornerNotchRadius: 12
            property real cornerNormalRadius: 8
            property real cornerGameRadius: 0
            /** How long the corners take to collapse in and out of game mode. */
            property int cornerMorphMs: 1500
            /** The inner bezel shadow the corner overlay paints, in px (0 = none). */
            property real cornerShadowSize: 8
            /** Multiplier on every duration the shell's own motion hands out. */
            property real motionSpeed: 1.0
            /** How often the pill sweeps for surfaces to evict, in seconds. */
            property int pillCleanupSec: 10
            /** Grace before the pill collapses after the pointer leaves it. */
            property int pillHoverGraceMs: 300
            /** How long a volume, brightness or track overlay stays up. */
            property int osdHoldMs: 1800
            /** How long a notification popup stays, by urgency. */
            property int notifMs: 6000
            property int notifLowMs: 4000
            /** The lock screen's password pill and avatar, in logical px. */
            property real lockPillW: 176
            property real lockPillH: 42
            property real lockAvatarSize: 120
            /** One password bead's flourish/delete animation. */
            property int lockBeadMs: 350
            /** Blur spread of the lock screen's wallpaper backdrop. */
            property real lockBlurSpread: 2.4
        }
    }
}

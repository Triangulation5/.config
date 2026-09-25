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
    property alias dndCritical: adapter.dndCritical
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
    property alias recordNotify: adapter.recordNotify
    property alias recordClearedBefore: adapter.recordClearedBefore
    property alias idleLockMin: adapter.idleLockMin
    property alias idleScreenOffMin: adapter.idleScreenOffMin
    property alias idleSuspendMin: adapter.idleSuspendMin
    property alias lockPrivacy: adapter.lockPrivacy
    property alias lockDotsMode: adapter.lockDotsMode
    property alias lockFailAction: adapter.lockFailAction
    property alias lockFailLimit: adapter.lockFailLimit
    property alias lockoutThreshold: adapter.lockoutThreshold
    property alias lockoutSeconds: adapter.lockoutSeconds
    property alias lockoutMax: adapter.lockoutMax
    property alias lockMedia: adapter.lockMedia
    property alias lockViz: adapter.lockViz
    property alias lockClock: adapter.lockClock
    property alias lockBattery: adapter.lockBattery
    property alias lockLink: adapter.lockLink
    property alias weatherCity: adapter.weatherCity
    property alias eventChime: adapter.eventChime
    property alias eventNotify: adapter.eventNotify
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
    property alias pillAutoStripH: adapter.pillAutoStripH
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
    property alias pillGameUnloadMs: adapter.pillGameUnloadMs
    property alias pillGameSweepSec: adapter.pillGameSweepSec
    property alias pillHoverGraceMs: adapter.pillHoverGraceMs
    property alias osdHoldMs: adapter.osdHoldMs
    property alias notifMs: adapter.notifMs
    property alias notifLowMs: adapter.notifLowMs
    property alias notifHistoryMax: adapter.notifHistoryMax
    property alias notifPopupMax: adapter.notifPopupMax
    property alias notifDedupe: adapter.notifDedupe
    property alias notifSound: adapter.notifSound
    /* Performance: one switch for the shell's expensive GPU layers. */
    property alias liteMode: adapter.liteMode
    property alias lockPillW: adapter.lockPillW
    property alias lockPillH: adapter.lockPillH
    property alias lockAvatarSize: adapter.lockAvatarSize
    property alias lockBeadMs: adapter.lockBeadMs
    /*
     * The lock backdrop's blur and grade. Spread is the blur's reach; darken,
     * saturation, vignette and grain are what BlurredShot's grade shader lays
     * over the blurred grab — the constants that used to live in
     * modules/lock/BlurredShot.qml and its grade.frag. All five are Lock Screen
     * settings, so the whole backdrop look is tunable from the settings app.
     */
    property alias lockBlurSpread: adapter.lockBlurSpread
    property alias lockBlurDarken: adapter.lockBlurDarken
    property alias lockBlurSaturation: adapter.lockBlurSaturation
    property alias lockBlurVignette: adapter.lockBlurVignette
    property alias lockBlurGrain: adapter.lockBlurGrain
    /*
     * Thresholds and cadences that used to be literals in the components that
     * use them: the two battery warnings, the wifi/bluetooth rescan gaps, the
     * calendar strip's idle return, the weather refresh pair and the recording
     * list's cap. Same reason the lock's own numbers are flags — what the
     * settings app cannot reach is not a setting.
     */
    property alias battLowPct: adapter.battLowPct
    property alias periphLowNotify: adapter.periphLowNotify
    property alias maxVolume: adapter.maxVolume
    property alias wifiScanMs: adapter.wifiScanMs
    property alias btScanMs: adapter.btScanMs
    property alias calendarIdleReturnMs: adapter.calendarIdleReturnMs
    property alias weatherRetryMs: adapter.weatherRetryMs
    property alias weatherRefreshMs: adapter.weatherRefreshMs
    property alias recHistoryMax: adapter.recHistoryMax
    /**
     * Whether opening the system monitor runs its network speed test on its
     * own, or waits for the card's Test button. Off by default.
     */
    property alias sysmonAutoTest: adapter.sysmonAutoTest

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
            /** Whether a critical-urgency notification still pops while Do-Not-Disturb is on. */
            property bool dndCritical: true
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
            /** Announce a finished recording with a notification (modules/recording). */
            property bool recordNotify: true
            property real recordClearedBefore: 0
            property int idleLockMin: 3
            property int idleScreenOffMin: 0
            property int idleSuspendMin: 0
            /**
             * Redact the lock screen until the session is authenticated: the
             * now-playing text and art, the wifi network name and the account's
             * real name each give way to a neutral placeholder. Off by default —
             * a lock screen a passer-by can read is not doing its job, but the
             * default here is behaviour, not advice: existing sessions keep the
             * lock they already had until they opt in from Settings › Lock Screen.
             */
            property bool lockPrivacy: false
            /** Lock-screen password bead entrance: "drop", "pulse", or "gpixel". */
            property string lockDotsMode: "gpixel"
            /**
             * What the lock does once the wrong-password streak reaches
             * `lockFailLimit`: "none" leaves only the time lockout, while "logout",
             * "reboot" and "shutdown" end the session through the same calls the
             * power surface makes. Defaults to "logout" — a keyboard left in
             * front of a locked screen ends the session rather than being left to
             * keep guessing. Read by modules/lock/Auth.qml.
             */
            property string lockFailAction: "logout"
            /**
             * Consecutive wrong passwords before `lockFailAction` runs. Counted
             * from the last successful unlock (that is what clears the streak),
             * and cleared again once the action fires, so a session that comes
             * back does not trip on its first mistake.
             */
            property int lockFailLimit: 10
            /**
             * AOSP-style retry lockout, read by modules/lock/Auth.qml: after
             * `lockoutThreshold` consecutive failures the field locks for
             * `lockoutSeconds`, doubling per repeat and capped at `lockoutMax`.
             * Distinct from the escalation above — the wait applies even with
             * `lockFailAction` set to "none".
             */
            property int lockoutThreshold: 5
            property int lockoutSeconds: 30
            property int lockoutMax: 600
            /**
             * Show the now-playing card on the lock screen while a player is
             * active. Read by modules/lock/LockPlayer.qml; `lockPrivacy` above
             * still decides whether its track details are legible.
             */
            property bool lockMedia: true
            /**
             * The lock screen's audio-reactive glow — its own cava capture, not
             * the pill's (services/Cava.qml). Independent of `musicViz`: a
             * locked screen can glow with the pill's visualizer switched off.
             */
            property bool lockViz: true
            /** Big time and date on the lock. Read by modules/lock/Content.qml. */
            property bool lockClock: true
            /** The lock's battery glance (modules/lock/BatterySurface.qml). */
            property bool lockBattery: true
            /** The lock's wifi/bluetooth glance (modules/lock/LinkSurface.qml). */
            property bool lockLink: true
            property string weatherCity: "WELLAND"
            /**
             * Calendar reminder effects, read by services/Events.qml: a timed
             * event's start plays an alarm chime and posts a desktop
             * notification. Each can be switched off on its own; the event is
             * still marked fired either way, so it never repeats.
             */
            property bool eventChime: true
            property bool eventNotify: true
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
            /** Height of the wake strip auto-hide leaves at the top edge, in logical px. */
            property real pillAutoStripH: 5
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
            /**
             * Game mode's override of the memory saver above. While the mode is
             * on, Pill.qml reclaims a closed surface `pillGameUnloadMs` after it
             * closes instead of after its tier tail, and runs the eviction sweep
             * at most every `pillGameSweepSec` seconds — the desktop hands its
             * memory back to the game as fast as the close animations allow, even
             * with the saver itself off. Flags rather than constants so the
             * Timers page's read-only note reports the same numbers the shell
             * applies rather than a copy that could drift from them.
             */
            property int pillGameUnloadMs: 1000
            property int pillGameSweepSec: 2
            /** Grace before the pill collapses after the pointer leaves it. */
            property int pillHoverGraceMs: 300
            /** How long a volume, brightness or track overlay stays up. */
            property int osdHoldMs: 1800
            /** How long a notification popup stays, by urgency. */
            property int notifMs: 6000
            property int notifLowMs: 4000
            /** Cap on the notification inbox's history list. */
            property int notifHistoryMax: 50
            /** Most notification popups stacked at once. */
            property int notifPopupMax: 3
            /**
             * Collapse a repeat of a notification that is already on screen
             * instead of stacking a second identical popup. The repeat is still
             * tracked, so the tray's group count still climbs.
             */
            property bool notifDedupe: true
            /** Play a blip for each notification shown. Off by default. */
            property bool notifSound: false
            /**
             * Skip the shell's expensive GPU layers — the now-playing bleed
             * blur, the ambient aura blur, the Ame bead's blur, the pill's
             * closing blur, the tooltip/tray shadows and the lock backdrop's
             * blur and grain. Everything still works; it draws flat. Intended
             * for integrated GPUs, where those layers are the frame budget.
             */
            property bool liteMode: false
            /**
             * Low-battery warning threshold, shared by both warnings so the
             * laptop's and a peripheral's cannot drift: services/Battery.qml
             * flags a discharging battery at or below this, and
             * services/Peripherals.qml raises one notify-send per device when
             * it falls to it.
             */
            property int battLowPct: 20
            /** Notify once when a peripheral falls to `battLowPct` and is not charging. */
            property bool periphLowNotify: true
            /**
             * Ceiling the mixer's volume slider reaches, in percent. Above 100
             * lets the sink run past unity, which PipeWire allows; the shell's
             * own OSD and the mixer's readout follow it.
             */
            property int maxVolume: 100
            /**
             * Rescan gaps for the control center's link panels, in ms —
             * modules/controlcenter/LinkWifi.qml and LinkBt.qml.
             */
            property int wifiScanMs: 10000
            property int btScanMs: 25000
            /** How long the calendar strip hovers a day before gliding back to today. */
            property int calendarIdleReturnMs: 2000
            /**
             * Weather cadence, in ms: while the machine has never been located
             * it retries every `weatherRetryMs` so a transient geolocation
             * failure heals quickly, else it refreshes the forecast every
             * `weatherRefreshMs`.
             */
            property int weatherRetryMs: 30000
            property int weatherRefreshMs: 1200000
            /** How many recent recordings the recorder's list looks up. */
            property int recHistoryMax: 40
            /**
             * Run the system monitor's Cloudflare speed test the moment the
             * surface opens. Off by default: a run moves tens of megabytes, so
             * the card waits for its Test button unless this is turned on.
             */
            property bool sysmonAutoTest: false
            /** The lock screen's password pill and avatar, in logical px. */
            property real lockPillW: 176
            property real lockPillH: 42
            property real lockAvatarSize: 120
            /** One password bead's flourish/delete animation. */
            property int lockBeadMs: 350
            /** Blur spread of the lock screen's wallpaper backdrop. */
            property real lockBlurSpread: 2.4
            /** How much the blurred backdrop is darkened (1 = untouched). */
            property real lockBlurDarken: 0.62
            /** Colour saturation of the backdrop (1 = untouched, 0 = greyscale). */
            property real lockBlurSaturation: 1.0
            /** How much darkness gathers at the backdrop's edges (0 = flat). */
            property real lockBlurVignette: 0.14
            /** Film grain mixed into the backdrop, as a 0-1 amplitude (0 = clean). */
            property real lockBlurGrain: 0.012
        }
    }
}

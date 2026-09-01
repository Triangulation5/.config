pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.components.icons
import qs.modules.pill.widgets
import qs.modules.pill.widgets.osd
import qs.modules.recording
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.modules.pill.visualizers
import qs.components.layout
import qs.modules.controlcenter
import qs.modules.launcher

/**
 * The pill body. One element carries every state. Width/height driven by `state`
 * (rest, hover/pinned, mixer, calendar) with a no-overshoot easing so surfaces
 * grow out of the pill in place. Surfaces are stacked absolutely and cross-fade.
 *
 * Hover comes from a passive HoverHandler, pin from a passive TapHandler, so
 * neither swallows pointer events from the surfaces stacked above: workspace
 * dots, the clock target, tray icons and the mixer faders get their own clicks
 * and drags.
 */
Item {
    id: pill

    property real s: 1.1
    property string screenName: ""
    property var barWindow
    property string surface: ""

    /**
     * Date a hover-strip click asked the calendar to open focused on, or null
     * to open on the real today. Cleared whenever the calendar surface closes,
     * so a later open from the clock, a keybind or IPC lands on today unless a
     * fresh date click set it again.
     */
    property var calendarFocusDate: null
    onCalendarOpenChanged: if (!calendarOpen) calendarFocusDate = null

    property bool hovered: false
    property bool pinned: false
    property bool forcePinned: false

    /**
     * True while the overlay is hiding the pill over fullscreen content
     * (`pillHidden`). While hidden the rest face must not fade in: the pill
     * collapses toward rest geometry as it fades out, and without this gate
     * the clock text fades in at the tail of the close and ghosts over the
     * fullscreen content.
     */
    property bool hidden: false

    /** True renders the pill as a notch-style bar (ears out, square top corners); false keeps the rounded pill. */
    property bool notchStyle: Flags.notchStyle

    /**
     * Notch <-> pill style transition progress: 1 renders the notch look (ears
     * out, square top corners), 0 the pill look. Toggling the style animates
     * this on the same quick, decisive glide the screen corners use (a touch
     * faster) so the ears deflate downward and the top corners re-round in one
     * crisp motion - mirrored when returning to notch.
     */
    property real notchProgress: notchStyle ? 1 : 0

    Behavior on notchProgress {
        NumberAnimation {
            duration: 380
            easing.type: Motion.easeStandard
        }
    }

    readonly property bool held: pinned || forcePinned
    readonly property bool mixerOpen: surface === "mixer"
    readonly property bool calendarOpen: surface === "calendar"
    readonly property bool launcherOpen: surface === "launcher"
    readonly property bool clipboardOpen: surface === "clipboard"
    readonly property bool wallpaperOpen: surface === "wallpaper"
    readonly property bool powerOpen: surface === "power"
    readonly property bool mediaOpen: surface === "media"
    readonly property bool linkOpen: surface === "link"
    readonly property bool settingsOpen: surface === "settings"
    readonly property bool keybindsOpen: surface === "keybinds"
    readonly property bool workspacesOpen: surface === "workspaces"
    readonly property bool stashOpen: surface === "stash"
    readonly property bool spaceappsOpen: surface === "spaceapps"
    readonly property bool recorderOpen: surface === "recorder"
    readonly property bool appearanceOpen: surface === "appearance"
    readonly property bool updatesOpen: surface === "updates"
    readonly property bool displayOpen: surface === "display"
    readonly property bool inputOpen: surface === "input"
    readonly property bool lookOpen: surface === "look"
    readonly property bool idlelockOpen: surface === "idlelock"
    readonly property bool animationOpen: surface === "animation"
    readonly property bool fontpickerOpen: surface === "fontpicker"
    readonly property bool timerOpen: surface === "timer"
    readonly property bool settingsLike: settingsOpen || appearanceOpen || updatesOpen
        || lookOpen || inputOpen || displayOpen || animationOpen || idlelockOpen || fontpickerOpen
    /**
     * True while any valid media source exists: a playing or paused player
     * with a track loaded (Players.has). Gates the hover media bud, so a
     * paused track still shows its card — you can glance at what's loaded —
     * while a stopped, closed, or vanished player (Players.has false) drops
     * the widget instead of leaving a stale card on screen.
     */
    readonly property bool hasMedia: Players.has

    /**
     * The media source dropped out while the media surface owned the pill: a
     * pause keeps the surface up (Players.has stays true — the paused card is
     * still the live now-playing view, and the OSD drops track flashes over
     * it, see Osd.mediaOpen), so the pill never yanks away to a toast. Only
     * when the source itself is gone — stopped, closed, killed (Players.has
     * false) — does the surface drop, so the pill morphs back to its normal
     * state instead of parking on a stale card. Driven purely by state changes
     * - no timers or timeouts.
     */
    onHasMediaChanged: if (!hasMedia && mediaOpen) pill.requestClose()

    /**
     * Subview the link surface should land on when next opened. The wifi glance
     * sets "wifi" to drill straight to the network list; the inbox glance and
     * toast set "main". Reset once the surface closes so IPC opens land on main.
     */
    property string linkInitialView: "main"

    readonly property var netDevices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: netDevices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var wifiNets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var wifiActive: wifiNets.find(function(n) { return n && n.connected }) || null
    readonly property real wifiLevel: (wifiActive && wifiActive.signalStrength) || 0
    readonly property bool surfaceOpen: surface.length > 0
    property bool hoverLatch: false
    readonly property bool expanded: surfaceOpen || held || hoverLatch

    /**
     * True while the open surface is waiting on an external auth dialog (the
     * updater's pkexec password prompt). The shell drops its modal grab for this
     * so the polkit window underneath is clickable and typeable, instead of the
     * backdrop swallowing the reach for it and dismissing the whole pill.
     */
    readonly property bool authPending: updatesOpen && Updates.applying

    /**
     * The special workspace shown on this pill's monitor, surfaced as a plain word
     * in place of the clock so it is obvious you are looking at the minimized stash
     * or the private space rather than your real desktop. Empty in the normal case.
     */
    readonly property string specialView: {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++) {
            if (ms[i] && ms[i].name === pill.screenName) {
                var o = ms[i].lastIpcObject;
                var sw = (o && o.specialWorkspace) ? o.specialWorkspace.name : "";
                if (sw === "special:minimized") return "Minimized";
                if (sw === "special:private") return "Private";
                if (sw === "special:stash") return "Stash";
                if (sw && sw.indexOf("special:") === 0) {
                    var id = sw.slice("special:".length);
                    var sl = Spaces.list;
                    for (var j = 0; j < sl.length; j++)
                        if (sl[j] && sl[j].id === id)
                            return sl[j].name;
                    return id.charAt(0).toUpperCase() + id.slice(1);
                }
                return "";
            }
        }
        return "";
    }
    readonly property bool toastActive: Notifs.popups.length > 0
    readonly property bool osdActive: osd.flashing
    /**
     * Whether the flashing OSD may hold the pill over fullscreen content
     * (everything but the workspace switcher); the overlay reads this when
     * deciding whether to summon over fullscreen.
     */
    readonly property bool osdHoldsOverFullscreen: osd.holdsOverFullscreen

    /** The overlay cuts a workspace flash short when the monitor goes fullscreen. */
    function dismissWorkspaceOsd() {
        osd.dismissWorkspace();
    }

    /**
     * Quick-record overlays belong only to the focused monitor the keybind
     * targeted, so a single chooser and a single countdown toast appear. The
     * standalone chooser is suppressed while the morphing recorder surface owns the
     * pill; the countdown toast yields to the surface too (the surface shows its
     * own in-bar countdown there).
     */
    readonly property bool quickHere: ScreenRec.quickMon === screenName
    readonly property bool quickChoosing: quickHere && ScreenRec.quickChoosing && !surfaceOpen
    readonly property bool quickCounting: quickHere && ScreenRec.counting && !recorderOpen

    readonly property real restW: 160 * s
    readonly property real restH: 38 * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverW: hoverFace.hoverRow.implicitWidth + 3 * hoverPad
    readonly property real hoverH: 172 * s
    readonly property real mixerH: 214 * s
    readonly property real launcherW: 360 * s
    readonly property real launcherH: 332 * s
    readonly property real clipboardW: 360 * s
    readonly property real clipboardH: 332 * s
    readonly property real wallpaperW: 720 * s
    readonly property real wallpaperH: 172 * s
    readonly property real powerW: 330 * s
    readonly property real powerH: 150 * s
    readonly property real mediaW: (Players.pickable.length > 1 ? 460 : 390) * s
    readonly property real mediaH: 150 * s
    readonly property real batteryW: 316 * s
    readonly property real settingsW: 392 * s
    readonly property real keybindsW: 460 * s
    readonly property real workspacesW: 392 * s
    readonly property real stashW: 392 * s
    readonly property real spaceappsW: 392 * s
    readonly property real recorderW: 384 * s
    readonly property real sysmonW: 392 * s
    readonly property real appearanceW: 392 * s
    readonly property real updatesW: 360 * s
    readonly property real displayW: 392 * s
    readonly property real inputW: 392 * s
    readonly property real lookW: 392 * s
    readonly property real idlelockW: 392 * s
    readonly property real animationW: 392 * s
    readonly property real fontpickerW: 360 * s
    readonly property real timerW: 340 * s
    readonly property real polkitW: 440 * s
    readonly property real timerH: 460 * s
    readonly property real toastW: 342 * s
    readonly property real quickChooseW: 344 * s
    readonly property real quickChooseH: 76 * s
    readonly property real quickCountW: 150 * s
    readonly property real quickCountH: 64 * s
    readonly property real dragOverW: 300 * s
    readonly property real dragOverH: 126 * s
    readonly property real gameH: 34 * s
    readonly property real gameW: barWindow ? barWindow.width : 1920
    readonly property real restCorner: (Flags.notchStyle ? 18 : 28) * s
    readonly property real openCorner: 22 * s

    /**
     * Latch-once lazy load with idle-timeout cleanup. Every surface sleeps in
     * an inactive Loader until first opened; the size and ame thunks below
     * resolve items through here. After a surface has been idle (not opened)
     * for `surfaceIdleTimeout` seconds its Loader is deactivated so the
     * component tree is destroyed, freeing RAM and GPU resources until the
     * next open reactivates it.
     *
     * Heavy surfaces opt into asynchronous creation (`asynchronous: true` on
     * their loader), so their first open builds in frame gaps and this returns
     * null until the build lands. Every read of `ld.item` inside a size/ame
     * thunk re-registers the dependency, so the pill re-morphs to the real
     * measurement the moment the item arrives. The measure helpers below keep
     * thunks null-safe; never deref `ld.item` directly in a thunk.
     */
    function surfaceItem(ld, name) {
        ld.active = true;
        if (name && name.length)
            _surfaceLastOpened[name] = Date.now();
        return ld.item;
    }

    /** Measured surface width + pad, or the fallback while an async load is in flight. */
    function surfaceWidth(ld, name, pad, fallback) {
        const it = surfaceItem(ld, name);
        return it && it.implicitWidth > 0 ? it.implicitWidth + pad : fallback;
    }

    /** Measured surface height + pad, or the fallback while an async load is in flight. */
    function surfaceHeight(ld, name, pad, fallback) {
        const it = surfaceItem(ld, name);
        return it && it.implicitHeight > 0 ? it.implicitHeight + pad : fallback;
    }

    /** Any surface prop with a fallback while an async load is in flight. */
    function surfaceProp(ld, name, prop, fallback) {
        const it = surfaceItem(ld, name);
        const v = it ? it[prop] : undefined;
        return v !== undefined && v > 0 ? v : fallback;
    }

    /** Seconds a surface stays loaded after last use before being reclaimed. */
    property int surfaceIdleTimeout: 12

    /** Timestamp of last open per surface name. */
    property var _surfaceLastOpened: ({})

    /** Surface name → loader map, self-registered by each PillSurfaceLoader. */
    property var _surfaceLoaders: ({})
    /** True while the idle-cleanup timer has run at least once. */
    property bool _surfaceCleanupReady: false

    /**
     * Latch that gates the wallpaper hold-to-delete so a held Enter fires the
     * strip's HeatHold once per press-hold, not once per autorepeat event.
     * Reset when the surface closes (below) and re-armed on key release in
     * PillRoot, so every new hold re-fires the delete hold.
     */
    property bool _wpHoldStarted: false
    onWallpaperOpenChanged: if (!wallpaperOpen) _wpHoldStarted = false

    function _cleanupIdleSurfaces() {
        var now = Date.now();
        var timeout = pill.surfaceIdleTimeout * 1000;
        var ld;
        for (var name in pill._surfaceLoaders) {
            ld = pill._surfaceLoaders[name];
            if (!ld || !ld.active)
                continue;
            /** Never evict the surface currently open on the pill. */
            if (name === pill.surface)
                continue;
            /** Never evict a running timer — it must persist in the background. */
            if (name === "timer" && ld.item && ld.item.timerState === "running")
                continue;
            var last = pill._surfaceLastOpened[name] || 0;
            if (now - last >= timeout)
                ld.active = false;
        }
        /**
         * The hover media bud stays loaded while a media source exists (playing
         * or paused), even with the pill at rest and the bud off-screen. Reclaim
         * it once it has been out of hover mode for the idle timeout so an idle
         * iGPU isn't paying for a full Media widget (player lookups, cover art)
         * that nobody can see.
         * The media timestamp is only stamped by the full media surface, never
         * by the bud itself, so a bud that is only ever seen on hover is simply
         * reclaimed sooner — harmless, since it rebuilds on the next media
         * toggle. The visible bud is never touched: this only fires when the
         * pill is out of hover mode.
         */
        if (pill.hoverFace && pill.hoverFace.mediaBud.active && pill.mode !== "hover" && now - (pill._surfaceLastOpened["media"] || 0) >= timeout)
            pill.hoverFace.mediaBud.active = false;
    }

    Timer {
        id: idleCleanupTimer
        interval: 10000
        repeat: true
        running: pill._surfaceCleanupReady
        onTriggered: pill._cleanupIdleSurfaces()
    }

    /**
     * Single source of truth for every morphing surface, keyed by its `surface`
     * string. Each entry owns the surface's target size (a thunk so the geometry
     * it reads registers as a live dep of targetSize) and a thunk resolving the
     * surface item Ame anchors to while it is open (null = Ame falls back to the
     * pill's own hover or wake anchor). `mode`, `targetSize` and `ameSurface` all
     * derive from this, so adding a surface is one entry here plus its Loader —
     * no parallel ternary chains to keep in lockstep.
     *
     * Size thunks go through the surfaceWidth/surfaceHeight/surfaceProp measure
     * helpers, which fall back to a default size while an async loader's item
     * is still building (null) and re-evaluate the moment it lands, so the
     * morph starts immediately and settles on the real measurement.
     */

    /**
     * Descriptor for the common surface shape: fixed width, measured height
     * with a fallback while an async loader is still building, and Ame anchored
     * to the loaded item. Pass `ameTarget: null` for a surface with no anchor
     * (timer). Surfaces that measure their width or size themselves differently
     * (calendar, launcher, mixer…) keep their own entries in the map below.
     */
    function stdSurface(ld, name, w, hPad, fallbackH, ameTarget) {
        const anchor = ameTarget === undefined ? name : ameTarget;
        return {
            size: () => Qt.size(w, surfaceHeight(ld, name, hPad, fallbackH)),
            ame: () => anchor === null ? null : surfaceItem(ld, anchor)
        };
    }

    readonly property var surfaces: ({
        calendar:  { size: () => Qt.size(surfaceWidth(ldCalendar, "calendar", 36 * s, 318 * s), surfaceHeight(ldCalendar, "calendar", 32 * s, 272 * s)), ame: () => surfaceItem(ldCalendar, "calendar") },
        launcher:  { size: () => { surfaceItem(ldLauncher, "launcher"); return Qt.size(launcherW, launcherH); }, ame: () => surfaceItem(ldLauncher, "launcher") },
        clipboard: { size: () => { surfaceItem(ldClip, "clipboard"); return Qt.size(clipboardW, clipboardH); }, ame: () => surfaceItem(ldClip, "clipboard") },
        wallpaper: { size: () => { surfaceItem(ldWall, "wallpaper"); return Qt.size(wallpaperW, wallpaperH); }, ame: () => null },
        power:     { size: () => { surfaceItem(ldPower, "power"); return Qt.size(powerW, powerH); }, ame: () => surfaceItem(ldPower, "power") },
        media:     { size: () => { surfaceItem(ldMedia, "media"); return Qt.size(mediaW, mediaH); }, ame: () => surfaceItem(ldMedia, "media") },
        mixer:     { size: () => Qt.size(93 * Math.max(4, surfaceProp(ldMixer, "mixer", "faderCount", 4)) * s, mixerH), ame: () => surfaceItem(ldMixer, "mixer") },
        link:      { size: () => Qt.size(surfaceProp(ldLink, "link", "desiredW", 330 * s), surfaceHeight(ldLink, "link", 26 * s, 300 * s)), ame: () => surfaceItem(ldLink, "link") },
        battery:   stdSurface(ldBattery, "battery", batteryW, 26 * s, 160 * s),
        settings:  stdSurface(ldSettings, "settings", settingsW, 29 * s, 400 * s),
        keybinds:  stdSurface(ldKeybinds, "keybinds", keybindsW, 29 * s, 420 * s),
        workspaces: stdSurface(ldWorkspaces, "workspaces", workspacesW, 29 * s, 300 * s),
        stash:     stdSurface(ldStash, "stash", stashW, 29 * s, 300 * s),
        spaceapps: stdSurface(ldSpaceapps, "spaceapps", spaceappsW, 29 * s, 300 * s),
        recorder:  stdSurface(ldRecorder, "recorder", recorderW, 33 * s, 300 * s),
        sysmon:    stdSurface(ldSysmon, "sysmon", sysmonW, 33 * s, 420 * s),
        appearance: stdSurface(ldAppearance, "appearance", appearanceW, 29 * s, 400 * s),
        updates:    stdSurface(ldUpdates, "updates", updatesW, 29 * s, 360 * s),
        display:    stdSurface(ldDisplay, "display", displayW, 29 * s, 400 * s),
        input:      stdSurface(ldInput, "input", inputW, 29 * s, 400 * s),
        look:       stdSurface(ldLook, "look", lookW, 29 * s, 400 * s),
        idlelock:   stdSurface(ldIdlelock, "idlelock", idlelockW, 29 * s, 400 * s),
        animation:  stdSurface(ldAnimation, "animation", animationW, 29 * s, 400 * s),
        fontpicker: stdSurface(ldFontpicker, "fontpicker", fontpickerW, 29 * s, 400 * s),
        timer:    stdSurface(ldTimer, "timer", timerW, 28 * s, 460 * s, null),
        polkit:    stdSurface(ldPolkit, "polkit", polkitW, 28 * s, 200 * s)
    })

    /**
     * True while the flashing OSD owns the pill: it is not held (pin/peek),
     * game mode is off (volume/brightness ride the bar's own inline chips
     * there), and — for a flash that began at rest — no surface has opened
     * over it. A flash that began while a surface was open still preempts
     * that surface and returns when it finishes; a surface that opens over a
     * flash which began at rest takes the pill straight over instead of
     * parking on the OSD and swallowing the open.
     */
    readonly property bool osdPreempts: osdActive && !held && !Flags.gameMode && !(surfaceOpen && !osd.startedOnSurface)

    /**
     * Drag-to-install state, live only while a file hovers the resting pill.
     * `dragStage` walks hover -> installing -> done, or bad for a
     * non-installable drop.
     */
    property bool dragActive: false
    property string dragName: ""
    property string dragStage: ""

    /** Mode ladder: drag-over, OSD, open surface, game, quick-record, toast, hover, rest. */
    readonly property string mode: (dragActive ? "dragOver"
        : (osdPreempts ? "osd"
        : (surfaceOpen && surfaces[surface] !== undefined ? surface
        : (Flags.gameMode ? "game"
        : (quickChoosing ? "quickChoose"
        : (quickCounting ? "quickCount"
        : (toastActive && !held ? "toast"
        : (expanded ? "hover" : "rest"))))))))

    signal requestSurface(string name)
    signal requestClose()

    readonly property bool keybindsListening: pill.keybindsOpen && ldKeybinds.item !== null && ldKeybinds.item.listening
    readonly property bool wallpaperSearching: pill.wallpaperOpen && ldWall.item !== null && ldWall.item.searching
    /**
     * The recorder's inline source chooser (or its monitor sub-chooser) is
     * covering the action bar. Return/Backspace must drive the chooser, not the
     * bar or the audio faders.
     */
    readonly property bool recorderChooserOpen: pill.recorderOpen && ldRecorder.item !== null && ldRecorder.item.chooserOpen
    /**
     * Hover-face keyboard focus: left/right walks the interactive targets of
     * the expanded pill (media bud, minimized tray, tray icons, clock); Enter
     * activates the focused target. The tray and the minimized row keep their
     * own per-icon focus while the ring sits on them.
     */
    property int faceFocus: -1

    /**
     * Child-widget aliases for the nav module (Nav.qml), which drives the
     * quick-record chooser and the hover face's per-icon rows through the host.
     * The hover-face widgets live in HoverFace.qml, so the aliases reach
     * through the face instance.
     */
    property alias quickChooserItem: quickChooser
    property alias minimizedRow: hoverFace.minimizedRow
    property alias trayRow: hoverFace.trayRow

    /** Keyboard routing + hover-face navigation, extracted to its own file. */
    Nav {
        id: navHost
        host: pill
    }

    /**
     * Thin forwards to the nav module. PillRoot and the shell call these on
     * the pill; all real routing lives in Nav.qml.
     */
    function openCalendarAt(date) { return navHost.openCalendarAt(date); }
    function mixerStep(deltaPct) { return navHost.mixerStep(deltaPct); }
    function mixerFocusMove(dir) { return navHost.mixerFocusMove(dir); }
    function recorderStep(deltaPct) { return navHost.recorderStep(deltaPct); }
    function rowNavSurface() { return navHost.rowNavSurface(); }
    function settingsMove(dir) { return navHost.settingsMove(dir); }
    function settingsAdjust(dir) { return navHost.settingsAdjust(dir); }
    function settingsActivate() { return navHost.settingsActivate(); }
    function keybindsMove(dir) { return navHost.keybindsMove(dir); }
    function keybindsActivate() { return navHost.keybindsActivate(); }
    function quickChooseSource(kind) { return navHost.quickChooseSource(kind); }
    function quickPickMonitor(name) { return navHost.quickPickMonitor(name); }
    function linkBack() { return navHost.linkBack(); }
    function surfaceBack() { return navHost.surfaceBack(); }
    function keybindsBack() { return navHost.keybindsBack(); }
    function wallpaperMove(dir) { return navHost.wallpaperMove(dir); }
    function wallpaperActivate() { return navHost.wallpaperActivate(); }
    function wallpaperHoldPress() { return navHost.wallpaperHoldPress(); }
    function wallpaperType(ch) { return navHost.wallpaperType(ch); }
    function powerMove(dir) { return navHost.powerMove(dir); }
    function powerPress() { return navHost.powerPress(); }
    function powerRelease() { return navHost.powerRelease(); }
    function clipboardMove(delta) { return navHost.clipboardMove(delta); }
    function clipboardActivate() { return navHost.clipboardActivate(); }
    function fontpickerMove(dir) { return navHost.fontpickerMove(dir); }
    function fontpickerActivate() { return navHost.fontpickerActivate(); }
    function timerBack() { return navHost.timerBack(); }
    function timerActivate() { return navHost.timerActivate(); }
    function timerReset() { return navHost.timerReset(); }
    function launcherMove(delta) { return navHost.launcherMove(delta); }
    function launcherActivate() { return navHost.launcherActivate(); }
    function recorderPress() { return navHost.recorderPress(); }
    function workspacesMove(dir) { return navHost.workspacesMove(dir); }
    function workspacesActivate() { return navHost.workspacesActivate(); }
    function stashMove(dir) { return navHost.stashMove(dir); }
    function stashActivate() { return navHost.stashActivate(); }
    function spaceappsMove(dir) { return navHost.spaceappsMove(dir); }
    function spaceappsActivate() { return navHost.spaceappsActivate(); }
    function calendarMove(axis, dir) { return navHost.calendarMove(axis, dir); }
    function calendarActivate() { return navHost.calendarActivate(); }
    function linkMove(dir) { return navHost.linkMove(dir); }
    function linkActivate() { return navHost.linkActivate(); }
    function linkAdjust(dir) { return navHost.linkAdjust(dir); }
    function recorderChooserMove(dir) { return navHost.recorderChooserMove(dir); }
    function recorderChooserActivate() { return navHost.recorderChooserActivate(); }
    function recorderChooserBack() { return navHost.recorderChooserBack(); }
    function quickChooseMove(dir) { return navHost.quickChooseMove(dir); }
    function quickChooseActivate() { return navHost.quickChooseActivate(); }
    function quickChooseBack() { return navHost.quickChooseBack(); }
    function faceMove(dir) { return navHost.faceMove(dir); }
    function faceActivate() { return navHost.faceActivate(); }
    function faceBack() { return navHost.faceBack(); }
    function focusSearch() { return navHost.focusSearch(); }
    function navUp() { return navHost.navUp(); }
    function navDown() { return navHost.navDown(); }
    function navLeft() { return navHost.navLeft(); }
    function navRight() { return navHost.navRight(); }
    function vimBack() { return navHost.vimBack(); }
    function vimEnter() { return navHost.vimEnter(); }

    /**
     * The item of the surface that most recently closed, kept while it is
     * still dissolving so the hover face can hold its entrance until the
     * dissolve clears (see `closingOpacity`). Advances whenever the `surface`
     * string changes: a close latches the closing item, an open (or any other
     * change) releases it.
     */
    property var closingSurface: null

    /** The previous `surface` value, used to pick the closing loader. */
    property string prevSurface: ""

    onSurfaceChanged: {
        if (pill.surface.length === 0 && pill.prevSurface.length > 0) {
            const ld = pill._surfaceLoaders[pill.prevSurface];
            pill.closingSurface = ld ? ld.item : null;
        } else {
            pill.closingSurface = null;
        }
        pill.prevSurface = pill.surface;
    }

    /**
     * Current opacity of the dissolving surface, 1 while it is fully visible
     * and animating down to 0 with its close fade. 0 with no surface closing.
     * The hover face reads this so its entrance on a close is an exact
     * crossfade against the dissolving surface instead of popping over it —
     * for surfaces whose close barely moves the pill (the media card) the old
     * morphCloseness gate alone was already satisfied the instant the close
     * began, so the hover clock and media bud flashed over the still-visible
     * card.
     */
    readonly property real closingOpacity: (pill.closingSurface && typeof pill.closingSurface.opacity === "number")
        ? pill.closingSurface.opacity : 0

    onSurfaceOpenChanged: if (surfaceOpen) {
        pinned = false;
        if (quickHere && ScreenRec.quickChoosing) {
            ScreenRec.quickChoosing = false;
            ScreenRec.quickScreenChoosing = false;
        }
        /**
         * A flash that was already running when the surface opened is over:
         * the surface owns the pill now, and the flash must not linger to
         * pop back in over the surface when it closes. A flash that began
         * over the open surface keeps its deliberate preempt and is
         * untouched.
         */
        if (!osd.startedOnSurface)
            osd.dismissAll();
    }

    QtObject {
        id: clock
        readonly property var loc: Qt.locale("en_US")
        property var now: new Date()

        readonly property string timeFormat: (Flags.time12h ? "h:mm AP" : "HH:mm") + (Flags.clockSeconds ? ":ss" : "")
        readonly property string hhmm: Flags.time12h
            ? Qt.formatTime(now, timeFormat).replace(" AM", "").replace(" PM", "")
            : Qt.formatTime(now, timeFormat)
        readonly property string date: loc.toString(now, "ddd d MMM")
    }

    /**
     * Drives the pill's clock from a plain repeating Timer instead of a
     * Quickshell SystemClock. A SystemClock schedules one delayed tick per
     * interval, and that single one-shot can be dropped while the session is
     * locked (the compositor stops frame-driven updates), leaving the pill's
     * time frozen after unlock. A repeating Timer re-reads the wall clock on
     * every fire, so the time self-heals the instant the event loop runs again.
     */
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: clock.now = new Date()
    }

    property real morphRadius: (mode === "rest" || mode === "hover" || mode === "game") ? restCorner : openCorner

    /**
     * Target geometry for the non-surface morph modes. Surface sizes come from
     * the `surfaces` descriptor; these three are the pill's own modes that have no
     * surface item. Thunks so the properties they read register as live deps of
     * targetSize.
     */
    readonly property var modeSize: ({
        osd:   () => Qt.size(osd.desiredW, osd.desiredH),
        toast: () => Qt.size(toastW, toastLoader.item ? toastLoader.item.implicitHeight + 24 * s : restH),
        hover: () => Qt.size(hoverW, hoverH),
        quickChoose: () => Qt.size(quickChooseW, quickChooseH),
        quickCount:  () => Qt.size(quickCountW, quickCountH),
        dragOver:    () => Qt.size(dragOverW, dragOverH),
        game:        () => Qt.size(gameW, gameH)
    })

    readonly property size targetSize: {
        const sf = surfaces[mode];
        if (sf)
            return sf.size();
        const f = modeSize[mode];
        return f ? f() : Qt.size(Math.max(restW, restRow.implicitWidth + 36 * s), restH);
    }
    readonly property real targetW: targetSize.width
    readonly property real targetH: targetSize.height

    width: targetW
    height: targetH

    /**
     * How settled the pill is into its target geometry: 0 while the morph is far
     * away, 1 once it arrives. Content opacities key off this, not their own
     * timers, so a surface fades in as the pill reaches full size, never over a
     * half-grown pill.
     */
    readonly property real morphCloseness: {
        const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH));
        return 1 - Math.min(1, d / (110 * s));
    }
    /**
     * How present the hover face's content is: the clock, media bud and tray
     * render at full strength whenever the pill is in hover mode, no matter how
     * far the morph has travelled. That includes the rest-to-hover hop (via
     * hoverHop) and a menu closing back into the pill (surface-to-hover) - the
     * media card returns the moment the close starts instead of waiting for the
     * pill to finish shrinking. Only non-hover modes gate content on the morph,
     * so surfaces still fade in as the pill grows to their size.
     */
    readonly property real contentMorph: {
        if (mode === "hover")
            return 1;
        return morphCloseness;
    }

    /**
     * Gate the soul bead until the hover morph has arrived and its icons exist.
     * Fire it earlier and the bead aims at anchors that aren't laid out yet.
     * Latched so small width changes inside hover (workspace dot growing, tray
     * icons appearing) don't flicker the bead off.
     */
    property bool hoverSoulGate: false
    readonly property bool hoverArrived: mode === "hover" && morphCloseness > 0.55
    onHoverArrivedChanged: if (hoverArrived) hoverSoulGate = true

    /**
     * Rest and hover sit a few dozen pixels apart, so the 420ms morph is nearly
     * all settle tail on that hop and reads sluggish. Both endpoints in the
     * rest/hover pair get the shorter glide; every real surface morph keeps the
     * full duration.
     */
    property string lastMode: "rest"
    property bool hoverHop: false

    /**
     * True when the pill entered hover mode by shrinking from an open surface
     * (or OSD/toast) rather than growing from rest. HoverFace reads this to
     * fade its content in with the pill's settle, so closing a surface never
     * flashes the hover face over the dissolving surface. Recomputed on every
     * mode change.
     */
    property bool closeArrive: false

    onModeChanged: {
        /**
         * Keep the cava capture only while the bars can actually render:
         * at rest with auto-hide on the pill is retracted off-screen, so the
         * capture would feed an invisible visualizer.
         */
        Cava.pillWanted = mode === "rest" && !Flags.autoHide;
        /** Touch the last-opened timestamp so the idle cleaner sees recent use. */
        if (pill.surfaces[mode] !== undefined)
            pill._surfaceLastOpened[mode] = Date.now();
        hoverHop = (mode === "hover" || mode === "rest") && (lastMode === "hover" || lastMode === "rest");
        /** Computed before lastMode is overwritten: hover reached by shrinking from a non-rest mode, not by growing from rest. */
        closeArrive = mode === "hover" && lastMode !== "hover" && lastMode !== "rest";
        lastMode = mode;
        if (mode !== "hover") {
            hoverSoulGate = false;
            soulTarget = "";
            hoverFace.calendarStrip.hoveredIndex = -1;
            faceFocus = -1;
        }
    }
    onHoverSoulGateChanged: if (hoverSoulGate) kanjiFlashAnim.restart()

    /**
     * Toggling auto-hide at rest never changes `mode`, so re-evaluate the
     * capture here too: turning it on must stop the invisible bars, turning
     * it off must wake them.
     */
    Connections {
        target: Flags
        function onAutoHideChanged() {
            Cava.pillWanted = pill.mode === "rest" && !Flags.autoHide;
        }
    }

    Component.onCompleted: {
        Cava.pillWanted = mode === "rest" && !Flags.autoHide;
        /** Loaders register themselves by name, so the map is complete by now. */
        pill._surfaceCleanupReady = true;
    }

    property string soulTarget: ""

    property real kanjiFlash: 0

    SequentialAnimation {
        id: kanjiFlashAnim
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 1; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 0; duration: 320; easing.type: Easing.OutCubic }
    }

    Behavior on width { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    Behavior on height { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    Behavior on morphRadius { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }

    Item {
        id: pillSurface

        anchors.fill: parent

        property int cornerSize: pill.morphRadius

        /**
         * Shared pill surface colors.
         *
         * Colors stay unmodified here because opacity is applied
         * once to the complete surface stack.
         */
        readonly property color surfaceTop: Theme.cardTop
        readonly property color surfaceBottom: Theme.cardBot

        /**
         * Notch <-> pill morph, driven by the pill's notchProgress (1 = notch
         * look). The ears retract into the body while the top corners round,
         * overlapping through the middle so the rounding corner absorbs the
         * shrinking ear - one wave that runs the full transition with no dead
         * time at either end. Mirrored when entering notch.
         */
        readonly property real earRise: {
            var t = Math.max(0, Math.min(1, (pill.notchProgress - 0.4) / 0.6));
            return t * t * (3 - 2 * t);
        }
        readonly property real cornerRound: {
            var t = Math.max(0, Math.min(1, (0.7 - pill.notchProgress) / 0.7));
            return t * t * (3 - 2 * t);
        }

        /**
         * Complete surface opacity.
         *
         * Applies consistently to body, media bleed, and ears.
         */
        opacity: Flags.pillOpacity


        /**
         * Media/content layer.
         *
         * Anything placed here can bleed into the notch ears.
         * The body and ears provide the final surface treatment.
         */
        Item {
            id: contentLayer
            anchors.fill: parent
            z: 0
        }

        /**
         * Left notch ear border.
         */
        RoundCorner {
            visible: pillSurface.earRise > 0.01
            opacity: pillSurface.earRise

            anchors.right: body.left
            anchors.top: body.top
            anchors.rightMargin: -1

            /** Shrink the radius instead of scaling so the arc keeps its shape as it deflates into the corner. */
            size: (pill.morphRadius + Flags.notchFlare) * pillSurface.earRise
            corner: RoundCorner.CornerEnum.TopRight
            color: Theme.border
            z: 1
        }

        /**
         * Left notch ear fill.
         *
         * Transparent so media/content can bleed through.
         */
        RoundCorner {
            visible: pillSurface.earRise > 0.01
            opacity: pillSurface.earRise

            anchors.right: body.left
            anchors.top: body.top
            anchors.rightMargin: -1

            size: pill.morphRadius * pillSurface.earRise
            corner: RoundCorner.CornerEnum.TopRight
            color: "transparent"
            z: 1
        }

        /**
         * Right notch ear border.
         */
        RoundCorner {
            visible: pillSurface.earRise > 0.01
            opacity: pillSurface.earRise

            anchors.left: body.right
            anchors.top: body.top
            anchors.leftMargin: -1

            size: (pill.morphRadius + Flags.notchFlare) * pillSurface.earRise
            corner: RoundCorner.CornerEnum.TopLeft
            color: Theme.border
            z: 1
        }

        /**
         * Right notch ear fill.
         *
         * Transparent so media/content can bleed through.
         */
        RoundCorner {
            visible: pillSurface.earRise > 0.01
            opacity: pillSurface.earRise

            anchors.left: body.right
            anchors.top: body.top
            anchors.leftMargin: -1

            size: pill.morphRadius * pillSurface.earRise
            corner: RoundCorner.CornerEnum.TopLeft
            color: "transparent"
            z: 1
        }

        Rectangle {
            id: body
            anchors.fill: parent
            z: 2
            property real gameFlat: pill.mode === "game" ? 1 : 0

            Behavior on gameFlat {
                NumberAnimation {
                    duration: Motion.morph
                    easing.type: Motion.easeMorph
                    easing.bezierCurve: Motion.morphCurve
                }
            }

            radius: pill.morphRadius
            topLeftRadius: pill.morphRadius * pillSurface.cornerRound * (1 - gameFlat)
            topRightRadius: pill.morphRadius * pillSurface.cornerRound * (1 - gameFlat)
            bottomLeftRadius: pill.morphRadius * (1 - gameFlat)
            bottomRightRadius: pill.morphRadius * (1 - gameFlat)

            border.width: 1
            border.color: Theme.border

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: pillSurface.surfaceTop
                }
                GradientStop {
                    position: 1.0
                    color: pillSurface.surfaceBottom
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                shadowBlur: 0.7
                shadowVerticalOffset: 3 * pill.s
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: body.radius * 0.6
                anchors.rightMargin: body.radius * 0.6
                height: 1
                color: Theme.sheen
            }
        }
    }

    /**
     * Rest anchor for Ame: the 時 kanji centre. The idle outline condenses into
     * the bead here before it moves.
     */
    readonly property point wakePoint: {
        void pill.width;
        void pill.height;
        return restKanji.mapToItem(pill, restKanji.width / 2, restKanji.height / 2);
    }

    /**
     * Bead target while hovered. soulTarget is a sticky key written by the hover
     * sources: the bead parks on the last focused icon and glides to the next, so
     * crossing a gap between targets doesn't snap it back. With no target it
     * rests below the hover strip's highlighted next-day (or under the hovered
     * day). Pill geometry is voided so the anchor follows the hover morph,
     * the point stays live.
     */
    readonly property point soulPoint: {
        void pill.width;
        void pill.height;
        const drop = 12 * pill.s;
        if (soulTarget === "wifi")
            return wifiIcon.mapToItem(pill, wifiIcon.width / 2, wifiIcon.height + drop * 0.55);
        if (soulTarget === "battery")
            return batteryIcon.mapToItem(pill, batteryIcon.width / 2, batteryIcon.height + drop * 0.55);
        if (soulTarget === "inbox")
            return inboxIcon.mapToItem(pill, inboxIcon.width / 2, inboxIcon.height + drop * 0.55);
        if (soulTarget === "mixer")
            return mixerIcon.mapToItem(pill, mixerIcon.width / 2, mixerIcon.height + drop * 0.55);
        if (soulTarget === "power")
            return powerIcon.mapToItem(pill, powerIcon.width / 2, powerIcon.height + drop * 0.55);
        if (soulTarget === "settings")
            return settingsIcon.mapToItem(pill, settingsIcon.width / 2, settingsIcon.height + drop * 0.55);
        if (soulTarget === "recorder")
            return recorderIcon.mapToItem(pill, recorderIcon.width / 2, recorderIcon.height + drop * 0.55);
        if (soulTarget === "sysmon")
            return sysmonIcon.mapToItem(pill, sysmonIcon.width / 2, sysmonIcon.height + drop * 0.55);
        /**
         * Calendar strip or no focused target: rest under the strip's
         * highlighted next-day (or under the hovered day, tracked by
         * CalendarStyle's ameAnchor).
         */
        return hoverFace.calendarStrip.mapToItem(pill, hoverFace.calendarStrip.ameAnchor.x, hoverFace.calendarStrip.ameAnchor.y);
    }

    /**
     * Which open surface owns Ame's anchor. Each surface exports its own
     * `ameForm`/`amePoint`; the pill picks the open surface's `ame` from the
     * descriptor and maps it. Null = nothing open (or a surface with no anchor,
     * e.g. wallpaper), so Ame falls back to the pill's own hover/wake anchor.
     */
    /**
     * While the OSD preempts the surface, the bead goes quiet (form "off")
     * instead of parking at the squished surface anchor inside the OSD-sized
     * body.
     */
    readonly property var ameSurface: (surfaceOpen && pill.mode !== "osd" && surfaces[surface] !== undefined)
        ? surfaces[surface].ame() : null

    Ame {
        id: ame
        anchors.fill: parent
        /**
         * Above the surface loaders so the caret/bead isn't hidden under opaque
         * surface content (the polkit prompt's field capsule), but below the
         * body so it keeps the body's translucency like every other element.
         */
        z: 1
        s: pill.s
        heat: (pill.powerOpen && ldPower.item) ? ldPower.item.holdProgress : 0
        wake: pill.wakePoint
        wickDir: pill.powerOpen ? 1 : -1
        form: pill.ameSurface ? pill.ameSurface.ameForm
            : (pill.mode === "hover" && pill.hoverSoulGate ? "soul" : "off")
        point: pill.ameSurface
            ? Qt.point(pill.ameSurface.x + pill.ameSurface.amePoint.x,
                       pill.ameSurface.y + pill.ameSurface.amePoint.y)
            : (pill.mode === "hover" ? pill.soulPoint : pill.wakePoint)
    }

    /**
     * No input pad: the media bud lives inside the hover row's bounds, so the
     * mask never needs to extend past the pill. (The old expression read a
     * nonexistent `budR`; while `shown` was an undeclared property it short-
     * circuited to 0, but once Media gained a real `shown` it evaluated
     * `undefined + 2*s` = NaN, which collapsed the window mask and killed all
     * hover input on the pill.) pill.hovered is fed by a window-level
     * HoverHandler in shell.qml: pointer events only exist inside the input
     * mask, so "window hovered" means "pointer over the pill (or bud)".
     */
    readonly property real inputPadRight: 0

    onHoveredChanged: {
        if (hovered) {
            hoverLatch = true;
            graceTimer.stop();
        } else {
            graceTimer.restart();
        }
    }

    Timer {
        id: graceTimer
        interval: 300
        onTriggered: {
            if (pill.morphCloseness < 0.95) {
                graceTimer.restart();
                return;
            }
            pill.hoverLatch = false;
        }
    }

    TapHandler {
        enabled: !pill.surfaceOpen
        gesturePolicy: TapHandler.WithinBounds
        onTapped: pill.pinned = !pill.pinned
    }

    /**
     * Game-mode face: the pill docks into a flush top bar carrying only the clock
     * and, when something plays, the current track. Everything else the desktop
     * usually shows is deliberately gone.
     */
    GameBar {
        id: gameBar
        anchors.fill: parent
        s: pill.s
        active: pill.mode === "game"
        morph: pill.morphCloseness
        time: clock.hhmm
        osd: osd
    }

    Item {
        id: rest
        anchors.fill: parent
        /**
         * Fades in as the pill settles — but only after the hover clock has
         * landed. Without the handoff gate the rest content (the visualizer
         * bars, which flip visible the moment mode becomes "rest") would
         * appear mid-collapse and flash ahead of the returning clock; the
         * (1 - clockHandoff) factor keeps the whole rest face hidden until
         * the clock reaches the rest spot, then it arrives with the swap.
         */
        opacity: (pill.expanded || pill.dragActive || pill.mode === "game" || pill.mode === "toast" || pill.mode === "osd" || pill.mode === "quickChoose" || pill.mode === "quickCount" || pill.hidden) ? 0 : Math.pow(pill.morphCloseness, 1.5) * (1 - hoverFace.clockHandoff)
        visible: opacity > 0.01
        /**
         * While at rest the fade-in is a pure per-frame binding (morphCloseness
         * × handoff) riding the pill's own animated geometry — a Behavior would
         * re-target every frame against that moving value and add lag plus
         * judder. The Behavior stays for the other modes, where the face is
         * driven to a constant 0 and needs a real fade-out.
         */
        Behavior on opacity {
            enabled: pill.mode !== "rest"
            NumberAnimation { duration: pill.mode === "rest" ? Motion.fast : Math.round(260 * Motion.mult) }
        }

        Row {
            id: restRow
            anchors.centerIn: parent
            spacing: 9 * pill.s
            Item {
                id: restKanji
                visible: pill.specialView === ""

                /**
                 * Audio leaving the speakers flips the left slot into the live
                 * waveform. The slot takes the visualizer's explicit size, not its
                 * implicit one: MusicBars is a Row whose implicitWidth collapses to
                 * zero in string mode (FastMusicLine is a transparent Rectangle),
                 * which would park the string on a point and let it overlap the
                 * clock. The explicit width keeps the slot stable for both the
                 * bars and the string renderer.
                 *
                 * The slot keeps a constant footprint (while the normal row is
                 * showing) so the row layout never re-runs as the bars appear
                 * and disappear: the clock's slide is a direct Translate on the
                 * clock below, which renders as a clean glide instead of the
                 * sub-pixel layout stepping that made the old layout-driven
                 * slide stutter.
                 */
                readonly property bool barsOn: Flags.musicViz && Cava.active

                /**
                 * The visualizer only renders while the pill is actually at
                 * rest. Leaving rest (a surface, hover, game mode) drops it on
                 * the fast curve so the string never bleeds into the incoming
                 * surface as it morphs open.
                 */
                readonly property bool vizShown: barsOn && pill.mode === "rest"

                anchors.verticalCenter: parent.verticalCenter

                width: pill.specialView === "" ? musicBars.width : 0
                height: pill.specialView === "" ? musicBars.height : 0

                MusicBars {
                    id: musicBars
                    anchors.centerIn: parent
                    s: pill.s

                    centeredVisualizer: Flags.vizStyle === "centered"
                    stringVisualizer: Flags.vizStyle === "string"
                    live: Flags.musicViz
                    resting: pill.mode === "rest"

                    opacity: restKanji.vizShown ? 1 : 0
                    scale: restKanji.vizShown ? 1 : 0.7

                    Behavior on opacity {
                        NumberAnimation {
                            duration: restKanji.vizShown ? Motion.standard : Motion.fast
                            easing.type: restKanji.vizShown ? Motion.easeStandard : Easing.OutQuad
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            /**
                             * A soft OutBack overshoot on the way in gives the
                             * bloom a subtle spring; the fast OutQuad collapse
                             * reads as a clean, quick retract.
                             */
                            duration: restKanji.vizShown ? Motion.standard : Motion.fast
                            easing.type: restKanji.vizShown ? Easing.OutBack : Easing.OutQuad
                        }
                    }
                }
            }
            Text {
                id: restTime
                visible: pill.specialView === ""
                anchors.verticalCenter: parent.verticalCenter
                text: clock.hhmm
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 18 * pill.s
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }

                /**
                 * The clock's slide is a direct translate, not a layout slide:
                 * the row keeps a constant footprint (see restKanji), so nothing
                 * re-lays out while it moves. The clock sits at its bars-present
                 * spot; offsetting it left by half the visualizer width plus half
                 * the row spacing parks it dead-centre when the bars are hidden
                 * (the row's centre of mass keeps the pill balanced while the
                 * bars show). Both directions glide on one short, silky OutSine
                 * - fast enough to read as a single motion with no stutter, and
                 * no overshoot.
                 */
                property real clockSlide: restKanji.barsOn ? 0 : -((musicBars.width + restRow.spacing) / 2)

                transform: Translate {
                    x: restTime.clockSlide
                }

                Behavior on clockSlide {
                    NumberAnimation {
                        duration: Math.round(160 * Motion.mult)
                        easing.type: Easing.OutSine
                    }
                }

                /**
                 * Hands off to the hover clock in the first moments of the hop
                 * (hoverFace.clockHandoff), while the hover clock still sits
                 * exactly on this spot at this size — the swap is invisible
                 * and the growing clock reads as one clock, never a ghost.
                 */
                opacity: 1 - hoverFace.clockHandoff
            }
            Text {
                visible: pill.specialView !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.specialView
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
            }
        }
    }

    /**
     * Expanded (hover) face: the clock growth + handoff, media bud, minimized
     * row, tray and calendar strip, extracted to its own file. The pill feeds
     * it the time text and rest-clock reference; Nav drives its per-icon rows
     * through the aliases below.
     */
    HoverFace {
        id: hoverFace
        anchors.fill: parent
        host: pill
        restClock: restTime
        timeText: clock.hhmm
    }

    /**
     * Morphing surfaces, one self-registering PillSurfaceLoader each. Each
     * names its surface and is registered into _surfaceLoaders on creation;
     * the loader supplies s/open/morphCloseness, so the sourceComponents only
     * carry their surface-specific props and signals.
     *
     * Surfaces build asynchronously (`asynchronous: true`) so their first open
     * never blocks the frame that starts the morph — the size thunks above
     * fall back to a default size until the item lands, then the pill re-morphs
     * to the real measurement. Only the instant-expected surfaces (polkit
     * prompt, power, mixer, timer, battery, calendar) stay synchronous so they
     * appear on the opening frame.
     */

    PillSurfaceLoader { id: ldMixer; name: "mixer"; host: pill; sourceComponent: Mixer {} }

    PillSurfaceLoader { id: ldCalendar; name: "calendar"; host: pill; sourceComponent: Calendar { targetDate: pill.calendarFocusDate } }

    PillSurfaceLoader { id: ldLauncher; name: "launcher"; asynchronous: true; host: pill; sourceComponent: Launcher { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldClip; name: "clipboard"; asynchronous: true; host: pill; sourceComponent: Clipboard { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldWall; name: "wallpaper"; asynchronous: true; host: pill; sourceComponent: Wallpaper { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldPower; name: "power"; host: pill; sourceComponent: Power { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldMedia; name: "media"; asynchronous: true; host: pill; sourceComponent: Media { shown: pill.mediaOpen; onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldLink; name: "link"; asynchronous: true; host: pill; sourceComponent: Link {
        initialView: pill.linkInitialView
        onRequestClose: pill.requestClose()
    } }

    onLinkOpenChanged: if (!linkOpen) linkInitialView = "main"

    PillSurfaceLoader { id: ldBattery; name: "battery"; host: pill; sourceComponent: BatterySurface { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldSettings; name: "settings"; asynchronous: true; host: pill; sourceComponent: Settings { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldKeybinds; name: "keybinds"; asynchronous: true; host: pill; sourceComponent: Keybinds { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldWorkspaces; name: "workspaces"; asynchronous: true; host: pill; sourceComponent: WorkspacesSurface { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldStash; name: "stash"; asynchronous: true; host: pill; sourceComponent: Stash { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldSpaceapps; name: "spaceapps"; asynchronous: true; host: pill; sourceComponent: SpaceApps { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldRecorder; name: "recorder"; asynchronous: true; host: pill; sourceComponent: Recorder { screenName: pill.screenName; onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldPolkit; name: "polkit"; host: pill; sourceComponent: PolkitPrompt { onRequestClose: Polkit.cancel() } }

    PillSurfaceLoader { id: ldSysmon; name: "sysmon"; asynchronous: true; host: pill; sourceComponent: SysmonSurface { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldAppearance; name: "appearance"; asynchronous: true; host: pill; sourceComponent: Appearance { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldUpdates; name: "updates"; asynchronous: true; host: pill; sourceComponent: Updates { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldDisplay; name: "display"; asynchronous: true; host: pill; sourceComponent: Display { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldInput; name: "input"; asynchronous: true; host: pill; sourceComponent: Input { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldLook; name: "look"; asynchronous: true; host: pill; sourceComponent: Look { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldIdlelock; name: "idlelock"; asynchronous: true; host: pill; sourceComponent: IdleLock { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldAnimation; name: "animation"; asynchronous: true; host: pill; sourceComponent: AnimationSurface { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldFontpicker; name: "fontpicker"; asynchronous: true; host: pill; sourceComponent: FontPicker { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldTimer; name: "timer"; host: pill; sourceComponent: Pomodoro {} }
    Osd {
        id: osd
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 18 * pill.s
        anchors.rightMargin: 18 * pill.s
        anchors.bottomMargin: 12 * pill.s
        s: pill.s
        screenName: pill.screenName
        /**
         * The OSD preempts any open surface, so only a held pill (pin/peek)
         * or a live polkit prompt suppresses it — morphing away from the
         * password field mid-prompt would hide the only way out.
         */
        suppressed: pill.held || pill.surface === "polkit"
        expanded: pill.expanded
        mixerOpen: pill.mixerOpen
        mediaOpen: pill.mediaOpen
        surfaceOpen: pill.surfaceOpen
        enabled: pill.mode === "osd"
        opacity: pill.mode === "osd" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }
    }

    Loader {
        id: toastLoader
        active: pill.toastActive
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 16 * pill.s
        anchors.rightMargin: 16 * pill.s
        anchors.bottomMargin: 12 * pill.s
        enabled: pill.mode === "toast"
        opacity: pill.mode === "toast" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        sourceComponent: Item {
            implicitHeight: toastContent.implicitHeight

            Toast {
                id: toastContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                s: pill.s
                live: pill.mode === "toast"
                notif: Notifs.popups.length > 0 ? Notifs.popups[Notifs.popups.length - 1] : null
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: Notifs.popups.length > 1
                text: "+" + (Notifs.popups.length - 1)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9 * pill.s
                font.weight: Font.DemiBold
            }
        }
    }

    /**
     * Standalone quick-record source chooser. Driven by the SUPER+D keybind with
     * no recorder surface open: it grows the pill on the focused monitor only
     * (mode "quickChoose") and offers the same Screen and Window / Region picks as
     * the surface. Screen with one monitor resolves at once; several monitors flip
     * to the inline sub-choice. A pick fires ScreenRec.prepareScreen / prepareWindow
     * → targetReady → the central countdown, then closes.
     */
    QuickChooser {
        id: quickChooser
        anchors.fill: parent
        anchors.margins: 6 * pill.s
        s: pill.s
        active: pill.mode === "quickChoose"
        morph: pill.morphCloseness
        onPickSource: (kind) => pill.quickChooseSource(kind)
        onPickMonitor: (name) => pill.quickPickMonitor(name)
    }

    QuickCount {
        id: quickCount
        anchors.fill: parent
        s: pill.s
        active: pill.mode === "quickCount"
        morph: pill.morphCloseness
    }

    /**
     * Drag-to-install pipeline, restored from Ricelin: dropping a file on the
     * resting pill hands it to app-install.sh (AppImages, native packages,
     * fonts, wallpapers), which prints one machine-readable line per drop.
     * The pill morphs into a drop-zone face, streams the installer's output
     * live, then opens the launcher when an app landed.
     */
    property var installQueue: []

    function localPath(url) {
        var s = String(url);
        if (s.indexOf("file://") === 0)
            s = s.substring(7);
        return decodeURIComponent(s);
    }

    readonly property var dropExt: /\.(appimage|deb|rpm|flatpakref|zip|tgz|txz|tbz2|ttf|otf|png|jpe?g|webp)$|\.(pkg\.)?tar\.(gz|xz|bz2|zst)$/i

    function droppablePaths(urls) {
        var out = [];
        for (var i = 0; i < urls.length; i++)
            if (pill.dropExt.test(String(urls[i])))
                out.push(pill.localPath(urls[i]));
        return out;
    }

    function dropLabel(urls) {
        var p = pill.localPath(urls.length ? urls[0] : "");
        return p.substring(p.lastIndexOf("/") + 1).replace(pill.dropExt, "");
    }

    property bool installedAny: false
    property bool installedApp: false
    property bool installFailed: false
    property string installKind: "app"
    property string installAction: "new"
    property string installLine: ""
    property string installProto: ""
    property string installPct: ""
    property int installSeconds: 0

    function runNextInstall() {
        if (pill.installQueue.length === 0) {
            pill.dragStage = pill.installedAny ? "done" : "fail";
            (pill.installedAny ? dropDoneTimer : dropBadTimer).restart();
            return;
        }
        var next = pill.installQueue.shift();
        pill.dragName = next.substring(next.lastIndexOf("/") + 1).replace(pill.dropExt, "");
        pill.installLine = "";
        pill.installProto = "";
        pill.installPct = "";
        installProc.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/app-install.sh", "install", next];
        installProc.running = true;
    }

    /**
     * Streams installer stdout instead of collecting it: slow backends
     * (flatpak runtime pulls, pacman) narrate their steps, and the drop face
     * mirrors the newest line live. The machine-readable result is the one
     * tab-separated kind-prefixed line, fished out of the stream as it passes.
     */
    Process {
        id: installProc
        stdout: SplitParser {
            onRead: (data) => {
                var seg = data.split("\r").pop().replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
                if (seg.length === 0)
                    return;
                if (/^(app|native|font|wallpaper)\t/.test(seg)) {
                    pill.installProto = seg;
                } else {
                    pill.installLine = seg;
                    var pct = seg.match(/(\d{1,3})\s*%/);
                    if (pct && Number(pct[1]) <= 100)
                        pill.installPct = pct[1] + "%";
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && pill.installProto.length > 0) {
                pill.installedAny = true;
                var parts = pill.installProto.split("\t");
                pill.installKind = parts[0];
                pill.installAction = parts[2];
                if (parts[0] === "app" || parts[0] === "native")
                    pill.installedApp = true;
                if (parts[0] === "font" && parts.length >= 4)
                    droppedFont.source = "file://" + parts[3];
            } else {
                pill.installFailed = true;
            }
            pill.runNextInstall();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: pill.dragStage === "installing"
        onTriggered: pill.installSeconds++
    }

    /**
     * Registers a just-dropped font in this running process; the fontconfig
     * cache alone only reaches apps started later. Ready -> the font picker's
     * family list refreshes and the new face shows up without a restart.
     */
    FontLoader {
        id: droppedFont
        onStatusChanged: if (status === FontLoader.Ready) Theme.refreshFonts()
    }

    Timer {
        id: dropDoneTimer
        interval: 1100
        onTriggered: {
            pill.dragActive = false;
            pill.dragStage = "";
            if (pill.installedApp)
                pill.requestSurface("launcher");
        }
    }

    Timer {
        id: dropBadTimer
        interval: 1300
        onTriggered: {
            pill.dragActive = false;
            pill.dragStage = "";
        }
    }

    /**
     * File drops land only on the resting pill; an open surface turns the pill
     * into a fullscreen modal that swallows the drag before it can start.
     * app-install.sh routes each drop by type (apps install, fonts land in the
     * font dir, images become the wallpaper), anything else flashes a rejection.
     */
    DropArea {
        anchors.fill: parent
        enabled: !pill.surfaceOpen && pill.dragStage !== "installing" && pill.dragStage !== "done"
        keys: ["text/uri-list"]
        onEntered: (drag) => {
            drag.acceptProposedAction();
            pill.dragActive = true;
            pill.dragStage = pill.droppablePaths(drag.urls).length > 0 ? "hover" : "bad";
            pill.dragName = pill.dropLabel(drag.urls);
        }
        onExited: {
            if (pill.dragStage === "hover" || pill.dragStage === "bad") {
                pill.dragActive = false;
                pill.dragStage = "";
            }
        }
        onDropped: (drop) => {
            drop.acceptProposedAction();
            var files = pill.droppablePaths(drop.urls);
            if (files.length === 0) {
                pill.dragActive = true;
                pill.dragStage = "bad";
                pill.dragName = pill.dropLabel(drop.urls);
                dropBadTimer.restart();
                return;
            }
            pill.dragActive = true;
            pill.dragStage = "installing";
            pill.installedAny = false;
            pill.installedApp = false;
            pill.installFailed = false;
            pill.installKind = "app";
            pill.installAction = "new";
            pill.installSeconds = 0;
            pill.installQueue = files;
            pill.runNextInstall();
        }
    }

    /**
     * Drop-zone face: corner brackets frame a stage glyph and label that walk
     * from "drop to install" through the spinner to a checkmark. Shares the
     * morph fade of the other pill faces, so it grows in as the pill reaches
     * its size.
     */
    Item {
        id: dragOverView
        anchors.fill: parent
        anchors.margins: 11 * pill.s
        enabled: pill.mode === "dragOver"
        opacity: pill.mode === "dragOver" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        readonly property color accent: (pill.dragStage === "bad" || pill.dragStage === "fail") ? "#e0533f" : Theme.vermLit
        readonly property real brLen: 15 * pill.s
        readonly property real brThick: 2 * pill.s

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Item {
                id: corner
                required property var modelData
                readonly property bool rightSide: modelData[0] === 1
                readonly property bool bottomSide: modelData[1] === 1

                x: rightSide ? dragOverView.width - dragOverView.brLen : 0
                y: bottomSide ? dragOverView.height - dragOverView.brLen : 0
                width: dragOverView.brLen
                height: dragOverView.brLen

                Rectangle {
                    width: dragOverView.brLen
                    height: dragOverView.brThick
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
                Rectangle {
                    width: dragOverView.brThick
                    height: dragOverView.brLen
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 44 * pill.s
            spacing: 7 * pill.s

            /**
             * Stage glyph with a cross-morph between icons: the outgoing glyph
             * shrinks and fades away while the incoming one grows in, so the
             * stage changes (drop → spin → check, or a failed install snapping
             * to the close-circle) read as one continuous motion instead of an
             * instant swap. `prevName` holds the outgoing icon and is re-stamped
             * once the morph settles, so every change cross-fades from the icon
             * that was actually on screen. The spinning reboot rides the
             * incoming layer, so the spin keeps running through the fade-in.
             */
            Item {
                id: stageIcon
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26 * pill.s
                height: 26 * pill.s

                /** 0 = outgoing icon shown, 1 = incoming icon settled. */
                property real morph: 1
                /** The icon that was showing before the current one. */
                property string prevName: "download"

                readonly property string glyphName: (pill.dragStage === "bad" || pill.dragStage === "fail") ? "close-circle"
                    : (pill.dragStage === "installing" ? "reboot"
                    : (pill.dragStage === "done" ? "check" : "download"))

                onGlyphNameChanged: {
                    if (glyphName !== prevName)
                        swapAnim.restart();
                }

                SequentialAnimation {
                    id: swapAnim
                    ScriptAction { script: stageIcon.morph = 0 }
                    NumberAnimation {
                        target: stageIcon
                        property: "morph"
                        to: 1
                        duration: Motion.standard
                        easing.type: Motion.easeStandard
                    }
                    ScriptAction { script: stageIcon.prevName = stageIcon.glyphName }
                }

                /** Outgoing icon: shrinks and fades away. */
                GlyphIcon {
                    anchors.fill: parent
                    stroke: 2
                    color: dragOverView.accent
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    name: stageIcon.prevName
                    opacity: 1 - stageIcon.morph
                    scale: 1 - 0.15 * stageIcon.morph
                }

                /** Incoming icon: grows in over the outgoing one. */
                GlyphIcon {
                    id: dragGlyph
                    anchors.fill: parent
                    stroke: 2
                    color: dragOverView.accent
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    name: stageIcon.glyphName
                    opacity: stageIcon.morph
                    scale: 0.7 + 0.3 * stageIcon.morph
                    RotationAnimation on rotation {
                        running: pill.dragStage === "installing"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                    onNameChanged: if (pill.dragStage !== "installing") rotation = 0
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pill.dragStage === "bad" ? "Can't install this"
                    : (pill.dragStage === "fail" ? "Install failed"
                    : (pill.dragStage === "installing" ? ("Installing"
                    + (pill.installPct.length > 0 ? " " + pill.installPct : "")
                    + (pill.installSeconds >= 3 ? " " + Math.floor(pill.installSeconds / 60) + ":" + String(pill.installSeconds % 60).padStart(2, "0") : ""))
                    : (pill.dragStage === "done" ? (pill.installFailed ? "Installed, some failed"
                    : (!pill.installedApp && pill.installKind === "wallpaper" ? "Wallpaper set"
                    : (!pill.installedApp && pill.installKind === "font" ? "Font installed"
                    : (pill.installAction === "updated" ? "Updated"
                    : (pill.installAction === "reinstalled" ? "Reinstalled" : "Installed")))))
                    : "Drop to install")))
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * pill.s
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: pill.dragStage === "installing" && pill.installLine.length > 0 ? pill.installLine : pill.dragName
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * pill.s
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }
}

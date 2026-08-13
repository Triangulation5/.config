pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.pill.widgets
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
    readonly property bool batteryOpen: surface === "battery"
    readonly property bool settingsOpen: surface === "settings"
    readonly property bool keybindsOpen: surface === "keybinds"
    readonly property bool workspacesOpen: surface === "workspaces"
    readonly property bool stashOpen: surface === "stash"
    readonly property bool spaceappsOpen: surface === "spaceapps"
    readonly property bool recorderOpen: surface === "recorder"
    readonly property bool sysmonOpen: surface === "sysmon"
    readonly property bool appearanceOpen: surface === "appearance"
    readonly property bool updatesOpen: surface === "updates"
    readonly property bool displayOpen: surface === "display"
    readonly property bool inputOpen: surface === "input"
    readonly property bool lookOpen: surface === "look"
    readonly property bool idlelockOpen: surface === "idlelock"
    readonly property bool animationOpen: surface === "animation"
    readonly property bool fontpickerOpen: surface === "fontpicker"
    readonly property bool localsendOpen: surface === "localsend"
    readonly property bool hasPendingSend: ldLSend.item !== null && ldLSend.item.sendFile.length > 0
    /** Exposes the localsend widget's active state for the Link surface header badge. */
    readonly property string localsendActivity: {
        if (!ldLSend.item) return "";
        if (ldLSend.item.sending) return "sending";
        if (ldLSend.item.scanning) return "scanning";
        return ldLSend.item.sendFile.length > 0 ? "scanning" : "";
    }
    readonly property bool timerOpen: surface === "timer"
    readonly property bool settingsLike: settingsOpen || appearanceOpen || updatesOpen
        || lookOpen || inputOpen || displayOpen || animationOpen || idlelockOpen || fontpickerOpen
    /**
     * True only while something is actually playing. Gates the hover media
     * bud, so a paused, stopped, closed, or vanished player hides the widget
     * instead of leaving a stale card on screen.
     */
    readonly property bool hasMedia: Players.playing

    /**
     * Playback stopped (pause, stop, exit, kill) while the media surface owned
     * the pill: drop the surface so the pill morphs back to its normal state
     * instead of parking on a stale card. Driven purely by state changes - no
     * timers or timeouts.
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
    readonly property real localsendW: 360 * s
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
    readonly property real restCorner: 28 * s
    readonly property real openCorner: 22 * s

    /**
     * Latch-once lazy load with idle-timeout cleanup. Every surface sleeps in
     * an inactive Loader until first opened; the size and ame thunks below
     * resolve items through here. After a surface has been idle (not opened)
     * for `surfaceIdleTimeout` seconds its Loader is deactivated so the
     * component tree is destroyed, freeing RAM and GPU resources until the
     * next open reactivates it.
     */
    function surfaceItem(ld, name) {
        ld.active = true;
        if (name && name.length)
            _surfaceLastOpened[name] = Date.now();
        return ld.item;
    }

    /** Seconds a surface stays loaded after last use before being reclaimed. */
    property int surfaceIdleTimeout: 15

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
    /** File path handed to the localsend surface between open and item load. */
    property string _pendingSend: ""

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
         * The hover media bud stays loaded while anything plays, even with the
         * pill at rest and the bud off-screen. Reclaim it once it has been out
         * of hover mode for the idle timeout so an idle iGPU isn't paying for a
         * full Media widget (player lookups, cover art) that nobody can see.
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
     */
    readonly property var surfaces: ({
        calendar:  { size: () => { const it = surfaceItem(ldCalendar, "calendar"); return Qt.size((it.implicitWidth > 0 ? it.implicitWidth : 282 * s) + 36 * s, it.implicitHeight + 32 * s); }, ame: () => surfaceItem(ldCalendar, "calendar") },
        launcher:  { size: () => { surfaceItem(ldLauncher, "launcher"); return Qt.size(launcherW, launcherH); }, ame: () => surfaceItem(ldLauncher, "launcher") },
        clipboard: { size: () => { surfaceItem(ldClip, "clipboard"); return Qt.size(clipboardW, clipboardH); }, ame: () => surfaceItem(ldClip, "clipboard") },
        wallpaper: { size: () => { surfaceItem(ldWall, "wallpaper"); return Qt.size(wallpaperW, wallpaperH); }, ame: () => null },
        power:     { size: () => { surfaceItem(ldPower, "power"); return Qt.size(powerW, powerH); }, ame: () => surfaceItem(ldPower, "power") },
        media:     { size: () => { surfaceItem(ldMedia, "media"); return Qt.size(mediaW, mediaH); }, ame: () => surfaceItem(ldMedia, "media") },
        mixer:     { size: () => Qt.size(93 * Math.max(4, surfaceItem(ldMixer, "mixer").faderCount) * s, mixerH), ame: () => surfaceItem(ldMixer, "mixer") },
        link:      { size: () => { const it = surfaceItem(ldLink, "link"); return Qt.size(it.desiredW, it.implicitHeight + 26 * s); }, ame: () => surfaceItem(ldLink, "link") },
        battery:   { size: () => Qt.size(batteryW, surfaceItem(ldBattery, "battery").implicitHeight + 26 * s), ame: () => surfaceItem(ldBattery, "battery") },
        settings:  { size: () => Qt.size(settingsW, surfaceItem(ldSettings, "settings").implicitHeight + 29 * s), ame: () => surfaceItem(ldSettings, "settings") },
        keybinds:  { size: () => Qt.size(keybindsW, surfaceItem(ldKeybinds, "keybinds").implicitHeight + 29 * s), ame: () => surfaceItem(ldKeybinds, "keybinds") },
        workspaces: { size: () => Qt.size(workspacesW, surfaceItem(ldWorkspaces, "workspaces").implicitHeight + 29 * s), ame: () => surfaceItem(ldWorkspaces, "workspaces") },
        stash:     { size: () => Qt.size(stashW, surfaceItem(ldStash, "stash").implicitHeight + 29 * s), ame: () => surfaceItem(ldStash, "stash") },
        spaceapps: { size: () => Qt.size(spaceappsW, surfaceItem(ldSpaceapps, "spaceapps").implicitHeight + 29 * s), ame: () => surfaceItem(ldSpaceapps, "spaceapps") },
        recorder:  { size: () => Qt.size(recorderW, surfaceItem(ldRecorder, "recorder").implicitHeight + 33 * s), ame: () => surfaceItem(ldRecorder, "recorder") },
        sysmon:    { size: () => Qt.size(sysmonW, surfaceItem(ldSysmon, "sysmon").implicitHeight + 33 * s), ame: () => surfaceItem(ldSysmon, "sysmon") },
        appearance: { size: () => Qt.size(appearanceW, surfaceItem(ldAppearance, "appearance").implicitHeight + 29 * s), ame: () => surfaceItem(ldAppearance, "appearance") },
        updates:    { size: () => Qt.size(updatesW, surfaceItem(ldUpdates, "updates").implicitHeight + 29 * s), ame: () => surfaceItem(ldUpdates, "updates") },
        display:    { size: () => Qt.size(displayW, surfaceItem(ldDisplay, "display").implicitHeight + 29 * s), ame: () => surfaceItem(ldDisplay, "display") },
        input:      { size: () => Qt.size(inputW, surfaceItem(ldInput, "input").implicitHeight + 29 * s), ame: () => surfaceItem(ldInput, "input") },
        look:       { size: () => Qt.size(lookW, surfaceItem(ldLook, "look").implicitHeight + 29 * s), ame: () => surfaceItem(ldLook, "look") },
        idlelock:   { size: () => Qt.size(idlelockW, surfaceItem(ldIdlelock, "idlelock").implicitHeight + 29 * s), ame: () => surfaceItem(ldIdlelock, "idlelock") },
        animation:  { size: () => Qt.size(animationW, surfaceItem(ldAnimation, "animation").implicitHeight + 29 * s), ame: () => surfaceItem(ldAnimation, "animation") },
        fontpicker: { size: () => Qt.size(fontpickerW, surfaceItem(ldFontpicker, "fontpicker").implicitHeight + 29 * s), ame: () => surfaceItem(ldFontpicker, "fontpicker") },
        localsend:  { size: () => { surfaceItem(ldLSend, "localsend"); return Qt.size(localsendW, surfaceItem(ldLSend, "localsend").implicitHeight + 26 * s); }, ame: () => surfaceItem(ldLSend, "localsend") },
        timer:    { size: () => { const it = surfaceItem(ldTimer, "timer"); return Qt.size(timerW, it.implicitHeight + 28 * s); }, ame: () => null },
        polkit:    { size: () => { const it = surfaceItem(ldPolkit, "polkit"); return Qt.size(polkitW, it.implicitHeight + 28 * s); }, ame: () => surfaceItem(ldPolkit, "polkit") }
    })

    readonly property string mode: dragInstall.dragActive ? "dragOver"
        : (surfaceOpen && surfaces[surface] !== undefined ? surface
        : (Flags.gameMode ? "game"
        : (quickChoosing ? "quickChoose"
        : (quickCounting ? "quickCount"
        : (osdActive && !held ? "osd"
        : (toastActive && !held ? "toast"
        : (expanded ? "hover" : "rest")))))))

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
    function localsendMove(dir) { return navHost.localsendMove(dir); }
    function localsendActivate() { return navHost.localsendActivate(); }
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

    onSurfaceOpenChanged: if (surfaceOpen) {
        pinned = false;
        if (quickHere && ScreenRec.quickChoosing) {
            ScreenRec.quickChoosing = false;
            ScreenRec.quickScreenChoosing = false;
        }
    }

    QtObject {
        id: clock
        readonly property var loc: Qt.locale("en_US")
        readonly property var now: sysClock.date

        readonly property string timeFormat: (Flags.time12h ? "h:mm AP" : "HH:mm") + (Flags.clockSeconds ? ":ss" : "")
        readonly property string hhmm: Flags.time12h
            ? Qt.formatTime(now, timeFormat).replace(" AM", "").replace(" PM", "")
            : Qt.formatTime(now, timeFormat)
        readonly property string date: loc.toString(now, "ddd d MMM")
    }

    SystemClock {
        id: sysClock
        precision: Flags.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
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
        // Loaders register themselves by name, so the map is complete by now.
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
         * Single-wave melt for the notch <-> pill style swap, driven by the
         * pill's notchProgress (1 = notch look). The ears deflate downward and
         * fade while the top corners round on the same broad, overlapping band,
         * so the rounding body progressively absorbs the shrinking ear - one
         * continuous gesture with no staged handoff. Mirrored when entering
         * notch.
         */
        readonly property real earRise: {
            var t = Math.max(0, Math.min(1, (pill.notchProgress - 0.38) / 0.42));
            return t * t * (3 - 2 * t);
        }
        readonly property real cornerRound: {
            var t = Math.max(0, Math.min(1, (0.62 - pill.notchProgress) / 0.42));
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
            scale: pillSurface.earRise
            transformOrigin: Item.TopRight
            transform: Translate { y: (1 - pillSurface.earRise) * pill.morphRadius * 0.45 }

            anchors.right: body.left
            anchors.top: body.top
            anchors.rightMargin: -1

            size: pill.morphRadius + Flags.notchFlare
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
            scale: pillSurface.earRise
            transformOrigin: Item.TopRight
            transform: Translate { y: (1 - pillSurface.earRise) * pill.morphRadius * 0.45 }

            anchors.right: body.left
            anchors.top: body.top
            anchors.rightMargin: -1

            size: pill.morphRadius
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
            scale: pillSurface.earRise
            transformOrigin: Item.TopLeft
            transform: Translate { y: (1 - pillSurface.earRise) * pill.morphRadius * 0.45 }

            anchors.left: body.right
            anchors.top: body.top
            anchors.leftMargin: -1

            size: pill.morphRadius + Flags.notchFlare
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
            scale: pillSurface.earRise
            transformOrigin: Item.TopLeft
            transform: Translate { y: (1 - pillSurface.earRise) * pill.morphRadius * 0.45 }

            anchors.left: body.right
            anchors.top: body.top
            anchors.leftMargin: -1

            size: pill.morphRadius
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
    readonly property var ameSurface: (surfaceOpen && surfaces[surface] !== undefined)
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

    DragInstall {
        id: dragInstall
        anchors.fill: parent
        s: pill.s
        surfaceOpen: pill.surfaceOpen
        morph: pill.morphCloseness
        onLaunchRequested: pill.requestSurface("launcher")
        onShareRequested: (path) => {
            pill._pendingSend = path;
            pill.requestSurface("localsend");
            Qt.callLater(function() { if (ldLSend.item) ldLSend.item.sendFile = pill._pendingSend; });
        }
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
        opacity: (pill.expanded || dragInstall.dragActive || pill.mode === "game" || pill.mode === "toast" || pill.mode === "osd" || pill.mode === "quickChoose" || pill.mode === "quickCount") ? 0 : Math.pow(pill.morphCloseness, 1.5)
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: pill.mode === "rest" ? Motion.fast : Math.round(260 * Motion.mult) } }

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

                anchors.verticalCenter: parent.verticalCenter

                width: pill.specialView === "" ? musicBars.width : 0
                height: pill.specialView === "" ? musicBars.height : 0

                MusicBars {
                    id: musicBars
                    anchors.centerIn: parent
                    s: pill.s

                    centeredVisualizer: Flags.vizStyle === "centered"
                    stringVisualizer: Flags.vizStyle === "string"
                    live: restKanji.barsOn
                    resting: pill.mode === "rest"

                    opacity: restKanji.barsOn ? 1 : 0
                    scale: restKanji.barsOn ? 1 : 0.7

                    Behavior on opacity {
                        NumberAnimation {
                            duration: restKanji.barsOn ? Motion.standard : Motion.fast
                            easing.type: restKanji.barsOn ? Motion.easeStandard : Easing.OutQuad
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            /**
                             * A soft OutBack overshoot on the way in gives the
                             * bloom a subtle spring; the fast OutQuad collapse
                             * reads as a clean, quick retract.
                             */
                            duration: restKanji.barsOn ? Motion.standard : Motion.fast
                            easing.type: restKanji.barsOn ? Easing.OutBack : Easing.OutQuad
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
     */

    PillSurfaceLoader { id: ldMixer; name: "mixer"; host: pill; sourceComponent: Mixer {} }

    PillSurfaceLoader { id: ldCalendar; name: "calendar"; host: pill; sourceComponent: Calendar { targetDate: pill.calendarFocusDate } }

    PillSurfaceLoader { id: ldLauncher; name: "launcher"; host: pill; sourceComponent: Launcher { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldClip; name: "clipboard"; host: pill; sourceComponent: Clipboard { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldWall; name: "wallpaper"; host: pill; sourceComponent: Wallpaper { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldPower; name: "power"; host: pill; sourceComponent: Power { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldMedia; name: "media"; host: pill; sourceComponent: Media { shown: pill.mediaOpen; onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldLink; name: "link"; host: pill; sourceComponent: Link {
        initialView: pill.linkInitialView
        sendStatus: pill.localsendActivity
        onRequestClose: pill.requestClose()
        onOpenSend: pill.requestSurface("localsend")
    } }

    onLinkOpenChanged: if (!linkOpen) linkInitialView = "main"

    PillSurfaceLoader { id: ldBattery; name: "battery"; host: pill; sourceComponent: BatterySurface { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldSettings; name: "settings"; host: pill; sourceComponent: Settings { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldKeybinds; name: "keybinds"; host: pill; sourceComponent: Keybinds { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldWorkspaces; name: "workspaces"; host: pill; sourceComponent: WorkspacesSurface { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldStash; name: "stash"; host: pill; sourceComponent: Stash { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldSpaceapps; name: "spaceapps"; host: pill; sourceComponent: SpaceApps { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldRecorder; name: "recorder"; host: pill; sourceComponent: Recorder { screenName: pill.screenName; onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldPolkit; name: "polkit"; host: pill; sourceComponent: PolkitPrompt { onRequestClose: Polkit.cancel() } }

    PillSurfaceLoader { id: ldSysmon; name: "sysmon"; host: pill; sourceComponent: SysmonSurface { onRequestClose: pill.requestClose() } }

    PillSurfaceLoader { id: ldAppearance; name: "appearance"; host: pill; sourceComponent: Appearance { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldUpdates; name: "updates"; host: pill; sourceComponent: Updates { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldDisplay; name: "display"; host: pill; sourceComponent: Display { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldInput; name: "input"; host: pill; sourceComponent: Input { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldLook; name: "look"; host: pill; sourceComponent: Look { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldIdlelock; name: "idlelock"; host: pill; sourceComponent: IdleLock { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldAnimation; name: "animation"; host: pill; sourceComponent: AnimationSurface { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldFontpicker; name: "fontpicker"; host: pill; sourceComponent: FontPicker { onRequestSurface: (name) => pill.requestSurface(name) } }

    PillSurfaceLoader { id: ldLSend; name: "localsend"; host: pill; sourceComponent: Localsend {} }

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
        suppressed: pill.surfaceOpen || pill.held
        expanded: pill.expanded
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
}

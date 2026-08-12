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
import qs.components.icons
import qs.components.controls
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

    /** Custom made notch style bar. */
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
    readonly property bool authPending: updatesOpen && ldUpdates.item !== null && ldUpdates.item.applying

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
    readonly property real hoverW: hoverRow.implicitWidth + 3 * hoverPad
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
    readonly property real restCorner: 18 * s
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
    property int surfaceIdleTimeout: 60

    /** Timestamp of last open per surface name. */
    property var _surfaceLastOpened: ({})

    /** Loader id → surface name map, built in Component.onCompleted. */
    property var _surfaceLoaders: ({})
    /** True while the idle-cleanup timer has run at least once. */
    property bool _surfaceCleanupReady: false

    function _cleanupIdleSurfaces() {
        var now = Date.now();
        var timeout = pill.surfaceIdleTimeout * 1000;
        var ld;
        for (var name in pill._surfaceLoaders) {
            ld = pill._surfaceLoaders[name];
            if (!ld || !ld.active)
                continue;
            /** Never evict a running timer — it must persist in the background. */
            if (name === "timer" && ld.item && ld.item.timerState === "running")
                continue;
            var last = pill._surfaceLastOpened[name] || 0;
            if (now - last >= timeout)
                ld.active = false;
        }
    }

    Timer {
        id: idleCleanupTimer
        interval: 30000
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
        timer:    { size: () => { const it = surfaceItem(ldTimer, "timer"); return Qt.size(timerW, it.implicitHeight + 28 * s); }, ame: () => null }
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

    /**
     * Open the calendar surface, focused on `date` when non-null, or on the
     * real today when null. Used by the hover strip (the clicked day) and the
     * clock area (today).
     */
    function openCalendarAt(date) {
        calendarFocusDate = date
        requestSurface("calendar")
    }

    /**
     * Forward an arrow-key nudge to the open mixer's targeted fader. Returns true
     * when the mixer is open and a fader consumed the step.
     */
    function mixerStep(deltaPct) {
        return (pill.mixerOpen && ldMixer.item) ? ldMixer.item.stepFocused(deltaPct) : false;
    }

    /**
     * Move the open mixer's keyboard focus across the fader row; `dir` is +1
     * (right) or -1 (left). No-op unless the mixer is open.
     */
    function mixerFocusMove(dir) {
        if (pill.mixerOpen && ldMixer.item)
            ldMixer.item.moveFocus(dir);
    }

    /**
     * Forward an arrow-key nudge to the open recorder's focused audio fader.
     * Returns true when the recorder is open and a revealed fader consumed it.
     */
    function recorderStep(deltaPct) {
        return (pill.recorderOpen && ldRecorder.item) ? ldRecorder.item.stepFocused(deltaPct) : false;
    }

    /**
     * Resolve which settings-family surface owns keyboard row navigation right
     * now: the category index or one of its morphing sub-surfaces. Returns null
     * when none of them is open.
     */
    function rowNavSurface() {
        if (pill.settingsOpen)
            return ldSettings.item;
        if (pill.appearanceOpen)
            return ldAppearance.item;
        if (pill.lookOpen)
            return ldLook.item;
        if (pill.inputOpen)
            return ldInput.item;
        if (pill.displayOpen)
            return ldDisplay.item;
        if (pill.animationOpen)
            return ldAnimation.item;
        if (pill.idlelockOpen)
            return ldIdlelock.item;
        if (pill.fontpickerOpen)
            return ldFontpicker.item;
        return null;
    }

    /**
     * Move the focused settings row by `dir` (+1 down, -1 up), carrying the soul
     * seam. Returns true when a settings-family surface is open and consumed it.
     */
    function settingsMove(dir) {
        var nav = pill.rowNavSurface();
        if (!nav)
            return false;
        nav.kbMove(dir);
        return true;
    }

    /**
     * Step the focused settings row's control: a segmented choice cycles by
     * `dir`, a toggle is set on (dir > 0) or off. Returns true when consumed.
     */
    /**
     * Left/right on an open settings surface: adjust the focused row's value
     * (seg cycle, toggle flip, scrub bump). Returns false when the focused row
     * is a nav row (nothing to adjust) so vim h/l fall through to back/enter
     * instead of being swallowed.
     */
    function settingsAdjust(dir) {
        var nav = pill.rowNavSurface();
        if (!nav || !nav.rows || nav.rows.length === 0)
            return false;
        var idx = nav.kbIndex < 0 ? 0 : nav.kbIndex;
        if (idx >= nav.rows.length)
            return false;
        var r = nav.rows[idx];
        if (!r || r.kind === "nav")
            return false;
        if (nav.kbIndex < 0) {
            nav.kbIndex = 0;
            nav.focusRowItem = nav.rows[0].item;
        }
        nav.kbAdjust(dir);
        return true;
    }

    /**
     * Activate the focused settings row: a toggle flips, a nav row opens its
     * sub-surface. Returns true when a settings-family surface is open.
     */
    function settingsActivate() {
        var nav = pill.rowNavSurface();
        if (!nav)
            return false;
        nav.kbActivate();
        return true;
    }

    /**
     * Slide the open keybinds list's focused row by `dir` (+1 down, -1 up),
     * carrying the soul seam. No-op unless the keybinds surface is open.
     */
    function keybindsMove(dir) {
        if (pill.keybindsOpen && ldKeybinds.item)
            ldKeybinds.item.move(dir);
    }

    /**
     * Enter on the open keybinds surface: arm chord capture on the focused row.
     * No-op unless the keybinds surface is open.
     */
    function keybindsActivate() {
        if (pill.keybindsOpen && ldKeybinds.item)
            ldKeybinds.item.activate();
    }

    readonly property bool keybindsListening: pill.keybindsOpen && ldKeybinds.item !== null && ldKeybinds.item.listening

    /**
     * A tile was picked in the standalone quick-record chooser. Screen with several
     * monitors flips to the inline sub-choice; otherwise each source kicks off its
     * resolver (which counts down once the target is ready) and the chooser closes.
     */
    function quickChooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                ScreenRec.quickScreenChoosing = true;
                return;
            }
            ScreenRec.prepareScreen(pill.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
    }

    function quickPickMonitor(name) {
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
        ScreenRec.prepareScreen(name);
    }

    /**
     * Pop the open link surface one subview back. Returns true when the step was
     * consumed, false when the surface is already at its root (or not open) and
     * Escape should close the surface instead.
     */
    function linkBack() {
        return (pill.linkOpen && ldLink.item) ? ldLink.item.back() : false;
    }

    /**
     * Step the open surface back one level when its header bar is clicked: a
     * settings sub-surface returns to the index, the font picker to appearance,
     * a keybinds form to its list, and any other surface dismisses to the hover
     * pill. Empty space in the body never triggers this.
     */
    function surfaceBack() {
        if (pill.keybindsOpen) {
            if (ldKeybinds.item && ldKeybinds.item.formOpen)
                ldKeybinds.item.closeForm();
            else
                pill.requestSurface("settings");
            return;
        }
        if (pill.fontpickerOpen) {
            pill.requestSurface("appearance");
            return;
        }
        if (pill.stashOpen) {
            if (ldStash.item && ldStash.item.addOpen)
                ldStash.item.closeAdd();
            else
                pill.requestSurface("workspaces");
            return;
        }
        if (pill.spaceappsOpen) {
            if (ldSpaceapps.item && ldSpaceapps.item.addOpen)
                ldSpaceapps.item.closeAdd();
            else
                pill.requestSurface("workspaces");
            return;
        }
        if (pill.workspacesOpen && ldWorkspaces.item && ldWorkspaces.item.formOpen) {
            ldWorkspaces.item.closeForm();
            return;
        }
        if (pill.calendarOpen && ldCalendar.item && ldCalendar.item.editorShown) {
            ldCalendar.item.closeEditor();
            return;
        }
        if (pill.appearanceOpen || pill.updatesOpen || pill.displayOpen || pill.inputOpen || pill.lookOpen || pill.idlelockOpen || pill.animationOpen || pill.workspacesOpen) {
            pill.requestSurface("settings");
            return;
        }
        pill.requestClose();
    }

    /**
     * Pop the open keybinds editor form back to the bind list. Returns true when a
     * form was open and dismissed, false otherwise so Escape closes the surface.
     */
    function keybindsBack() {
        if (pill.keybindsOpen && ldKeybinds.item && ldKeybinds.item.formOpen) {
            ldKeybinds.item.closeForm();
            return true;
        }
        return false;
    }

    /**
     * Slide the open wallpaper strip's focus by `dir` thumbs; +1 is right (older)
     * and -1 is left (newer). No-op unless the wallpaper surface is open.
     */
    function wallpaperMove(dir) {
        if (pill.wallpaperOpen && ldWall.item)
            ldWall.item.move(dir);
    }

    /**
     * Apply the wallpaper strip's focused thumb through wallpaper.sh. The
     * surface stays open so the pick can be iterated. No-op unless the
     * wallpaper surface is open.
     */
    function wallpaperActivate() {
        if (pill.wallpaperOpen && ldWall.item)
            ldWall.item.activate();
    }

    /** Keyboard hold-to-delete on the wallpaper strip. */
    function wallpaperHoldPress() {
        if (pill.wallpaperOpen && ldWall.item)
            ldWall.item.holdPress();
    }

    readonly property bool wallpaperSearching: pill.wallpaperOpen && ldWall.item !== null && ldWall.item.searching

    /**
     * Route the first printable keystroke over the open wallpaper strip into a
     * DuckDuckGo search seeded with that character. No-op unless the wallpaper
     * surface is open.
     */
    function wallpaperType(ch) {
        if (pill.wallpaperOpen && ldWall.item)
            ldWall.item.startSearch(ch);
    }

    /**
     * Slide the open power surface's keyboard focus by `dir` tiles; +1 is right
     * and -1 is left. No-op unless the power surface is open.
     */
    function powerMove(dir) {
        if (pill.powerOpen && ldPower.item)
            ldPower.item.move(dir);
    }

    /**
     * Enter pressed on the open power surface's focused tile: fires a safe tile
     * at once, latches a destructive tile's heat hold. Returns true when a tile
     * consumed the key. No-op (false) unless the power surface is open.
     */
    function powerPress() {
        return (pill.powerOpen && ldPower.item) ? ldPower.item.pressFocused() : false;
    }

    /**
     * Enter released on the open power surface: drains an unfinished destructive
     * hold so a key let go before the fill completes never confirms.
     */
    function powerRelease() {
        if (pill.powerOpen && ldPower.item)
            ldPower.item.releaseFocused();
    }

    /**
     * Slide the open clipboard's selection by `delta` rows. Returns true when
     * the clipboard surface consumed it.
     */
    function clipboardMove(delta) {
        if (!pill.clipboardOpen || !ldClip.item)
            return false;
        ldClip.item.move(delta);
        return true;
    }

    /** Return on the open clipboard: copy the selected entry and close. */
    function clipboardActivate() {
        if (!pill.clipboardOpen || !ldClip.item)
            return false;
        ldClip.item.activate();
        return true;
    }

    /**
     * Slide the open font picker's highlight by `dir`. Returns true when the
     * picker consumed it.
     */
    function fontpickerMove(dir) {
        if (!pill.fontpickerOpen || !ldFontpicker.item)
            return false;
        ldFontpicker.item.move(dir);
        return true;
    }

    /** Return on the open font picker: pick the highlighted family. */
    function fontpickerActivate() {
        if (!pill.fontpickerOpen || !ldFontpicker.item)
            return false;
        ldFontpicker.item.activate();
        return true;
    }

    function localsendMove(dir) {
        if (!pill.localsendOpen || !ldLSend.item)
            return false;
        ldLSend.item.move(dir);
        return true;
    }

    function localsendActivate() {
        if (!pill.localsendOpen || !ldLSend.item)
            return false;
        ldLSend.item.activate();
        return true;
    }

    function timerBack() {
        if (!pill.timerOpen || !ldTimer.item)
            return false;
        pill.requestClose();
        return true;
    }

    function timerActivate() {
        if (!pill.timerOpen || !ldTimer.item)
            return false;
        ldTimer.item.toggle();
        return true;
    }

    function timerReset() {
        if (!pill.timerOpen || !ldTimer.item)
            return false;
        ldTimer.item.reset();
        return true;
    }

    /**
     * Slide the open launcher's selection by `delta`. Returns true when the
     * launcher consumed it.
     */
    function launcherMove(delta) {
        if (!pill.launcherOpen || !ldLauncher.item)
            return false;
        ldLauncher.item.move(delta);
        return true;
    }

    /** Return on the open launcher: launch the selected entry. */
    function launcherActivate() {
        if (!pill.launcherOpen || !ldLauncher.item)
            return false;
        ldLauncher.item.activate();
        return true;
    }

    /**
     * Return on the open recorder: press its action bar (start / stop / open
     * the source chooser).
     */
    function recorderPress() {
        if (!pill.recorderOpen || !ldRecorder.item)
            return false;
        ldRecorder.item.press();
        return true;
    }

    /**
     * Slide the open workspaces hub's focus by `dir`. Returns true when the
     * hub consumed it.
     */
    function workspacesMove(dir) {
        if (!pill.workspacesOpen || !ldWorkspaces.item)
            return false;
        ldWorkspaces.item.move(dir);
        return true;
    }

    /**
     * Return on the open workspaces hub: open the focused row's surface or the
     * add-workspace form.
     */
    function workspacesActivate() {
        if (!pill.workspacesOpen || !ldWorkspaces.item)
            return false;
        ldWorkspaces.item.activate();
        return true;
    }

    /**
     * The recorder's inline source chooser (or its monitor sub-chooser) is
     * covering the action bar. Return/Backspace must drive the chooser, not the
     * bar or the audio faders.
     */
    readonly property bool recorderChooserOpen: pill.recorderOpen && ldRecorder.item !== null && ldRecorder.item.chooserOpen

    /**
     * Slide the open stash list's focus by `dir` (+1 down, -1 up), across the
     * stashed apps and the add-app bar. Returns true when consumed.
     */
    function stashMove(dir) {
        if (!pill.stashOpen || !ldStash.item)
            return false;
        ldStash.item.move(dir);
        return true;
    }

    /**
     * Return on the open stash list: remove the focused app, or open the add
     * picker when the add bar is focused. Returns true when consumed.
     */
    function stashActivate() {
        if (!pill.stashOpen || !ldStash.item)
            return false;
        ldStash.item.activate();
        return true;
    }

    /** Slide the open space-apps list's focus by `dir`. Returns true when consumed. */
    function spaceappsMove(dir) {
        if (!pill.spaceappsOpen || !ldSpaceapps.item)
            return false;
        ldSpaceapps.item.move(dir);
        return true;
    }

    /** Return on the open space-apps list: remove the focused app, or open the picker. */
    function spaceappsActivate() {
        if (!pill.spaceappsOpen || !ldSpaceapps.item)
            return false;
        ldSpaceapps.item.activate();
        return true;
    }

    /**
     * Move the open calendar's keyboard day by `dir` along `axis` ("h" rows
     * by one day, "v" by a week). Returns true when the calendar consumed it.
     */
    function calendarMove(axis, dir) {
        if (!pill.calendarOpen || !ldCalendar.item)
            return false;
        ldCalendar.item.kbMove(axis, dir);
        return true;
    }

    /** Return on the open calendar: select the keyboard-focused day. */
    function calendarActivate() {
        if (!pill.calendarOpen || !ldCalendar.item)
            return false;
        ldCalendar.item.kbActivate();
        return true;
    }

    /**
     * Slide the open link surface's row focus by `dir`, across the rows of the
     * active subview (connectivity rows, wifi networks, bt devices). Returns
     * true when the link surface consumed it.
     */
    function linkMove(dir) {
        if (!pill.linkOpen || !ldLink.item)
            return false;
        ldLink.item.kbMove(dir);
        return true;
    }

    /** Return on the open link surface: activate the focused row. */
    function linkActivate() {
        if (!pill.linkOpen || !ldLink.item)
            return false;
        ldLink.item.kbActivate();
        return true;
    }

    /**
     * Move the recorder's inline source chooser focus by `dir`: across the
     * Screen / Window tiles, or the monitor tiles in the sub-chooser. Returns
     * true when the chooser consumed it.
     */
    function recorderChooserMove(dir) {
        return (pill.recorderOpen && ldRecorder.item) ? ldRecorder.item.chooserMove(dir) : false;
    }

    /** Return on the recorder's inline source chooser: pick the focused tile. */
    function recorderChooserActivate() {
        return (pill.recorderOpen && ldRecorder.item) ? ldRecorder.item.chooserActivate() : false;
    }

    /**
     * Backspace on the recorder's inline source chooser: the monitor sub-
     * chooser returns to the sources, the sources close the chooser. Returns
     * true when a chooser was open and consumed it.
     */
    function recorderChooserBack() {
        return (pill.recorderOpen && ldRecorder.item) ? ldRecorder.item.chooserBack() : false;
    }

    /**
     * Move the standalone quick-record chooser's focus by `dir`: across the
     * Screen / Window tiles, or the monitor tiles in the sub-choice. Returns
     * true when the chooser consumed it.
     */
    function quickChooseMove(dir) {
        if (!pill.quickChoosing)
            return false;
        quickChooser.move(dir);
        return true;
    }

    /** Return on the quick-record chooser: pick the focused tile. */
    function quickChooseActivate() {
        if (!pill.quickChoosing)
            return false;
        quickChooser.activate();
        return true;
    }

    /**
     * Backspace on the quick-record chooser: the monitor sub-choice returns to
     * the sources, the sources cancel the chooser. Returns true when consumed.
     */
    function quickChooseBack() {
        if (!pill.quickChoosing)
            return false;
        quickChooser.back();
        return true;
    }

    /**
     * Hover-face keyboard focus: left/right walks the interactive targets of
     * the expanded pill (media bud, minimized tray, tray icons, clock); Enter
     * activates the focused target. The tray and the minimized row keep their
     * own per-icon focus while the ring sits on them.
     */
    property int faceFocus: -1

    readonly property var faceTargets: {
        var out = [];
        if (pill.hasMedia) out.push("media");
        if (minimized.count > 0) out.push("minimized");
        if (SystemTray.items.values.length > 0) out.push("tray");
        out.push("clock");
        return out;
    }
    readonly property int faceCount: faceTargets.length

    function faceMove(dir) {
        if (pill.surfaceOpen || pill.mode !== "hover" || faceCount < 2)
            return false;
        if (faceFocus < 0 || faceFocus >= faceCount)
            faceFocus = 0;
        var key = faceTargets[faceFocus];
        /**
         * While the ring sits on a per-icon widget, arrows walk its icons and
         * step out to the neighbouring face target at the edges.
         */
        if (key === "minimized") {
            if (minimized.focusIndex < 0)
                minimized.focusIndex = 0;
            if (dir < 0 && minimized.focusIndex === 0)
                faceFocus = (faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && minimized.focusIndex === minimized.count - 1)
                faceFocus = (faceFocus + 1) % faceCount;
            else
                minimized.moveFocus(dir);
            return true;
        }
        if (key === "tray") {
            var nItems = SystemTray.items.values.length;
            if (tray.focusIndex < 0)
                tray.focusIndex = 0;
            if (dir < 0 && tray.focusIndex === 0)
                faceFocus = (faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && tray.focusIndex === nItems - 1)
                faceFocus = (faceFocus + 1) % faceCount;
            else
                tray.moveFocus(dir);
            return true;
        }
        faceFocus = (faceFocus + dir + faceCount) % faceCount;
        var landed = faceTargets[faceFocus];
        if (landed === "minimized" && minimized.focusIndex < 0)
            minimized.focusIndex = 0;
        if (landed === "tray" && tray.focusIndex < 0)
            tray.focusIndex = 0;
        return true;
    }

    function faceActivate() {
        if (pill.surfaceOpen || pill.mode !== "hover")
            return false;
        var key = faceFocus >= 0 && faceFocus < faceCount ? faceTargets[faceFocus] : "clock";
        if (key === "media") {
            pill.requestSurface("media");
        } else if (key === "minimized") {
            if (minimized.focusIndex < 0)
                minimized.focusIndex = 0;
            minimized.activate();
        } else if (key === "tray") {
            if (tray.focusIndex < 0)
                tray.focusIndex = 0;
            tray.activate();
        } else {
            pill.openCalendarAt(null);
        }
        return true;
    }

    /**
     * Escape/Backspace on the hover face: unpin if held and collapse the pill
     * back to rest. Returns true when the face was showing and consumed it.
     */
    function faceBack() {
        if (pill.surfaceOpen || pill.mode !== "hover")
            return false;
        if (pill.pinned)
            pill.pinned = false;
        pill.hoverLatch = false;
        pill.faceFocus = -1;
        return true;
    }

    /**
     * Focus the open picker's search field, for a forward-slash keypress.
     * Returns true when a picker consumed it.
     */
    function focusSearch() {
        if (pill.keybindsOpen && ldKeybinds.item) {
            ldKeybinds.item.focusSearch();
            return true;
        }
        if (pill.fontpickerOpen && ldFontpicker.item) {
            ldFontpicker.item.focusSearch();
            return true;
        }
        if (pill.clipboardOpen && ldClip.item) {
            ldClip.item.focusField();
            return true;
        }
        if (pill.launcherOpen && ldLauncher.item) {
            ldLauncher.item.focusField();
            return true;
        }
        if (pill.wallpaperOpen && ldWall.item) {
            ldWall.item.focusSearch();
            return true;
        }
        return false;
    }

    /**
     * Composed menu navigation, shared by the arrow keys and (with the vim
     * flag on) h/j/k/l. Each returns true when an open surface consumed it,
     * which the key handlers in PillRoot read to accept the event. The pill
     * owns the routing so the per-monitor key handling stays a thin shell.
     */
    function navUp() {
        if (pill.keybindsOpen && !pill.keybindsListening) { pill.keybindsMove(-1); return true; }
        /** The recorder's chooser tiles are horizontal; don't step the faders behind it. */
        if (pill.recorderOpen && pill.recorderChooserOpen)
            return false;
        return pill.calendarMove("v", -1) || pill.linkMove(-1) || pill.mixerStep(1)
            || pill.recorderStep(5) || pill.clipboardMove(-1)
            || pill.fontpickerMove(-1) || pill.launcherMove(-1) || pill.localsendMove(-1)
            || pill.workspacesMove(-1) || pill.stashMove(-1) || pill.spaceappsMove(-1)
            || pill.settingsMove(-1)
            || (pill.timerOpen && pill.timerActivate());
    }
    function navDown() {
        if (pill.keybindsOpen && !pill.keybindsListening) { pill.keybindsMove(1); return true; }
        if (pill.recorderOpen && pill.recorderChooserOpen)
            return false;
        return pill.calendarMove("v", 1) || pill.linkMove(1) || pill.mixerStep(-1)
            || pill.recorderStep(-5) || pill.clipboardMove(1)
            || pill.fontpickerMove(1) || pill.launcherMove(1) || pill.localsendMove(1)
            || pill.workspacesMove(1) || pill.stashMove(1) || pill.spaceappsMove(1)
            || pill.settingsMove(1)
            || (pill.timerOpen && pill.timerActivate());
    }
    function navLeft() {
        if (pill.quickChoosing) return pill.quickChooseMove(-1);
        if (pill.recorderChooserOpen) return pill.recorderChooserMove(-1);
        if (pill.calendarOpen) return pill.calendarMove("h", -1);
        if (pill.mixerOpen) { pill.mixerFocusMove(-1); return true; }
        if (pill.wallpaperOpen) { pill.wallpaperMove(-1); return true; }
        if (pill.powerOpen) { pill.powerMove(-1); return true; }
        if (pill.recorderOpen) { pill.recorderStep(-5); return true; }
        if (pill.settingsLike) return pill.settingsAdjust(-1);
        if (pill.mode === "hover" && !pill.surfaceOpen) return pill.faceMove(-1);
        return false;
    }
    function navRight() {
        if (pill.quickChoosing) return pill.quickChooseMove(1);
        if (pill.recorderChooserOpen) return pill.recorderChooserMove(1);
        if (pill.calendarOpen) return pill.calendarMove("h", 1);
        if (pill.mixerOpen) { pill.mixerFocusMove(1); return true; }
        if (pill.wallpaperOpen) { pill.wallpaperMove(1); return true; }
        if (pill.powerOpen) { pill.powerMove(1); return true; }
        if (pill.recorderOpen) { pill.recorderStep(5); return true; }
        if (pill.settingsLike) return pill.settingsAdjust(1);
        if (pill.mode === "hover" && !pill.surfaceOpen) return pill.faceMove(1);
        return false;
    }

    /**
     * Vim `h` with no horizontal nav available: back out of the current menu,
     * mirroring the Backspace chain (quick-record cancel, recorder chooser
     * step-back, link subview pop, hover-face collapse, then surface back).
     */
    function vimBack() {
        if (pill.quickChoosing) {
            pill.quickChooseBack();
        } else if (!pill.recorderChooserBack() && !pill.linkBack() && !pill.faceBack()) {
            pill.surfaceBack();
        }
    }

    /**
     * Vim `l` with no horizontal nav available: enter the current menu,
     * mirroring the Return chain (activate the focused item of the open
     * surface, or the hover face when resting).
     */
    function vimEnter() {
        if (pill.quickChoosing) {
            pill.quickChooseActivate();
        } else if (pill.wallpaperOpen) {
            pill.wallpaperActivate();
        } else if (pill.powerOpen) {
            pill.powerPress();
        } else if (pill.recorderChooserOpen) {
            pill.recorderChooserActivate();
        } else if (pill.recorderOpen) {
            pill.recorderPress();
        } else if (pill.calendarOpen) {
            pill.calendarActivate();
        } else if (pill.linkOpen) {
            pill.linkActivate();
        } else if (pill.clipboardOpen) {
            pill.clipboardActivate();
        } else if (pill.fontpickerOpen) {
            pill.fontpickerActivate();
        } else if (pill.localsendOpen) {
            pill.localsendActivate();
        } else if (pill.timerOpen) {
            pill.timerActivate();
        } else if (pill.workspacesOpen) {
            pill.workspacesActivate();
        } else if (pill.stashOpen) {
            pill.stashActivate();
        } else if (pill.spaceappsOpen) {
            pill.spaceappsActivate();
        } else if (pill.keybindsOpen && !pill.keybindsListening) {
            pill.keybindsActivate();
        } else if (pill.settingsLike) {
            pill.settingsActivate();
        } else if (pill.mode === "hover" && !pill.surfaceOpen) {
            pill.faceActivate();
        }
    }

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
         * Keep the 60fps cava capture only while the bars can actually render:
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
            calendarStyle.hoveredIndex = -1;
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
        pill._surfaceLoaders = {
            mixer: ldMixer, calendar: ldCalendar, launcher: ldLauncher,
            clipboard: ldClip, wallpaper: ldWall, power: ldPower,
            media: ldMedia, link: ldLink, battery: ldBattery,
            settings: ldSettings, keybinds: ldKeybinds, workspaces: ldWorkspaces,
            stash: ldStash, spaceapps: ldSpaceapps, recorder: ldRecorder,
            sysmon: ldSysmon, appearance: ldAppearance, updates: ldUpdates,
            display: ldDisplay, input: ldInput, look: ldLook,
            idlelock: ldIdlelock, animation: ldAnimation, fontpicker: ldFontpicker,
            localsend: ldLSend, timer: ldTimer
        };
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
        return calendarStyle.mapToItem(pill, calendarStyle.ameAnchor.x, calendarStyle.ameAnchor.y);
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
                 * (hover.clockHandoff), while the hover clock still sits
                 * exactly on this spot at this size — the swap is invisible
                 * and the growing clock reads as one clock, never a ghost.
                 */
                opacity: 1 - hover.clockHandoff
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

    Item {
        id: hover
        anchors.fill: parent

        readonly property bool live: pill.mode === "hover"

        /**
         * How far the pill has grown along the rest→hover hop, from the two
         * constant heights. The clock rides this instead of contentMorph — which
         * is 1 the instant hover mode begins and would pop the clock — so the
         * flight tracks the pill's actual growth. Only the pill's own geometry
         * is read, so it behaves identically on any monitor, at any scale, in
         * any notch style.
         */
        readonly property real clockHop: {
            const den = Math.max(1, pill.hoverH - pill.restH);
            return Math.max(0, Math.min(1, (pill.height - pill.restH) / den));
        }

        /**
         * The clock grows out of the rest clock's spot and shrinks back into
         * it: one continuous scale+slide driven by clockMorph. The morph leads
         * the pill's hop slightly (1.08x) so the clock lands just before the
         * pill finishes growing, and a soft out-back settle gives a subtle,
         * barely-there overshoot as it arrives. The rest-to-hover handoff is a
         * separate quick crossfade (clockHandoff) in the first moments, while
         * the hover clock still sits exactly on the rest clock at the same
         * size — so the swap is invisible and the growth reads as one clock.
         */
        readonly property real clockProgress: Math.max(0, Math.min(1, clockHop * 1.08))
        readonly property real clockMorph: {
            /** Subtle overshoot: peaks ~2.5% past 1, settles. */
            const c1 = 0.8;
            const c3 = c1 + 1;
            const x = clockProgress - 1;
            return 1 + c3 * x * x * x + c1 * x * x;
        }
        /**
         * Near-instant handoff tied to clockMorph: the hover clock is pixel-
         * identical to the rest clock at morph=0, so the swap completes while
         * the two are still coincident (the out-back front-loads, so a wider
         * window would crossfade a clock already in motion).
         */
        readonly property real clockHandoff: { var t = Math.max(0, Math.min(1, clockMorph / 0.08)); return t * t * (3 - 2 * t); }

        /**
         * The media bud, tray and calendar strip render at full strength the
         * moment hover mode begins (contentMorph is 1 in hover); the clock is
         * the one piece that moves, so it alone animates on clockHop above.
         */
        readonly property real mediaMorph: { var t = Math.max(0, Math.min(1, (pill.contentMorph - 0.30) / 0.70)); var ease = t * t * (3 - 2 * t); return ease; }
        readonly property real calendarMorph: { var t = Math.max(0, Math.min(1, (pill.contentMorph - 0.72) / 0.28)); return t * t * (3 - 2 * t); }
        readonly property real trayMorph: { var t = Math.max(0, Math.min(1, (pill.contentMorph - 0.64) / 0.36)); return 1 - Math.pow(1 - t, 2.2); }

        /**
         * The rest clock's centre, captured once the moment hover mode begins
         * (while the pill is still at rest geometry) so the flight is a clean
         * straight line instead of chasing a live mapToItem mid-morph — the old
         * binding re-mapped an invisible hover target every frame and jumped.
         * Measured in hoverClock's frame — the same frame the flight Translate
         * lives in — so start and end are directly comparable.
         */
        property real clockStartX: 0
        property real clockStartY: 0

        function captureClockStart() {
            const p = restTime.mapToItem(hoverClock, restTime.width / 2, restTime.height / 2);
            clockStartX = p.x;
            clockStartY = p.y;
        }

        /**
         * Fires on every rest-to-hover hop. The pill is still at rest geometry
         * here (the height Behavior starts a tick later), so the capture is
         * exact. The onCompleted guard covers the one path where live is true
         * from birth — a monitor hotplug while its pill is peeked — so a
         * collapse then still flies from the rest clock's real position.
         */
        onLiveChanged: if (live) captureClockStart()
        Component.onCompleted: if (live) captureClockStart()

        /**
         * The hover clock's settled centre in hoverClock's frame: the clock
         * column's centre, offset by the same 20*s the clock is anchored with
         * (the clock is the column's first row, so its vertical centre is half
         * its own height down the column).
         */
        readonly property real clockEndX: hoverClock.width / 2 + 20 * pill.s
        readonly property real clockEndY: hoverTime.height / 2

        opacity: live ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "hover" ? Motion.fast : 40
                easing.type: Motion.easeStandard
            }
        }

        Row {
            id: hoverRow

            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -20 * pill.s

            spacing: 20 * pill.s

            Row {
                id: statusRow

                anchors.verticalCenter: parent.verticalCenter

                spacing: 12 * pill.s

                opacity: hover.mediaMorph

                transform: Translate {
                    x: 56 * pill.s * (1 - hover.mediaMorph)
                }

                Loader {
                    id: hoverMedia

                    anchors.verticalCenter: parent.verticalCenter

                    x: -72 * pill.s * (1 - hover.mediaMorph)

                    opacity: hover.mediaMorph
                    scale: 0.78 + 0.22 * hover.mediaMorph

                    active: pill.hasMedia
                    visible: active

                    /**
                     * Collapse to 0×0 when nothing plays: an invisible-but-sized
                     * loader still counts toward hoverRow's implicitWidth, which
                     * would leave a gap inside the expanded pill.
                     */
                    width: pill.hasMedia ? pill.mediaW : 0
                    height: pill.hasMedia ? pill.mediaH : 0

                    sourceComponent: Media {
                        id: bud

                        s: pill.s
                        open: true
                        morphCloseness: hover.mediaMorph
                        shown: pill.mode === "hover"

                        onRequestClose: {
                            hoverMedia.active = false
                        }
                    }
                }

                /** Keyboard ring around the focused hover-face media bud. */
                Rectangle {
                    anchors.fill: hoverMedia
                    anchors.margins: -3 * pill.s
                    visible: pill.faceFocus >= 0 && pill.faceFocus < pill.faceCount
                        && pill.faceTargets[pill.faceFocus] === "media"
                    radius: 14 * pill.s
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(Theme.vermLit, 0.65)
                }

                MinimizedTray {
                    id: minimized

                    anchors.verticalCenter: parent.verticalCenter

                    s: pill.s
                    screenName: pill.screenName

                    enabled: hover.live
                    visible: count > 0

                    opacity: hover.trayMorph
                    scale: 0.9 + 0.1 * hover.trayMorph

                    faceActive: pill.faceFocus >= 0 && pill.faceFocus < pill.faceCount
                        && pill.faceTargets[pill.faceFocus] === "minimized"
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: minimized.count > 0 && SystemTray.items.values.length > 0
                    width: 1
                    height: 14 * pill.s
                    color: Theme.hair
                    opacity: 0.7 * hover.trayMorph
                }

                Tray {
                    id: tray
                    anchors.verticalCenter: parent.verticalCenter

                    s: pill.s
                    barWindow: pill.barWindow

                    enabled: hover.live

                    opacity: hover.trayMorph
                    scale: 0.9 + 0.1 * hover.trayMorph

                    faceActive: pill.faceFocus >= 0 && pill.faceFocus < pill.faceCount
                        && pill.faceTargets[pill.faceFocus] === "tray"
                }
            }

            Item {
                id: clockContainer

                anchors.verticalCenter: parent.verticalCenter

                implicitWidth: hoverClock.implicitWidth
                implicitHeight: hoverClock.implicitHeight

                Column {
                    id: hoverClock

                    anchors.centerIn: parent

                    spacing: 8 * pill.s

                    Item {
                        /**
                         * The flight lives on this wrapper: a Translate declared
                         * on the scaled Text would itself be scaled (the
                         * transform list applies in the item's local frame), so
                         * the clock would sit short of the rest clock at the
                         * start of the hop. Here the offset is in the column's
                         * unscaled frame, and the Text below scales around its
                         * own centre — position and size stay independent.
                         */
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 20 * pill.s

                        implicitWidth: hoverTime.implicitWidth
                        implicitHeight: hoverTime.implicitHeight

                        transform: Translate {
                            x: (hover.clockStartX - hover.clockEndX) * (1 - hover.clockMorph)
                            y: (hover.clockStartY - hover.clockEndY) * (1 - hover.clockMorph)
                        }

                        Text {
                            id: hoverTime

                            anchors.centerIn: parent

                            text: clock.hhmm

                            color: Theme.cream

                            font.family: Theme.font
                            font.pixelSize: 28 * pill.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }

                            opacity: hover.clockHandoff
                            /** 18px rest clock scaled up to 28px, tracking the pill's hop. */
                            scale: (18 / 28) + (1 - 18 / 28) * hover.clockMorph
                        }
                    }

                    CalendarStyle {
                        id: calendarStyle

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 20 * pill.s

                        width: 220 * pill.s
                        height: 48 * pill.s

                        pillRef: pill
                        ameEnabled: true

                        onOpenCalendar: (date) => pill.openCalendarAt(date)

                        scale: pill.s
                        opacity: hover.calendarMorph
                    }
                }

                MouseArea {
                    anchors.centerIn: parent

                    width: hoverClock.implicitWidth + 22 * pill.s
                    height: hoverClock.implicitHeight + 10 * pill.s

                    /**
                     * While a day cell is hovered the strip's delegates own the
                     * click (they open the calendar focused on that day);
                     * anywhere else opens it on the current date.
                     */
                    enabled: hover.live && !calendarStyle.hovered

                    cursorShape: Qt.PointingHandCursor

                    onClicked: pill.openCalendarAt(null)
                }

                /** Keyboard ring around the focused hover-face clock target. */
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4 * pill.s
                    visible: pill.faceFocus >= 0 && pill.faceFocus < pill.faceCount
                        && pill.faceTargets[pill.faceFocus] === "clock"
                    radius: 16 * pill.s
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(Theme.vermLit, 0.65)
                }
            }
        }
    }

    /**
     * Morphing surfaces, one PillSurfaceLoader each. Each shares the lazy
     * Loader pattern (active=false, anchors.fill) while keeping s/open/
     * morphCloseness inline so bindings are live from component creation.
     */

    PillSurfaceLoader {
        id: ldMixer
        sourceComponent: Mixer { s: pill.s; open: pill.mixerOpen; morphCloseness: pill.morphCloseness }
    }

    PillSurfaceLoader {
        id: ldCalendar
        sourceComponent: Calendar { s: pill.s; open: pill.calendarOpen; morphCloseness: pill.morphCloseness; targetDate: pill.calendarFocusDate }
    }

    PillSurfaceLoader {
        id: ldLauncher
        sourceComponent: Launcher { s: pill.s; open: pill.launcherOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldClip
        sourceComponent: Clipboard { s: pill.s; open: pill.clipboardOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldWall
        sourceComponent: Wallpaper { s: pill.s; open: pill.wallpaperOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldPower
        sourceComponent: Power { s: pill.s; open: pill.powerOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldMedia
        sourceComponent: Media { s: pill.s; open: pill.mediaOpen; morphCloseness: pill.morphCloseness; shown: pill.mediaOpen; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldLink
        sourceComponent: Link {
            s: pill.s; open: pill.linkOpen; morphCloseness: pill.morphCloseness
            initialView: pill.linkInitialView
            sendStatus: pill.localsendActivity
            onRequestClose: pill.requestClose()
            onOpenSend: pill.requestSurface("localsend")
        }
    }

    onLinkOpenChanged: if (!linkOpen) linkInitialView = "main"

    PillSurfaceLoader {
        id: ldBattery
        sourceComponent: BatterySurface { s: pill.s; open: pill.batteryOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldSettings
        sourceComponent: Settings { s: pill.s; open: pill.settingsOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldKeybinds
        sourceComponent: Keybinds { s: pill.s; open: pill.keybindsOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldWorkspaces
        sourceComponent: WorkspacesSurface { s: pill.s; open: pill.workspacesOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldStash
        sourceComponent: Stash { s: pill.s; open: pill.stashOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldSpaceapps
        sourceComponent: SpaceApps { s: pill.s; open: pill.spaceappsOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldRecorder
        sourceComponent: Recorder { s: pill.s; open: pill.recorderOpen; morphCloseness: pill.morphCloseness; screenName: pill.screenName; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldSysmon
        sourceComponent: SysmonSurface { s: pill.s; open: pill.sysmonOpen; morphCloseness: pill.morphCloseness; onRequestClose: pill.requestClose() }
    }

    PillSurfaceLoader {
        id: ldAppearance
        sourceComponent: Appearance { s: pill.s; open: pill.appearanceOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldUpdates
        sourceComponent: Updates { s: pill.s; open: pill.updatesOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldDisplay
        sourceComponent: Display { s: pill.s; open: pill.displayOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldInput
        sourceComponent: Input { s: pill.s; open: pill.inputOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldLook
        sourceComponent: Look { s: pill.s; open: pill.lookOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldIdlelock
        sourceComponent: IdleLock { s: pill.s; open: pill.idlelockOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldAnimation
        sourceComponent: AnimationSurface { s: pill.s; open: pill.animationOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldFontpicker
        sourceComponent: FontPicker { s: pill.s; open: pill.fontpickerOpen; morphCloseness: pill.morphCloseness; onRequestSurface: (name) => pill.requestSurface(name) }
    }

    PillSurfaceLoader {
        id: ldLSend
        sourceComponent: Localsend { s: pill.s; open: pill.localsendOpen; morphCloseness: pill.morphCloseness }
    }

    PillSurfaceLoader {
        id: ldTimer
        sourceComponent: Pomodoro { s: pill.s; open: pill.timerOpen; morphCloseness: pill.morphCloseness }
    }
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

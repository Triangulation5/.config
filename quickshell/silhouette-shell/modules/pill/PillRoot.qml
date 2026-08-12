//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

import qs.services
import qs.modules.pill

/**
 * Washi pill top shell. Each monitor carries two layer-shell windows:
 *
 *  - `reserve` is a zero-content strip that claims an exclusive zone the
 *    height of the rest pill, so tiled windows sit below the pill even while
 *    it is expanded or a surface is open — except under auto-hide, where the
 *    band stays collapsed (zone 0) so a retracted pill, transient hover
 *    reveal, or open surface floats over windows without shifting them.
 *  - `overlay` is a full-screen transparent Overlay layer hosting the single
 *    morphing pill anchored at top-centre. The pill never moves windows and is
 *    never re-parented; it just grows in place, so every surface grows out of
 *    the rest pill instead of popping up as a separate panel.
 *
 * Input is routed by the window mask. While the pill is collapsed the mask is
 * the pill rect only, so the rest of the screen clicks through to windows.
 * While the pill is expanded (hovered/pinned) or a surface is open the mask is
 * cleared so the whole layer catches clicks. A backdrop press dismisses, and
 * keyboard focus is taken on demand so Escape closes the open surface.
 */
ShellRoot {
    id: root

    property string openMon: ""
    property string openSurface: ""
    property string peekMon: ""

    /**
     * Per-monitor auto-hide reserve collapse (retracted or floating), bridged
     * from each overlay delegate to its reserve window so the reserved band
     * stays at zero while the pill hides or floats. Written by reassigning a
     * fresh object so the reserve's binding re-evaluates.
     */
    property var pillCollapsed: ({})
    function setPillCollapsed(mon, v) {
        var m = {};
        for (var k in root.pillCollapsed)
            m[k] = root.pillCollapsed[k];
        m[mon] = v;
        root.pillCollapsed = m;
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    Component.onCompleted: {
        refresh();
        Devices.restore();
        void GameMode.active;
    }

    /**
     * After an update relaunches the shell, raise a one-shot toast naming what
     * landed, so the apply ends in a confirmation instead of a silent restart. The
     * updater drops the marker just before it restarts; the short delay lets the
     * notification server own the bus before we post to it, and the marker is
     * removed as it is read so the toast only ever fires once.
     */
    Timer {
        interval: 2500
        running: true
        onTriggered: updatedToast.running = true
    }
    Process {
        id: updatedToast
        command: ["sh", "-c",
            "m=\"${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/updated\"; [ -f \"$m\" ] || exit 0; "
            + "b=$(cat \"$m\"); rm -f \"$m\"; "
            + "gdbus call --session --dest org.freedesktop.Notifications "
            + "--object-path /org/freedesktop/Notifications "
            + "--method org.freedesktop.Notifications.Notify "
            + "SilhouetteShell 0 '' 'SilhouetteShell updated' \"$b\" '[]' '{}' 5000 >/dev/null 2>&1"]
    }


    PanelWindow {
        id: inhibitWin
        visible: Flags.keepAwake
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "pill-inhibit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; left: true }
        IdleInhibitor { window: inhibitWin; enabled: Flags.keepAwake }
    }

    /**
     * The Wayland IdleInhibitor above only pauses the compositor's own idle
     * (DPMS); hypridle runs its own timer and never sees it, so the lock still
     * fired with keep-awake on. A logind idle inhibitor is the wire hypridle
     * does respect, so hold one for as long as the flag is set.
     */
    Process {
        running: Flags.keepAwake
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=josh",
                  "--why=keep awake", "--mode=block", "sleep", "infinity"]
    }

    /**
     * Only these raw events can change what the pill renders (per-monitor
     * active workspace, minimized toplevels, monitor hotplug). Everything
     * else (window drags, resizes, title spam) must not trigger the triple
     * model refresh, which costs three Hyprland IPC round-trips.
     */
    readonly property var refreshEvents: ({
        workspace: true, workspacev2: true,
        createworkspace: true, createworkspacev2: true,
        destroyworkspace: true, destroyworkspacev2: true,
        moveworkspace: true, moveworkspacev2: true,
        renameworkspace: true, activespecial: true,
        focusedmon: true, focusedmonv2: true,
        openwindow: true, closewindow: true,
        movewindow: true, movewindowv2: true,
        fullscreen: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.refreshEvents[event.name])
                root.refresh();
        }
    }

    /**
     * An empty monitor argument resolves to the focused monitor here, so the
     * keybind scripts skip their hyprctl+jq round trip and a surface open costs
     * one IPC call instead of three process spawns.
     */
    function toggleSurface(mon, surface) {
        if (!mon || mon.length === 0)
            mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (root.openMon === mon && root.openSurface === surface) {
            root.close();
            return;
        }
        root.openMon = mon;
        root.openSurface = surface;
    }

    function close() {
        root.openMon = "";
        root.openSurface = "";
    }

    function peek(mon) {
        root.peekMon = root.peekMon === mon ? "" : mon;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            readonly property real restHeight: 38 * s

            /** Trimming the reserved band below the pill's bottom lets windows climb, so App gap sets the pill-to-window air without touching the desktop gaps_out. */
            readonly property real reservedH: Math.max(0, restHeight + topGap - 12 * (1 - Flags.appGap) * s)

            readonly property real gameBarH: 34 * s

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Flags.gameMode ? gameBarH : (root.pillCollapsed[modelData.name] ? 0 : reservedH)
            aboveWindows: true

            anchors { top: true; left: true; right: true }
            implicitHeight: Flags.gameMode ? gameBarH : reservedH

            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0
            readonly property bool modal: pill.authPending ? false : (surfaceOpen || pill.held || pill.quickChoosing)

            /**
             * Auto-hide: with the flag on, the rest pill retracts off the top
             * edge and the band mask collapses to a thin strip, so a pointer
             * touch anywhere along the top edge wakes it. Anything that needs
             * the pill (an open surface, pin, peek, OSD/toast, special
             * workspace) keeps it down.
             */
            readonly property bool autoRetracted: Flags.autoHide && !monFullscreen
                && pill.specialView === "" && pill.mode === "rest"

            /**
             * True while auto-hide keeps the reserved band collapsed: the pill
             * is either retracted off-screen or floating over windows in a
             * transient hover, an open surface, OSD, toast or quick-record. The
             * band is only reclaimed once the pill is held (pin/peek) or a
             * special workspace forces the pill on, so windows never shift
             * from a glance at the bar or an auto-hidden surface.
             */
            readonly property bool autoCollapsed: Flags.autoHide && !monFullscreen
                && pill.specialView === "" && !pill.held

            /** The wake strip and the growing hover band, shared by the mask. */
            readonly property real autoStripH: 5 * s
            readonly property real autoBandH: Math.max(autoStripH, pill.y + pill.height + autoStripH)

            onAutoCollapsedChanged: root.setPillCollapsed(modelData.name, autoCollapsed)
            Component.onCompleted: root.setPillCollapsed(modelData.name, autoCollapsed)

            /**
             * True while this monitor's active workspace holds a real
             * fullscreen window. The pill then retracts off the top edge and
             * the whole layer becomes click-through so fullscreen content owns
             * the screen. Maximize is suppressed globally, so only true
             * fullscreen ever flips this.
             */
            readonly property bool monFullscreen: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++) {
                    if (mons[i].name === modelData.name) {
                        var ws = mons[i].activeWorkspace;
                        var o = ws ? ws.lastIpcObject : null;
                        return o ? !!o.hasfullscreen : false;
                    }
                }
                return false;
            }

            onMonFullscreenChanged: if (monFullscreen) {
                if (root.openMon === modelData.name) root.close();
                if (root.peekMon === modelData.name) root.peekMon = "";
                pill.pinned = false;
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: ((surfaceOpen || pill.quickChoosing) && !pill.authPending) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "pill"

            anchors { top: true; left: true; right: true; bottom: true }

            mask: monFullscreen ? hiddenRegion : (modal ? fullRegion : (Flags.autoHide ? autoRegion : pillRegion))
            Region { id: hiddenRegion }
            Region {
                id: autoRegion
                width: overlay.width
                height: overlay.autoBandH
            }
            Region {
                id: pillRegion
                readonly property real baseW: Math.max(pill.width, pill.targetW)
                x: pill.x + (pill.width - baseW) / 2
                y: pill.y
                width: baseW + pill.inputPadRight
                height: Math.max(pill.height, pill.targetH)
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                onPressed: (mouse) => {
                    if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else if (overlay.surfaceOpen) {
                        var inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width
                            && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                        if (!inside)
                            root.close();
                        else if (mouse.y <= pillRegion.y + 40 * pill.s)
                            pill.surfaceBack();
                    } else {
                        pill.pinned = false;
                        root.peekMon = "";
                    }
                }
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                /**
                 * Keyboard ownership follows the pointer. Hovering the pill is
                 * already an OnDemand keyboard grab (Hyprland focuses on-demand
                 * layers under the cursor), so with the flag below the shell
                 * actually uses those keys for the hover face instead of
                 * dropping them. A surface or the quick-record chooser takes
                 * the keys exclusively.
                 */
                focus: overlay.surfaceOpen || pill.quickChoosing
                    || (pill.mode === "hover" && pill.hovered)

                HoverHandler {
                    onHoveredChanged: pill.hovered = hovered
                }
                Keys.onEscapePressed: {
                    if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else {
                        root.close();
                    }
                }
                /**
                 * Arrow keys: with the vim flag on they go dead in the menus and
                 * h/j/k/l take over (below). Inside a focused search field they
                 * still work — that is insert mode.
                 */
                Keys.onUpPressed: (e) => {
                    if (Flags.vimKeys) return;
                    e.accepted = pill.navUp();
                }
                Keys.onDownPressed: (e) => {
                    if (Flags.vimKeys) return;
                    e.accepted = pill.navDown();
                }
                Keys.onLeftPressed: (e) => {
                    if (Flags.vimKeys) return;
                    e.accepted = pill.navLeft();
                }
                Keys.onRightPressed: (e) => {
                    if (Flags.vimKeys) return;
                    e.accepted = pill.navRight();
                }

                /**
                 * Return/Enter/Space: the wallpaper strip applies its focused
                 * thumb on every press; the power surface fires a safe tile on
                 * the first press and, for a destructive tile, holds the heat
                 * fill across autorepeat presses (drained on release). Autorepeat
                 * is swallowed for everything else so a held key never re-fires.
                 */
                Keys.onPressed: (e) => {
                    /**
                     * Forward-slash focuses the open picker's search field (the
                     * keybind search, font picker, clipboard, launcher or
                     * wallpaper strip). A focused field consumes it as text, so
                     * this only fires while browsing the list.
                     */
                    if (e.key === Qt.Key_Slash && pill.focusSearch()) {
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_R && !e.isAutoRepeat && pill.timerOpen) {
                        pill.timerReset();
                        e.accepted = true;
                        return;
                    }
                    /**
                     * Vim navigation: with the flag on, h/j/k/l drive the same
                     * menu moves as the arrows (which are disabled above). h/l
                     * select and deselect — they flip toggles and cycle
                     * segments in the settings rows. A focused search field
                     * still consumes them as text, so this only fires while
                     * browsing. The wallpaper strip is covered too: h/l page
                     * it instead of seeding a search.
                     */
                    if (Flags.vimKeys && e.text.length === 1) {
                        var c = e.text;
                        if (c === "h") {
                            /**
                             * Vim `h`: move left where a menu has horizontal
                             * navigation (calendar days, mixer faders, settings
                             * values). In a vertical list (link rows, launcher,
                             * clipboard, settings index) nothing consumes it, so
                             * fall back to backing out — the same chain as
                             * Backspace. Always accepted so the key never leaks
                             * into a search.
                             */
                            if (!pill.navLeft() && !e.isAutoRepeat)
                                pill.vimBack();
                            e.accepted = true;
                            return;
                        }
                        if (c === "j") { e.accepted = pill.navDown(); return; }
                        if (c === "k") { e.accepted = pill.navUp(); return; }
                        if (c === "l") {
                            /**
                             * Vim `l`: move right where a menu has horizontal
                             * navigation, otherwise enter — the same chain as
                             * Return/Enter (drill into a link subview, activate
                             * the focused row). Autorepeat is swallowed so a
                             * held key never re-fires an activate. Always
                             * accepted.
                             */
                            if (!pill.navRight() && !e.isAutoRepeat)
                                pill.vimEnter();
                            e.accepted = true;
                            return;
                        }
                    }
                    /**
                     * Backspace is the shell-wide "back": it cancels a quick-
                     * record chooser, steps the recorder's inline chooser back,
                     * pops a link subview, collapses the hover face, then runs
                     * the surface's own back navigation (a settings sub-surface
                     * returns to its index, a form closes, anything else
                     * dismisses). Handled in the general onPressed because this
                     * build's Keys exposes no named onBackspacePressed handler.
                     * A focused search field consumes its own Backspace, so this
                     * only fires while browsing.
                     */
                    if (e.key === Qt.Key_Backspace) {
                        if (pill.quickChoosing) {
                            pill.quickChooseBack();
                        } else if (!pill.recorderChooserBack() && !pill.linkBack() && !pill.faceBack() && !pill.keybindsBack() && !pill.timerBack()) {
                            pill.surfaceBack();
                        }
                        e.accepted = true;
                        return;
                    }
                    if (pill.wallpaperOpen && !pill.wallpaperSearching
                        && e.text.length === 1 && e.text > " ") {
                        pill.wallpaperType(e.text);
                        e.accepted = true;
                        return;
                    }
                    if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space)
                        return;
                    /**
                     * Order matters only where branches overlap: the quick-
                     * record chooser is not a surface so it must be claimed
                     * first; the recorder's inline source chooser must be
                     * claimed before the plain recorder press; the font picker
                     * before the settingsLike branch (whose rows are empty
                     * there and would swallow the key).
                     */
                    if (pill.quickChoosing) {
                        if (!e.isAutoRepeat) pill.quickChooseActivate();
                        e.accepted = true;
                    } else if (pill.wallpaperOpen) {
                        if (e.isAutoRepeat) {
                            if (!pill._wpHoldStarted) {
                                pill._wpHoldStarted = true;
                                pill.wallpaperHoldPress();
                            }
                            e.accepted = true;
                        } else {
                            pill.wallpaperActivate();
                            e.accepted = true;
                        }
                    } else if (pill.powerOpen) {
                        if (!e.isAutoRepeat) pill.powerPress();
                        e.accepted = true;
                    } else if (pill.recorderChooserOpen) {
                        if (!e.isAutoRepeat) pill.recorderChooserActivate();
                        e.accepted = true;
                    } else if (pill.recorderOpen) {
                        if (!e.isAutoRepeat) pill.recorderPress();
                        e.accepted = true;
                    } else if (pill.calendarOpen) {
                        if (!e.isAutoRepeat) pill.calendarActivate();
                        e.accepted = true;
                    } else if (pill.linkOpen) {
                        if (!e.isAutoRepeat) pill.linkActivate();
                        e.accepted = true;
                    } else if (pill.clipboardOpen) {
                        if (!e.isAutoRepeat) pill.clipboardActivate();
                        e.accepted = true;
                    } else if (pill.fontpickerOpen) {
                        if (!e.isAutoRepeat) pill.fontpickerActivate();
                        e.accepted = true;
                    } else if (pill.launcherOpen) {
                        if (!e.isAutoRepeat) pill.launcherActivate();
                        e.accepted = true;
                    } else if (pill.workspacesOpen) {
                        if (!e.isAutoRepeat) pill.workspacesActivate();
                        e.accepted = true;
                    } else if (pill.stashOpen) {
                        if (!e.isAutoRepeat) pill.stashActivate();
                        e.accepted = true;
                    } else if (pill.spaceappsOpen) {
                        if (!e.isAutoRepeat) pill.spaceappsActivate();
                        e.accepted = true;
                    } else if (pill.keybindsOpen && !pill.keybindsListening) {
                        if (!e.isAutoRepeat) pill.keybindsActivate();
                        e.accepted = true;
                    } else if (pill.timerOpen) {
                        if (!e.isAutoRepeat) pill.timerActivate();
                        e.accepted = true;
                    } else if (pill.settingsLike) {
                        if (!e.isAutoRepeat) pill.settingsActivate();
                        e.accepted = true;
                    } else if (pill.mode === "hover" && !pill.surfaceOpen) {
                        if (!e.isAutoRepeat) pill.faceActivate();
                        e.accepted = true;
                    }
                }

                /**
                 * Backspace travels through the general onPressed handler above
                 * (this build has no named Keys.onBackspacePressed).
                 */
                Keys.onReleased: (e) => {
                    if (e.isAutoRepeat)
                        return;
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                        && pill.powerOpen) {
                        pill.powerRelease();
                        e.accepted = true;
                    }
                }

                Pill {
                    id: pill
                    anchors.top: parent.top
                    anchors.topMargin: pill.mode === "game" ? 0 : overlay.topGap
                    anchors.horizontalCenter: parent.horizontalCenter

                    Behavior on anchors.topMargin {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                    s: overlay.s
                    screenName: overlay.modelData.name
                    barWindow: overlay
                    surface: overlay.surface
                    forcePinned: root.peekMon === overlay.modelData.name

                    opacity: (overlay.monFullscreen || overlay.autoRetracted) ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Math.round(Motion.morph * 0.7)
                            easing.type: Easing.OutCubic
                        }
                    }
                    transform: Translate {
                        y: (overlay.monFullscreen || overlay.autoRetracted) ? -(pill.height + overlay.topGap) : 0
                        Behavior on y {
                            NumberAnimation {
                                duration: Motion.morph
                                easing.type: Motion.easeMorph
                                easing.bezierCurve: Motion.morphCurve
                            }
                        }
                    }

                    onRequestSurface: (name) => root.toggleSurface(overlay.modelData.name, name)
                    onRequestClose: root.close()
                }
            }

            onSurfaceOpenChanged: if (surfaceOpen) focusScope.forceActiveFocus()

            Connections {
                target: pill
                function onQuickChoosingChanged() {
                    if (pill.quickChoosing)
                        focusScope.forceActiveFocus();
                }
                function onModeChanged() {
                    if (pill.mode === "hover" && pill.hovered && !pill.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
                function onWallpaperSearchingChanged() {
                    if (!pill.wallpaperSearching && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
                function onKeybindsListeningChanged() {
                    if (!pill.keybindsListening && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
            }
        }
    }

    /**
     * IPC: the pill owns its own surface routing. `qs ipc call pill ...` lands
     * here; an empty monitor argument resolves to the focused monitor inside
     * toggleSurface, so the keybind scripts skip their hyprctl+jq round trip.
     */
    IpcHandler {
        target: "pill"
        function mixer(mon: string): void { root.toggleSurface(mon, "mixer"); }
        function calendar(mon: string): void { root.toggleSurface(mon, "calendar"); }
        function launcher(mon: string): void { root.toggleSurface(mon, "launcher"); }
        function power(mon: string): void { root.toggleSurface(mon, "power"); }
        function link(mon: string): void { root.toggleSurface(mon, "link"); }
        function battery(mon: string): void { root.toggleSurface(mon, "battery"); }
        function settings(mon: string): void { root.toggleSurface(mon, "settings"); }
        function keybinds(mon: string): void { root.toggleSurface(mon, "keybinds"); }
        function recorder(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function screenrec(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function record(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function quickRecord(mon: string): void {
            if (ScreenRec.recording) {
                ScreenRec.stop();
            } else if (ScreenRec.counting) {
                ScreenRec.cancel();
            } else if (ScreenRec.quickChoosing) {
                ScreenRec.quickChoosing = false;
                ScreenRec.quickScreenChoosing = false;
            } else {
                ScreenRec.quickMon = mon;
                ScreenRec.quickScreenChoosing = false;
                ScreenRec.quickChoosing = true;
            }
        }
        function gameMode(_mon: string): void { Flags.gameMode = !Flags.gameMode; }
        function sysmon(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function system(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function clipboard(mon: string): void { root.toggleSurface(mon, "clipboard"); }
        function wallpaper(mon: string): void { root.toggleSurface(mon, "wallpaper"); }
        function localsend(mon: string): void { root.toggleSurface(mon, "localsend"); }
        function timer(mon: string): void { root.toggleSurface(mon, "timer"); }
        function media(mon: string): void {
            if (Players.playing)
                root.toggleSurface(mon, "media");
        }
        function peek(mon: string): void { root.peek(mon); }
        function hide(): void { root.close(); }
        function page(mon: string, name: string): void { root.toggleSurface(mon, name); }
        function mute(mon: string): void {
            var src = Pipewire.defaultAudioSource;
            if (src && src.audio) {
                src.audio.muted = !src.audio.muted;
            }
        }
        function minimizeWindow(addr: string): void {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + addr + '" })');
        }
        function restoreWindow(arg: string): void {
            var p = arg.split("|");
            if (p.length < 2 || p[0].length === 0)
                return;
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + p[1] + ', window = "address:' + p[0] + '" })');
        }
    }
}

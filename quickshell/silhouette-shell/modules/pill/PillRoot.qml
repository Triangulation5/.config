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
     * Eagerly instantiate the Polkit service (and with it, the agent daemon)
     * at startup. The service is a lazy singleton: without this reference
     * nothing loads it until the first prompt IPC arrives — but only the
     * agent can send that, so it would never start and pkexec would report
     * "No authentication agent found".
     */
    readonly property var polkitBootstrap: Polkit

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
     *
     * Deferred a tick so the IPC dispatch returns before any surface loader
     * activates: opening a heavy surface never blocks the call that triggered
     * it. The open/close check runs inside the deferred body, so rapid
     * toggles still alternate correctly. Closing (Escape/backdrop/hide) stays
     * immediate.
     */
    function toggleSurface(mon, surface) {
        Qt.callLater(function() {
            if (!mon || mon.length === 0)
                mon = Hyprland.focusedMonitor
                    ? Hyprland.focusedMonitor.name
                    : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
            if (root.openMon === mon && root.openSurface === surface) {
                root.close();
                return;
            }
            root.openMon = mon;
            root.openSurface = surface;
        });
    }

    /**
     * A live polkit prompt is non-dismissible: the only way out is an explicit
     * Cancel / Authenticate on the prompt, or the agent resolving the
     * conversation (its `clear` IPC drops Polkit.pending first). Guarding here
     * makes Escape, backdrop presses, the hide IPC and every surfaceBack path
     * no-op while the prompt is pending, so the user cannot click or key their
     * way around entering the password.
     */
    function close() {
        if (root.openSurface === "polkit" && Polkit.pending)
            return;
        /** A live call surface is non-dismissible, exactly like the polkit prompt: the only way out is its red hang-up ✕. */
        if (root.openSurface === "call" && Calls.onCall)
            return;
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

    /**
     * The per-monitor overlay: input mask, backdrop press, keyboard focus
     * scope, and the morphing Pill itself. Lives in PillOverlay.qml so this
     * file stays a slim host — surface routing state and IPC live here, the
     * window mechanics live there.
     */
    PillOverlay {
        host: root
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
        function timer(mon: string): void { root.toggleSurface(mon, "timer"); }
        function media(mon: string): void {
            if (Players.has)
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

    /**
     * IPC: the polkit agent (utils/polkit/agent.py) pokes the pill when an app
     * needs admin rights. `prompt` parks the request on the Polkit service and
     * morphs the pill into the authorize face; `clear` closes it once the
     * agent resolves the conversation (success, failure or cancel).
     */
    IpcHandler {
        target: "polkit"
        function prompt(message: string, action: string, user: string): void {
            Polkit.message = message || "";
            Polkit.action = action || "";
            Polkit.user = user || "";
            Polkit.pending = true;
            if (root.openSurface !== "polkit")
                root.toggleSurface("", "polkit");
        }
        function clear(): void {
            Polkit.pending = false;
            if (root.openSurface === "polkit")
                root.close();
        }
    }

    /**
     * Calls (ModemManager) drive the pill directly: a ringing call summons the
     * call surface on the focused monitor, and the surface is non-dismissible
     * until the call ends (see close above), so Escape or a backdrop press
     * can't hide an active call — only the surface's red ✕ hangs up. When the
     * call ends the surface folds back automatically.
     */
    Connections {
        target: Calls
        function onOnCallChanged() {
            if (Calls.onCall)
                root.toggleSurface("", "call");
            else if (root.openSurface === "call")
                root.close();
        }
        function onRingingChanged() {
            if (Calls.ringing)
                root.toggleSurface("", "call");
        }
    }
}

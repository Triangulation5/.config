pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Live phone-call status from two sources. ModemManager is the one with a real
 * hang-up (an iPhone-style "end call" needs more than presence): it probes
 * `mmcli -L` on load, stays dormant with no modem (retrying every 30s for a
 * hotplug), and polls `--voice-list-calls` / `--voice-call <n>` for state,
 * caller and duration; `accept()` and `hangup()` drive the modem.
 *
 * Web calls (WhatsApp Web, Meet, browser Discord…) come from PipeWire: WebRTC
 * in a browser opens a playback + capture stream pair tagged
 * `media.role = "communication"`, detected by parsing `pactl list
 * sink-inputs source-outputs`. Presence and the app name come for free, mute
 * is a real `pactl set-source-output-mute`, and ending the call falls back to
 * focusing the browser window (only ModemManager can actually hang up). A web
 * call is shown as "Browser call" and never blocks the modem path when both
 * exist.
 *
 * The pill watches `onCall`/`ringing` and summons the call surface, which is
 * non-dismissible while a call is live (mirroring the polkit guard), so an
 * accidental Escape or backdrop press can't hide an active call.
 */
Singleton {
    id: root

    property int modem: -1

    property int callIndex: -1
    property string direction: ""
    property string state: ""
    property string number: ""
    property int duration: 0

    readonly property bool available: root.modem >= 0
    readonly property bool modemLive: state === "dialing" || state === "ringing-in"
        || state === "ringing-out" || state === "active"
    readonly property bool ringing: state === "dialing" || state === "ringing-in" || state === "ringing-out"
    readonly property bool active: state === "active" || (root.webCall && !root.modemLive)

    /** A live call of any kind: a ModemManager call or a detected web call. */
    readonly property bool onCall: root.modemLive || root.webCall

    /** True when the web call is the one to show; a modem call always wins. */
    readonly property bool webShown: root.webCall && !root.modemLive

    /** "Incoming call" / "Calling…" caption for the surface (web calls get "Browser call" in the view). */
    readonly property string caption: state === "ringing-in" ? "Incoming call"
        : (root.ringing ? "Calling…" : "Call")

    /** mm:ss from the modem's own duration counter. */
    readonly property string timerText: {
        var m = Math.floor(root.duration / 60);
        var s = root.duration % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    /** Web call fields (PipeWire): the browser app, its own elapsed timer, and the capture stream for mute. */
    property bool webCall: false
    property string webApp: ""
    property int webPid: 0
    property int webSourceIdx: -1
    property bool webMuted: false
    property int webSeconds: 0
    readonly property string webLabel: root.webApp.length > 0 ? root.webApp : "Web call"
    readonly property string webTimerText: {
        var m = Math.floor(root.webSeconds / 60);
        var s = root.webSeconds % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }
    onWebCallChanged: root.webSeconds = 0

    signal changed()

    Component.onCompleted: probe()

    /** Re-probe after a modem hotplug or a missed ModemManager start. */
    function probe() {
        if (probeProc.running)
            return;
        probeProc.running = true;
    }

    function poll() {
        if (listProc.running || detailProc.running || actionProc.running || webProc.running)
            return;
        if (root.available)
            listProc.running = true;
        webProc.running = true;
    }

    /** Smallest live call's index from the list output, or -1. */
    function firstLiveCall(text) {
        var live = { "dialing": 1, "ringing-in": 1, "ringing-out": 1, "active": 1 };
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/Call\s+(\d+):\s*(\S+)\s*\/\s*(\S+)/);
            if (m && live[m[3]]) {
                root.direction = m[2] === "incoming" ? "in" : "out";
                root.state = m[3];
                return parseInt(m[1], 10);
            }
        }
        return -1;
    }

    /** Pulls the named property's value out of `mmcli --voice-call` output. */
    function field(text, key) {
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim();
            if (t.indexOf(key + ":") !== 0)
                continue;
            return t.slice(key.length + 1).trim();
        }
        return "";
    }

    function accept() {
        if (root.callIndex < 0)
            return;
        actionProc.command = ["mmcli", "--voice-call", String(root.callIndex), "--accept"];
        actionProc.running = true;
    }

    function hangup() {
        if (root.callIndex < 0)
            return;
        actionProc.command = ["mmcli", "--voice-call", String(root.callIndex), "--hangup"];
        actionProc.running = true;
    }

    /**
     * Parses `pactl list sink-inputs source-outputs` for an active web call: a
     * playback + capture stream pair both tagged `media.role = "communication"`.
     * Returns true when both halves are up and records the browser app, its
     * process id (for focusing the window) and the capture stream's index and
     * mute state (for real mute via pactl).
     */
    function parseWeb(text) {
        var blocks = text.split(/\n(?=(?:Sink Input|Source Output) #\d+)/);
        var sink = null, src = null;
        for (var i = 0; i < blocks.length; i++) {
            var b = blocks[i];
            var isSink = b.indexOf("Sink Input #") === 0;
            var role = b.match(/media\.role = "([^"]+)"/);
            if (!role || role[1] !== "communication")
                continue;
            var app = b.match(/application\.name = "([^"]+)"/);
            var pid = b.match(/application\.process\.id = "(\d+)"/);
            var muted = b.match(/Mute: (yes|no)/);
            var head = b.match(/Source Output #(\d+)/);
            var hit = {
                app: app ? app[1] : "",
                pid: pid ? parseInt(pid[1], 10) : 0,
                muted: muted ? muted[1] === "yes" : false,
                idx: head ? parseInt(head[1], 10) : -1
            };
            if (isSink)
                sink = hit;
            else
                src = hit;
        }
        if (!sink || !src)
            return false;
        root.webApp = sink.app.length > 0 ? sink.app : src.app;
        root.webPid = sink.pid || src.pid;
        root.webSourceIdx = src.idx;
        root.webMuted = src.muted;
        return true;
    }

    /** Real mute for the web call: silences only the browser's capture stream. */
    function toggleWebMute() {
        if (root.webSourceIdx < 0)
            return;
        muteProc.command = ["pactl", "set-source-output-mute", String(root.webSourceIdx), "toggle"];
        muteProc.running = true;
    }

    /**
     * Best-effort end for a web call: bring the browser window forward so the
     * call is one click from over (PipeWire has no hang-up). Matches the
     * capture stream's process id against Hyprland toplevels, with a pid
     * dispatch as the fallback.
     */
    function focusWebCall() {
        var p = root.webPid;
        if (!p)
            return;
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            if (tl[i] && tl[i].pid === p) {
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + tl[i].address + '" })');
                return;
            }
        }
        Hyprland.dispatch('hl.dsp.focus({ window = "pid:' + p + '" })');
    }

    /**
     * Modem probe: `mmcli -L` lists "Modem/0 [...]" lines. A missing binary or
     * daemon leaves stdout empty, so the regex fails and the 30s retry stays
     * armed — the shell works untouched on machines without modems.
     */
    Process {
        id: probeProc
        command: ["mmcli", "-L"]
        stdout: StdioCollector {
            function onStreamFinished() {
                var m = this.text.match(/Modem\/(\d+)/);
                root.modem = m ? parseInt(m[1], 10) : -1;
                root.changed();
            }
        }
    }

    Timer {
        id: probeRetry
        interval: 30000
        repeat: true
        running: !root.available
        onTriggered: root.probe()
    }

    /**
     * Poll cadence: 2s while idle, 1s once a call is live so the duration
     * counter stays in sync with the pill's clock.
     */
    Timer {
        id: pollTimer
        interval: root.onCall ? 1000 : 2000
        repeat: true
        /** Runs always: web-call detection needs no modem. */
        running: true
        onTriggered: root.poll()
    }

    /** Web-call elapsed timer, ticked locally since PipeWire has no duration. */
    Timer {
        id: webTick
        interval: 1000
        repeat: true
        running: root.webCall
        onTriggered: root.webSeconds++
    }

    /**
     * Call list poll: finds the live call and its state. On any live call the
     * detail fetch below fills in number and duration; when nothing is live
     * the state fields reset.
     */
    Process {
        id: listProc
        command: ["mmcli", "-m", "0", "--voice-list-calls"]
        stdout: StdioCollector {
            function onStreamFinished() {
                var idx = root.firstLiveCall(this.text);
                if (idx < 0) {
                    root.callIndex = -1;
                    root.direction = "";
                    root.state = "";
                    root.number = "";
                    root.duration = 0;
                    root.changed();
                    return;
                }
                var fresh = root.callIndex !== idx;
                root.callIndex = idx;
                if (fresh) {
                    root.number = "";
                    root.duration = 0;
                    detailProc.command = ["mmcli", "--voice-call", String(idx)];
                    detailProc.running = true;
                }
                root.changed();
            }
        }
    }

    /**
     * Call detail poll: `mmcli --voice-call <n>` prints index/direction/state/
     * number/duration. Runs once per call — the list poll alone carries state
     * transitions after that, so the modem is only queried twice per second
     * at most while connected.
     */
    Process {
        id: detailProc
        command: ["mmcli", "--voice-call", "0"]
        stdout: StdioCollector {
            function onStreamFinished() {
                root.number = root.field(this.text, "number");
                var d = parseInt(root.field(this.text, "duration"), 10);
                root.duration = isNaN(d) ? 0 : d;
                root.changed();
            }
        }
    }

    /** One-shot accept/hangup; the next poll confirms the new state. */
    Process {
        id: actionProc
        command: ["mmcli", "--voice-call", "0", "--hangup"]
    }

    /**
     * Web call poll: `pactl list sink-inputs source-outputs` every tick. With
     * no pactl or no PipeWire the output is empty and detection stays off.
     */
    Process {
        id: webProc
        command: ["pactl", "list", "sink-inputs", "source-outputs"]
        stdout: StdioCollector {
            function onStreamFinished() {
                root.webCall = root.parseWeb(this.text);
                if (!root.webCall) {
                    root.webApp = "";
                    root.webPid = 0;
                    root.webSourceIdx = -1;
                    root.webMuted = false;
                }
                root.changed();
            }
        }
    }

    /** One-shot web mute; the next poll confirms the new state. */
    Process {
        id: muteProc
        command: ["pactl", "set-source-output-mute", "0", "toggle"]
    }
}
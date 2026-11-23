pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services

/**
 * Screen-recorder child processes: the open/pick/window pickers, the mkdir +
 * ffmpeg-preflight chain into the live recorder, the fallback/probe/fail/stop/
 * save notifications, the thumb + list chain feeding the recent list, and the
 * external-process poll. All state and driver functions live on the host
 * singleton (`host`); this object only drives the processes and writes results
 * back. The exposed aliases let the host's functions start and stop individual
 * processes.
 */
Item {
    id: root

    property var host: null
    property alias windowProc: windowProc
    property alias mkdirProc: mkdirProc
    property alias recProc: recProc
    property alias warnProc: warnProc
    property alias stopProc: stopProc
    property alias openProc: openProc
    property alias pickProc: pickProc
    property alias thumbProc: thumbProc
    property alias probeProc: probeProc
    property alias infoProc: infoProc

    Process {
        id: openProc
    }

    Process {
        id: pickProc
        stdout: StdioCollector {
            onStreamFinished: {
                var dir = this.text.trim();
                if (dir.length > 0)
                    Flags.recordDir = dir;
            }
        }
    }

    /**
     * Combined Window / Region picker: feeds each Hyprland client's current
     * rectangle to `slurp`, so clicking a window snaps to its `WxH+X+Y` geometry
     * while dragging draws a freeform region. The rectangle is captured
     * statically, so a window moved or resized after the pick is not followed.
     * Empty pick or non-zero exit (Escape) aborts.
     */
    Process {
        id: windowProc
        command: root.useRust
            ? [root.watcherRunner, "hypr-slurp"]
            : ["sh", "-c", "hyprctl clients -j | jq -r '.[] | \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' | slurp -f \"%wx%h+%x+%y\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var geom = this.text.trim();
                if (geom.length > 0)
                    root.host.targetReady(geom);
                else
                    root.host.targetAborted();
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 127 && root.useRust) {
                root.rustUnavailable = true;
                windowProc.running = true;
                return;
            }
            if (exitCode !== 0)
                root.host.targetAborted();
        }
    }

    Process {
        id: mkdirProc
        property string pendingToken: ""
        property string pendingFile: ""
        onExited: {
            root.host.currentFile = pendingFile;
            if (root.host.backend === "ffmpeg") {
                ffPrepProc.pendingToken = pendingToken;
                ffPrepProc.pendingFile = pendingFile;
                ffPrepProc.running = true;
            } else {
                recProc.command = root.host.buildArgs(pendingToken, pendingFile);
                recProc.running = true;
            }
        }
    }

    /**
     * ffmpeg fallback pre-flight: resolve the pulse sink / source at start
     * (they can change between recordings), then launch the portal capture.
     * The pending file is read through this Process's id: the collector is a
     * nested object, so an unqualified `pendingFile` does not resolve under
     * `pragma ComponentBehavior: Bound` and the capture never starts.
     */
    Process {
        id: ffPrepProc
        property string pendingToken: ""
        property string pendingFile: ""
        command: ["sh", "-c",
            "sink=$(pactl get-default-sink 2>/dev/null); echo \"sink=$sink\"; " +
            "src=$(pactl get-default-source 2>/dev/null); echo \"src=$src\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.indexOf("sink=") === 0)
                        root.host.ffSinkMon = line.slice(5);
                    else if (line.indexOf("src=") === 0)
                        root.host.ffMicSrc = line.slice(4);
                }
                root.host.currentFile = ffPrepProc.pendingFile;
                recProc.command = root.host.buildArgs(ffPrepProc.pendingToken, ffPrepProc.pendingFile);
                recProc.running = true;
            }
        }
    }

    /**
     * The live recorder. Its own lifecycle drives `recording` so start/stop UI is
     * immediate instead of waiting up to a poll cycle: onStarted marks running,
     * onExited marks stopped. The poll stays an external reconciler. A clean stop
     * (SIGINT) finalises and exits zero and the saved file is announced; a
     * non-zero exit before it ever reached the recording state means gsr failed to
     * start, so its stderr is surfaced and no save is announced.
     */
    Process {
        id: recProc
        stderr: StdioCollector { id: recErr }
        onStarted: {
            root.host.ffCaptureStarted = false;
            root.host.gsrConfirmed = false;
            root.host.gsrAliveTicks = 0;
            if (root.host.backend === "ffmpeg")
                root.host.recording = false;
            root.host.fallbackRetried = false;
        }
        onExited: function(exitCode) {
            var gsrConfirmed = root.host.gsrConfirmed;
            root.host.recording = false;
            root.host.gsrConfirmed = false;
            root.host.gsrAliveTicks = 0;
            if (exitCode !== 0) {
                /**
                 * gsr died before it ever reached the recording state: that's
                 * a start failure, so retry once through the ffmpeg fallback
                 * instead of dropping the recording.
                 */
                if (!gsrConfirmed && root.host.backend === "gsr" && !root.host.fallbackRetried && root.host.lastToken.length > 0) {
                    root.host.fallbackRetried = true;
                    root.host.useFallback("gpu-screen-recorder failed to start — recording with ffmpeg via the PipeWire portal");
                    root.host.start(root.host.lastToken);
                    return;
                }
                var msg = recErr.text.trim();
                failProc.command = ["notify-send", "-a", "SilhouetteShell", "-u", "critical",
                    "Recording failed", msg.length > 0 ? msg : (root.host.backend === "ffmpeg" ? "ffmpeg exited " + exitCode : "gpu-screen-recorder exited " + exitCode)];
                failProc.running = true;
            } else {
                if (Flags.recordNotify)
                    savedProc.running = true;
                Qt.callLater(root.host.refreshRecent);
            }
        }
    }

    /** One-shot notify when the ffmpeg fallback engages on a recording. */
    Process {
        id: warnProc
    }

    /**
     * Backend probe: if gpu-screen-recorder is not on PATH the session records
     * with the ffmpeg fallback from the start. When it is there, the codec probe
     * below runs right after, so a missing binary spawns nothing extra.
     */
    Process {
        id: probeProc
        command: ["sh", "-c", "command -v gpu-screen-recorder || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0)
                    root.host.useFallback("gpu-screen-recorder not found — recording with ffmpeg via the PipeWire portal");
                else
                    infoProc.running = true;
            }
        }
    }

    /**
     * Codec probe: gsr reports the video codecs its ffmpeg actually offers under
     * `section=video_codecs`. Newer nvidia drivers (580xx) against ffmpeg 9 drop
     * nvenc, leaving gsr with no native h264/hevc/av1 to pick; when that happens
     * and vulkan h264 is available the host pins `-k h264_vulkan` so recording
     * keeps working instead of failing over to the CPU encoder. Started by
     * probeProc once gsr is known to be installed.
     */
    Process {
        id: infoProc
        command: ["gpu-screen-recorder", "--info"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = this.text.match(/section=video_codecs\n([\s\S]*?)(\nsection=|$)/);
                var codecs = m ? m[1].split("\n") : [];
                var native = ["h264", "hevc", "av1"].some(function(c) { return codecs.indexOf(c) >= 0; });
                root.host.codecArgs = !native && codecs.indexOf("h264_vulkan") >= 0 ? ["-k", "h264_vulkan"] : [];
            }
        }
    }

    Process {
        id: failProc
    }

    Process {
        id: stopProc
    }

    Process {
        id: savedProc
        command: ["notify-send", "-a", "SilhouetteShell", "Recording saved",
            root.host.currentFile.substring(root.host.currentFile.lastIndexOf("/") + 1)]
    }

    function refreshRecent() {
        if (rustThumbProc.running || thumbProc.running || listProc.running)
            return;
        if (root.useRust) {
            rustThumbProc.running = true;
            return;
        }
        thumbProc.running = true;
    }

    Process {
        id: rustThumbProc
        command: [root.watcherRunner, "thumbs-rec", root.host.outDir, root.host.thumbDir,
            String(Math.max(1, Flags.recHistoryMax)), String(Flags.recordClearedBefore)]
        property string body: ""
        stdout: StdioCollector {
            onStreamFinished: rustThumbProc.body = this.text
        }
        onExited: function(exitCode) {
            if (exitCode === 127) {
                rustThumbProc.body = "";
                root.rustUnavailable = true;
                thumbProc.running = true;
                return;
            }
            if (exitCode === 0 && rustThumbProc.body.trim().length > 0) {
                try {
                    var parsed = JSON.parse(rustThumbProc.body);
                    if (Array.isArray(parsed)) {
                        var out = [];
                        for (var i = 0; i < parsed.length; i++) {
                            var r = parsed[i];
                            out.push({
                                path: r.path,
                                name: r.name,
                                mtime: r.mtime,
                                sizeLabel: root.host.humanSize(r.bytes),
                                thumb: r.thumb
                            });
                        }
                        root.host.recent = out;
                    }
                } catch (e) {
                }
            }
            rustThumbProc.body = "";
        }
    }

    Process {
        id: thumbProc
        command: ["sh", root.host.thumbScript, root.host.outDir]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["sh", "-c",
            "d=\"$1\"; [ -d \"$d\" ] || exit 0; find \"$d\" -maxdepth 1 -type f -name 'recording_*.mp4' -printf '%T@\\t%s\\t%p\\n' | sort -rn | head -n " + Math.max(1, Flags.recHistoryMax),
            "_", root.host.outDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var out = [];
                for (var i = 0; i < lines.length; i++) {
                    var cols = lines[i].split("\t");
                    if (cols.length < 3)
                        continue;
                    var mtime = parseFloat(cols[0]);
                    if (mtime <= Flags.recordClearedBefore)
                        continue;
                    var path = cols[2];
                    var name = path.substring(path.lastIndexOf("/") + 1);
                    out.push({
                        path: path,
                        name: name,
                        mtime: mtime,
                        sizeLabel: root.host.humanSize(parseFloat(cols[1])),
                        thumb: root.host.thumbDir + name.replace(/\.mp4$/, "") + ".jpg"
                    });
                }
                root.host.recent = out;
            }
        }
    }

    readonly property string watcherRunner: Qt.resolvedUrl("../utils/watchers/run.sh").toString().replace(/^file:\/\//, "")
    property bool rustUnavailable: false
    readonly property bool useRust: Flags.useRustTools && !root.rustUnavailable

    Connections {
        target: Flags
        function onUseRustToolsChanged() {
            if (Flags.useRustTools)
                root.rustUnavailable = false;
        }
    }

    function applyPollState(running) {
        if (running && root.host.backend === "ffmpeg" && !root.host.ffCaptureStarted)
            return;
        if (running && root.host.backend === "gsr") {
            root.host.gsrAliveTicks += 1;
            if (root.host.gsrAliveTicks >= 2)
                root.host.gsrConfirmed = true;
        }
        if (running !== root.host.recording) {
            root.host.recording = running;
            if (!running)
                Qt.callLater(root.host.refreshRecent);
        }
    }

    /**
     * Native inotify waiter for the `<output>.capturing` sentinel: eliminates
     * the 300ms `sh -c "test -f"` polling loop while waiting on the share picker.
     */
    Process {
        id: rustMarkerProc
        command: [root.watcherRunner, "file-wait", root.host.ffMarkerPath]
        running: root.host && root.host.backend === "ffmpeg" && recProc.running
            && !root.host.ffCaptureStarted && root.host.ffMarkerPath.length > 0 && root.useRust
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim().length === 0)
                    return;
                root.host.ffCaptureStarted = true;
                root.host.recording = true;
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 127)
                root.rustUnavailable = true;
        }
    }

    /**
     * Fallback sentinel check when Rust watchers are unavailable.
     */
    Process {
        id: markerProc
        command: ["sh", "-c", "test -f \"$1\" && echo yes", "_", root.host.ffMarkerPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0)
                    return;
                root.host.ffCaptureStarted = true;
                root.host.recording = true;
            }
        }
    }

    Timer {
        interval: 300
        running: root.host.backend === "ffmpeg" && recProc.running && !root.host.ffCaptureStarted && !root.useRust
        repeat: true
        onTriggered: if (!markerProc.running) markerProc.running = true
    }

    /**
     * Native persistent `/proc` scanner: replaces the 1s `pgrep -f` fork loop
     * while recording or while the recorder surface is open.
     */
    Process {
        id: rustPollProc
        command: [root.watcherRunner, "proc-watch", "--mode", "rec", "--interval", "1000"]
        running: root.host && (root.host.recording || root.host.recorderOpen || recProc.running) && root.useRust
        stdout: SplitParser {
            onRead: (line) => {
                var p = line.trim().split(/\s+/);
                if (p[0] === "COUNT")
                    root.applyPollState((parseInt(p[1], 10) || 0) > 0);
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 127)
                root.rustUnavailable = true;
        }
    }

    /**
     * Fallback recorder process poll when Rust watchers are unavailable.
     */
    Process {
        id: pollProc
        command: ["pgrep", "-f", "(^|/)gpu-screen-recorder|portal_capture\\.py|framepump.*--portal"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPollState(this.text.trim().length > 0)
        }
    }

    Timer {
        interval: 1000
        running: (root.host.recording || root.host.recorderOpen || recProc.running) && !root.useRust
        repeat: true
        onTriggered: if (!pollProc.running) pollProc.running = true
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Screen-recorder backend, shared by the 録 RECORD surface, the pill's hover
 * cluster record indicator and the record OSD. gpu-screen-recorder is the
 * encoder (cross-vendor nvenc/vaapi/cpu); this singleton owns the capture
 * settings, builds the argv from them, starts and stops the recorder and keeps
 * a live `recording` flag polled from the real process so an externally started
 * or stopped recorder is reflected too. gsr is launched with
 * `-fallback-cpu-encoding yes` so a machine with broken hardware encoding but a
 * working CPU encoder (libx264) degrades to CPU instead of failing; a distro
 * whose ffmpeg build omits the h264 encoders entirely still needs its full
 * ffmpeg installed (see docs/troubleshooting/commands.md).
 *
 * If gpu-screen-recorder is missing (or fails to start), the shell falls back
 * to a plain ffmpeg capture: kmsgrab grabs the whole display and the default
 * sink/source are captured through pulse. kmsgrab needs DRM master, so the
 * capture runs as root through pkexec — window/region picks narrow to the
 * full screen, and the recorder UI shows a fallback chip so the user knows
 * why. A gsr that dies before it ever starts recording is retried once
 * through this path instead of just failing.
 *
 * The capture target is chosen at leisure BEFORE any countdown, so the user
 * picks WHAT to record with no recording running yet. The surface calls one of
 * two resolvers, each emitting `targetReady(token)` on a valid pick or
 * `targetAborted()` on cancel: `prepareScreen(name)` resolves synchronously to a
 * monitor connector name (`-w DP-1`, falling back to `-w screen`);
 * `prepareWindow()` feeds the Hyprland client rectangles to `slurp` for one
 * combined Window / Region pick — clicking a window snaps to it, dragging draws
 * a freeform region — and resolves to that `WxH+X+Y` geometry. Only after
 * `targetReady` does the surface run its countdown and call `start(token)`, so
 * the order is pick → countdown → record. Audio uses gsr's device aliases (`default_output` for desktop,
 * `default_input` for the mic) so no device id is ever hardcoded; the surface's
 * faders set the captured level by driving the default sink/source through
 * Pipewire. Stop sends SIGINT, which makes gsr finalise and save the file, then
 * notify-send announces the saved file; a recorder that exits non-zero before it
 * ever started reports its stderr and resets. The on-pill record OSD shows the
 * started/stopped state, so the start is not also pushed as a notification.
 *
 * The output directory is the Flags-persisted `recordDir`, falling back to
 * `$HOME/Videos/Recordings`; `pickDir()` runs a native folder picker (kdialog
 * or zenity) and writes the chosen path back to Flags so the displayed path,
 * Open action and recent list all follow it. A `recording` poll reconciles an
 * externally started or stopped recorder so the state is never stale.
 *
 * The recent list carries a cover thumbnail per clip: `refreshRecent()` first
 * runs the thumb script (ffmpeg extracts a single frame into a cache dir under
 * `$XDG_CACHE_HOME/ricelin/rec-thumbs`, skipping clips already cached) and only
 * then re-reads the list, so each entry's `thumb` path is on disk by the time
 * the filmstrip binds to it. Entries are `{ path, name, mtime, sizeLabel,
 * thumb }`.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultDir: home + "/Videos/Recordings"
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/ricelin/rec-thumbs/"
    readonly property string thumbScript: home + "/.config/hypr/scripts/rec-thumbs.sh"
    readonly property string outDir: {
        var d = Flags.recordDir;
        return d && d.length > 0 ? d : defaultDir;
    }

    onOutDirChanged: refreshRecent()

    property int fps: Flags.recordFps
    onFpsChanged: Flags.recordFps = fps
    property string quality: Flags.recordQuality
    onQualityChanged: Flags.recordQuality = quality
    property bool captureCursor: Flags.recordCursor
    onCaptureCursorChanged: Flags.recordCursor = captureCursor
    property bool micOn: Flags.recordMic
    onMicOnChanged: Flags.recordMic = micOn
    property bool desktopOn: Flags.recordDesktop
    onDesktopOnChanged: Flags.recordDesktop = desktopOn

    property bool recording: false
    property bool recorderOpen: false
    property string currentFile: ""
    property var recent: []
    readonly property int recentCount: recent.length

    /**
     * Recording backend: `gsr` (gpu-screen-recorder) or `ffmpeg` (kmsgrab +
     * pulse fallback). Probed once at startup; a gsr that fails to start is
     * switched over mid-session with `fallbackRetried` guarding a single
     * retry. `usingFallback` and `backendNote` drive the recorder UI's
     * warning chip.
     */
    property string backend: "gsr"
    readonly property bool usingFallback: backend === "ffmpeg"
    property string backendNote: ""
    property bool fallbackRetried: false
    property bool fallbackWarned: false

    /** The capture token of the recording about to start, for the gsr retry. */
    property string lastToken: ""

    /** ffmpeg fallback inputs, resolved at start: DRM card + pulse targets. */
    property string ffDrmDev: "/dev/dri/card0"
    property string ffSinkMon: ""
    property string ffMicSrc: ""

    /** Switch the whole session to the ffmpeg backend with a reason. */
    function useFallback(note) {
        if (backend === "ffmpeg")
            return;
        backend = "ffmpeg";
        backendNote = note;
    }

    /**
     * Pre-roll countdown, owned here rather than in the surface so the quick-record
     * keybind flow gets it for free with no surface open. `beginCountdown(token)`
     * runs after any target resolves; at zero the recorder starts. `pendingTarget`
     * holds the resolved capture token across the tick-down. `counting` gates the
     * countdown UI in both the surface action bar and the standalone top toast.
     */
    property int countdown: 0
    readonly property bool counting: countdown > 0
    property string pendingTarget: ""

    /**
     * Standalone quick-capture state, read by both pills. `quickMon` is the focused
     * monitor's connector name the keybind targeted, so only that pill renders the
     * chooser and the countdown toast. `quickChoosing` shows the source chooser;
     * `quickScreenChoosing` the monitor sub-choice. The recorder surface stays out
     * of this entirely.
     */
    property bool quickChoosing: false
    property bool quickScreenChoosing: false
    property string quickMon: ""

    signal targetReady(string token)
    signal targetAborted()

    /**
     * Run the pre-roll for a freshly resolved capture token. Zero countdown starts
     * gsr at once; otherwise the token is parked and the timer ticks it down to the
     * start. Fired from this singleton's own `targetReady`, so every caller — the
     * recorder surface or the quick-record keybind — counts down the same way.
     */
    function beginCountdown(token) {
        pendingTarget = token;
        var n = Flags.recordCountdown;
        if (n > 0) {
            countdown = n;
            cdTimer.restart();
        } else {
            countdown = 0;
            cdTimer.stop();
            start(token);
            pendingTarget = "";
        }
    }

    /**
     * Abort an in-flight pre-roll: stop the timer, clear the countdown and the
     * parked token. Used by a cancelled pick and the surface's tap-to-cancel.
     */
    function cancel() {
        cdTimer.stop();
        countdown = 0;
        pendingTarget = "";
    }

    Timer {
        id: cdTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) {
                cdTimer.stop();
                root.start(root.pendingTarget);
                root.pendingTarget = "";
            }
        }
    }

    Connections {
        target: root
        function onTargetReady(token) {
            root.beginCountdown(token);
        }
        function onTargetAborted() {
            root.cancel();
        }
    }

    onRecordingChanged: if (recording) {
        cancel();
        quickChoosing = false;
        quickScreenChoosing = false;
    }

    /**
     * Connected monitors as `{ name, w, h, label }` for the Screen sub-chooser.
     * gsr's `-w <name>` records a monitor by its connector name, so the chooser
     * passes the chosen `name` straight into `prepareScreen()`. A single screen
     * needs no chooser; the surface uses the lone entry directly.
     */
    readonly property var monitors: {
        var out = [];
        var sc = Quickshell.screens;
        for (var i = 0; i < sc.length; i++) {
            var s = sc[i];
            out.push({ name: s.name, w: s.width, h: s.height, label: s.name + " · " + s.width + "×" + s.height });
        }
        return out;
    }

    /**
     * gsr quality preset for the surface's quality value. The UI labels Ultra and
     * Lossless above gsr's named presets, so Ultra maps to gsr `very_high` and
     * Lossless to gsr `ultra` (its highest QP quality); gsr has no literal
     * lossless preset.
     */
    readonly property var qualityPreset: ({
        medium: "medium",
        high: "high",
        ultra: "very_high",
        lossless: "ultra"
    })

    function timestamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
    }

    function audioArg() {
        var sources = [];
        if (desktopOn)
            sources.push("default_output");
        if (micOn)
            sources.push("default_input");
        return sources.join("|");
    }

    /**
     * True while a recording is live or a region/window picker is still up, so
     * the surface and the resolvers never stack a second pick on a busy backend.
     */
    readonly property bool picking: windowProc.running
    readonly property bool busy: recording || recProc.running || picking

    /**
     * Resolve a whole-screen target synchronously to a monitor connector name
     * (or `screen` when none was passed) and announce it. No picker runs; the
     * surface chose the screen at leisure already, so the countdown follows.
     */
    function prepareScreen(name) {
        if (busy)
            return;
        targetReady(name && name.length > 0 ? name : "screen");
    }

    /**
     * Feed the Hyprland client rectangles to `slurp` so the user picks at
     * leisure with nothing recording yet: clicking a window snaps to that
     * window, dragging draws a freeform region (one combined Window / Region
     * pick, like a screenshot tool). Announces the chosen `WxH+X+Y` geometry, or
     * aborts on cancel / non-zero exit (the user pressed Escape).
     */
    function prepareWindow() {
        if (busy)
            return;
        if (backend === "ffmpeg") {
            /** kmsgrab can only grab the whole display; skip the picker. */
            targetReady("screen");
            return;
        }
        windowProc.running = true;
    }

    function buildArgs(captureToken, file) {
        if (backend === "ffmpeg")
            return buildFfmpegArgs(file);
        var args = ["gpu-screen-recorder", "-w", captureToken,
                    "-f", String(fps), "-q", qualityPreset[quality] || "high",
                    "-cursor", captureCursor ? "yes" : "no",
                    "-fallback-cpu-encoding", "yes"];
        var a = audioArg();
        if (a.length > 0)
            args = args.concat(["-a", a]);
        args = args.concat(["-o", file]);
        return args;
    }

    /**
     * ffmpeg fallback argv: kmsgrab grabs the whole display (window/region
     * picks narrow to full screen), the default sink monitor and mic source
     * come in through pulse against the session's pipewire socket, and libx264
     * encodes on the CPU. kmsgrab needs DRM master, so the whole capture runs
     * under pkexec; stop() signals the same process as root.
     */
    function buildFfmpegArgs(file) {
        var server = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pulse/native";
        var args = ["pkexec", "ffmpeg",
                    "-f", "kmsgrab", "-device", ffDrmDev,
                    "-framerate", String(fps), "-i", "-",
                    "-vf", "hwdownload,format=nv12",
                    "-c:v", "libx264", "-preset", "veryfast",
                    "-crf", String(qualityCrf())];
        var inputs = [];
        if (desktopOn && ffSinkMon.length > 0)
            inputs.push(["-f", "pulse", "-server", server, "-i", ffSinkMon + ".monitor"]);
        if (micOn && ffMicSrc.length > 0)
            inputs.push(["-f", "pulse", "-server", server, "-i", ffMicSrc]);
        if (inputs.length === 1) {
            args = args.concat(inputs[0],
                ["-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k"]);
        } else if (inputs.length === 2) {
            args = args.concat(inputs[0], inputs[1],
                ["-filter_complex", "[1:a][2:a]amix=inputs=2:normalize=0[a]",
                 "-map", "0:v", "-map", "[a]", "-c:a", "aac", "-b:a", "192k"]);
        } else {
            args = args.concat(["-an"]);
        }
        args = args.concat(["-y", file]);
        return args;
    }

    /** Map the UI quality label onto a libx264 crf for the ffmpeg fallback. */
    function qualityCrf() {
        switch (quality) {
            case "lossless": return 0;
            case "ultra": return 12;
            case "medium": return 23;
            default: return 18;
        }
    }

    /**
     * Begin recording the already-resolved capture token (a monitor name,
     * `screen` or a WxH+X+Y geometry). Builds the output path, ensures the
     * directory exists, then launches gsr.
     */
    function start(captureToken) {
        if (recording || recProc.running)
            return;
        lastToken = captureToken;
        var file = outDir + "/recording_" + timestamp() + ".mp4";
        mkdirProc.command = ["mkdir", "-p", outDir];
        mkdirProc.pendingToken = captureToken;
        mkdirProc.pendingFile = file;
        mkdirProc.running = true;
        if (usingFallback && !fallbackWarned) {
            fallbackWarned = true;
            warnProc.command = ["notify-send", "-a", "SilhouetteShell", "Recording with ffmpeg fallback", backendNote];
            warnProc.running = true;
        }
    }

    function stop() {
        if (!recording)
            return;
        if (backend === "ffmpeg") {
            /**
             * The capture runs as root, so stopping needs root too. The unique
             * output filename only ever matches the live recorder's command
             * line (never the thumbnail ffmpeg), and SIGINT makes ffmpeg
             * finalise and save.
             */
            var name = currentFile.substring(currentFile.lastIndexOf("/") + 1);
            stopProc.command = ["pkexec", "sh", "-c", "pkill -SIGINT -f \"$1\"", "sh", name];
        } else {
            stopProc.command = ["pkill", "-SIGINT", "-f", "(^|/)gpu-screen-recorder"];
        }
        stopProc.running = true;
    }

    /**
     * Re-read the recent list, regenerating any missing cover thumbnails first.
     * The thumb script extracts a frame per clip with ffmpeg into the cache dir
     * (skipping clips whose thumb already exists and is newer) and only then does
     * the list land, so filmstrip delegates never bind to a not-yet-written jpg;
     * a thumb run already in flight is left to finish rather than stacked.
     */
    function refreshRecent() {
        if (thumbProc.running)
            return;
        thumbProc.running = true;
    }

    /**
     * Hide every current clip from the recent list without touching the files:
     * the newest clip's mtime is parked as a persisted watermark and the list is
     * emptied, so refreshes filter out anything at or before it while later
     * recordings still surface. The clips stay on disk in the save folder.
     */
    function clearRecent() {
        var newest = 0;
        for (var i = 0; i < recent.length; i++)
            newest = Math.max(newest, recent[i].mtime);
        Flags.recordClearedBefore = newest;
        recent = [];
    }

    function openFile(path) {
        openProc.command = ["xdg-open", path];
        openProc.running = true;
    }

    function openDir() {
        openProc.command = ["xdg-open", outDir];
        openProc.running = true;
    }

    /**
     * Run a native folder picker (kdialog, else zenity) seeded at the current
     * directory and write the chosen path to Flags so the surface, Open action
     * and recent list all follow it. A cancelled pick prints nothing and leaves
     * the directory unchanged.
     */
    function pickDir() {
        pickProc.command = ["sh", "-c",
            "d=\"$1\"; if command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$d\"; else zenity --file-selection --directory --filename=\"$d/\"; fi",
            "_", outDir];
        pickProc.running = true;
    }

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
        command: ["sh", "-c", "hyprctl clients -j | jq -r '.[] | \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' | slurp -f \"%wx%h+%x+%y\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var geom = this.text.trim();
                if (geom.length > 0)
                    root.targetReady(geom);
                else
                    root.targetAborted();
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.targetAborted();
        }
    }

    Process {
        id: mkdirProc
        property string pendingToken: ""
        property string pendingFile: ""
        onExited: {
            root.currentFile = pendingFile;
            if (root.backend === "ffmpeg") {
                ffPrepProc.pendingToken = pendingToken;
                ffPrepProc.pendingFile = pendingFile;
                ffPrepProc.running = true;
            } else {
                recProc.command = root.buildArgs(pendingToken, pendingFile);
                recProc.running = true;
            }
        }
    }

    /**
     * ffmpeg fallback pre-flight: resolve the DRM card and the pulse sink /
     * source at start (they can change between recordings), then launch.
     */
    Process {
        id: ffPrepProc
        property string pendingToken: ""
        property string pendingFile: ""
        command: ["sh", "-c",
            "dev=$(ls /dev/dri/card* 2>/dev/null | head -n 1); echo \"dev=$dev\"; " +
            "sink=$(pactl get-default-sink 2>/dev/null); echo \"sink=$sink\"; " +
            "src=$(pactl get-default-source 2>/dev/null); echo \"src=$src\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.indexOf("dev=") === 0)
                        root.ffDrmDev = line.slice(4);
                    else if (line.indexOf("sink=") === 0)
                        root.ffSinkMon = line.slice(5);
                    else if (line.indexOf("src=") === 0)
                        root.ffMicSrc = line.slice(4);
                }
                root.currentFile = pendingFile;
                recProc.command = root.buildArgs(pendingToken, pendingFile);
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
            root.recording = true;
            root.fallbackRetried = false;
        }
        onExited: function(exitCode) {
            var wasLive = root.recording;
            root.recording = false;
            if (exitCode !== 0) {
                /**
                 * gsr died before it ever reached the recording state: that's
                 * a start failure, so retry once through the ffmpeg fallback
                 * instead of dropping the recording.
                 */
                if (!wasLive && root.backend === "gsr" && !root.fallbackRetried && root.lastToken.length > 0) {
                    root.fallbackRetried = true;
                    root.useFallback("gpu-screen-recorder failed to start — recording with ffmpeg (full screen, root capture)");
                    root.start(root.lastToken);
                    return;
                }
                var msg = recErr.text.trim();
                failProc.command = ["notify-send", "-a", "SilhouetteShell", "-u", "critical",
                    "Recording failed", msg.length > 0 ? msg : (root.backend === "ffmpeg" ? "ffmpeg exited " + exitCode : "gpu-screen-recorder exited " + exitCode)];
                failProc.running = true;
            } else {
                savedProc.running = true;
                Qt.callLater(root.refreshRecent);
            }
        }
    }

    /** One-shot notify when the ffmpeg fallback engages on a recording. */
    Process {
        id: warnProc
    }

    /**
     * Backend probe: if gpu-screen-recorder is not on PATH the session records
     * with the ffmpeg fallback from the start.
     */
    Process {
        id: probeProc
        command: ["sh", "-c", "command -v gpu-screen-recorder || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0)
                    root.useFallback("gpu-screen-recorder not found — recording with ffmpeg");
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
            root.currentFile.substring(root.currentFile.lastIndexOf("/") + 1)]
    }

    Process {
        id: thumbProc
        command: ["sh", root.thumbScript, root.outDir]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["sh", "-c",
            "d=\"$1\"; [ -d \"$d\" ] || exit 0; find \"$d\" -maxdepth 1 -type f -name 'recording_*.mp4' -printf '%T@\\t%s\\t%p\\n' | sort -rn | head -n 40",
            "_", root.outDir]
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
                        sizeLabel: root.humanSize(parseFloat(cols[1])),
                        thumb: root.thumbDir + name.replace(/\.mp4$/, "") + ".jpg"
                    });
                }
                root.recent = out;
            }
        }
    }

    function humanSize(bytes) {
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(1) + " GB";
        if (bytes >= 1048576)
            return Math.round(bytes / 1048576) + " MB";
        if (bytes >= 1024)
            return Math.round(bytes / 1024) + " KB";
        return bytes + " B";
    }

    /**
     * Poll the real recorder process so the flag tracks gsr started or stopped
     * from anywhere, not just this surface. On a save the recent list re-reads so
     * the new file appears.
     */
    Process {
        id: pollProc
        command: ["pgrep", "-f", "(^|/)gpu-screen-recorder|kmsgrab"]
        stdout: StdioCollector {
            onStreamFinished: {
                var running = this.text.trim().length > 0;
                if (running !== root.recording) {
                    root.recording = running;
                    if (!running)
                        Qt.callLater(root.refreshRecent);
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: root.recording || root.recorderOpen
        repeat: true
        onTriggered: if (!pollProc.running) pollProc.running = true
    }

    Component.onCompleted: {
        refreshRecent();
        probeProc.running = true;
    }
}

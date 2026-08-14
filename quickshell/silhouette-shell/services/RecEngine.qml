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
                    root.host.targetReady(geom);
                else
                    root.host.targetAborted();
            }
        }
        onExited: function(exitCode) {
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
                        root.host.ffDrmDev = line.slice(4);
                    else if (line.indexOf("sink=") === 0)
                        root.host.ffSinkMon = line.slice(5);
                    else if (line.indexOf("src=") === 0)
                        root.host.ffMicSrc = line.slice(4);
                }
                root.host.currentFile = pendingFile;
                recProc.command = root.host.buildArgs(pendingToken, pendingFile);
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
            root.host.recording = true;
            root.host.fallbackRetried = false;
        }
        onExited: function(exitCode) {
            var wasLive = root.host.recording;
            root.host.recording = false;
            if (exitCode !== 0) {
                /**
                 * gsr died before it ever reached the recording state: that's
                 * a start failure, so retry once through the ffmpeg fallback
                 * instead of dropping the recording.
                 */
                if (!wasLive && root.host.backend === "gsr" && !root.host.fallbackRetried && root.host.lastToken.length > 0) {
                    root.host.fallbackRetried = true;
                    root.host.useFallback("gpu-screen-recorder failed to start — recording with ffmpeg (full screen, root capture)");
                    root.host.start(root.host.lastToken);
                    return;
                }
                var msg = recErr.text.trim();
                failProc.command = ["notify-send", "-a", "SilhouetteShell", "-u", "critical",
                    "Recording failed", msg.length > 0 ? msg : (root.host.backend === "ffmpeg" ? "ffmpeg exited " + exitCode : "gpu-screen-recorder exited " + exitCode)];
                failProc.running = true;
            } else {
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
     * with the ffmpeg fallback from the start.
     */
    Process {
        id: probeProc
        command: ["sh", "-c", "command -v gpu-screen-recorder || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0)
                    root.host.useFallback("gpu-screen-recorder not found — recording with ffmpeg");
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

    Process {
        id: thumbProc
        command: ["sh", root.host.thumbScript, root.host.outDir]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["sh", "-c",
            "d=\"$1\"; [ -d \"$d\" ] || exit 0; find \"$d\" -maxdepth 1 -type f -name 'recording_*.mp4' -printf '%T@\\t%s\\t%p\\n' | sort -rn | head -n 40",
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
                if (running !== root.host.recording) {
                    root.host.recording = running;
                    if (!running)
                        Qt.callLater(root.host.refreshRecent);
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: root.host.recording || root.host.recorderOpen
        repeat: true
        onTriggered: if (!pollProc.running) pollProc.running = true
    }
}

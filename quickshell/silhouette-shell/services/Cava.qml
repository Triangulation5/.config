pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live audio spectrum service for the rest-pill visualizer and the lock
 * screen's glow. CAVA captures the default sink monitor and outputs
 * normalized 0..1 levels.
 *
 * This service only handles audio data. The visual components (the pill bars
 * and the lock GlowField) are responsible for rendering. `enabled` forces the
 * capture on while the lock is up, independent of the pill visualizer flag.
 */
Singleton {
    id: root

    property int bars: Flags.vizStyle === "centered" ? 7 : 4

    property var levels: Array(bars).fill(0)
    property bool active: false

    property bool available: false

    /**
     * True while the resting pill can actually render the bars: the pill sets
     * this while in rest mode, so the capture never runs behind an expanded
     * pill, a hover, a surface, toast, OSD or game mode where the bars cannot
     * be seen. Defaults off; the pill flips it on at rest.
     */
    property bool pillWanted: false

    /**
     * The pill capture's real gate. Follows `pillWanted` through a grace
     * period: when the pill briefly leaves rest (hovering for the workspace
     * dots, a quick surface open) the capture stays warm so the bars resume
     * instantly instead of paying a ~2s respawn; only once the grace expires
     * while the pill is still away does the capture actually go down. Mirror
     * of the string visualizer's expandKill policy.
     */
    property bool pillCaptureWanted: false

    onPillWantedChanged: {
        if (pillWanted) {
            pillGrace.stop();
            pillCaptureWanted = true;
        } else {
            pillGrace.restart();
        }
    }

    Timer {
        id: pillGrace
        interval: 5000
        onTriggered: root.pillCaptureWanted = false
    }

    /**
     * The pill pipeline only answers to the pill visualizer flag and the
     * graced capture gate; the lock's forced capture is a separate process
     * below. The string style never needs this capture: FastMusicLine runs
     * its own 10-segment cava, so keeping the bars capture alive too would
     * run two cava processes for one visible visualizer.
     */
    readonly property bool wanted: Flags.musicViz && available && root.pillCaptureWanted
        && Flags.vizStyle !== "string"

    /**
     * Lock-glow capture: its own cava run (12 bars, ascii range 100), matching
     * the 12 bands the glow shader interpolates. Forced on while the lock
     * screen is up, independent of the pill visualizer flag.
     */
    property bool enabled: false
    readonly property int lockBars: 12
    property var lockLevels: Array(lockBars).fill(0)
    property bool lockActive: false

    /**
     * Lock capture config, generated like the pill one so the framerate
     * follows Flags.vizFps too.
     */
    property string lockConfig:
        "[general]\n"
        + "mode = normal\n"
        + "framerate = " + Flags.vizFps + "\n"
        + "bars = " + lockBars + "\n"
        + "autosens = 1\n"
        + "[input]\n"
        + "method = pulse\n"
        + "source = auto\n"
        + "[output]\n"
        + "method = raw\n"
        + "raw_target = /dev/stdout\n"
        + "data_format = ascii\n"
        + "ascii_max_range = 100\n"
        + "channels = mono\n"

    property string config:
        "[general]\n"
        + "bars = " + bars + "\n"
        + "framerate = " + Flags.vizFps + "\n"
        + "autosens = 0\n"
        + "sensitivity = 3500\n"
        + "[input]\n"
        + "method = pulse\n"
        + "source = auto\n"
        + "[output]\n"
        + "method = raw\n"
        + "raw_target = /dev/stdout\n"
        + "data_format = ascii\n"
        + "ascii_max_range = 1000\n"
        + "bar_delimiter = 59\n"
        + "frame_delimiter = 10\n"
        + "channels = mono\n"
        + "mono_option = average\n"
        + "[smoothing]\n"
        + "noise_reduction = 0.77\n"


    onWantedChanged: {
        cavaProc.running = wanted
        idle.stop()

        if (wanted) {
            /**
             * Fresh countdown on return: if the first frames are silence the
             * idle timer drops the frozen bars within its interval instead of
             * leaving them stuck.
             */
            idle.restart()
        } else if (!Flags.musicViz || !root.available) {
            /**
             * Freeze, don't vanish, on expand: active and levels persist so
             * returning to rest shows the bars immediately while cava respawns
             * in the background - a killed-and-respawned capture would
             * otherwise read as a visible reload. With the grace gate this
             * only fires after the pill has been away from rest past the
             * 5s window; brief absences never reach it. Only turning the
             * visualizer off or losing cava actually zeroes them.
             */
            levels = Array(bars).fill(0)
            active = false
        }
    }

    onEnabledChanged: {
        lockProc.running = enabled && available

        if (!enabled) {
            lockLevels = Array(lockBars).fill(0)
            lockActive = false
        }
    }

    onAvailableChanged: {
        cavaProc.running = wanted
        lockProc.running = enabled && available
    }

    Component.onCompleted: {
        cavaProc.running = wanted
        lockProc.running = enabled && available
    }

    /**
     * Live config changes: the config bindings track Flags continuously, so a
     * capture relaunched after a framerate or bar-count change comes up with
     * the new settings instead of the shell-start values. A running capture is
     * bounced through its relaunch timer (it picks the fresh config up on
     * respawn); when the pill is expanded the wanted flip already handles it.
     * The string visualizer self-heals the same way via the rest/expand cycle.
     */
    Connections {
        target: Flags
        function onVizFpsChanged() {
            if (root.wanted && cavaProc.running)
                cavaProc.running = false;
            if (root.enabled && root.available && lockProc.running)
                lockProc.running = false;
        }
        function onVizStyleChanged() {
            if (root.wanted && cavaProc.running)
                cavaProc.running = false;
        }
    }

    Process {
        running: true

        command: [
            "sh",
            "-c",
            "command -v cava >/dev/null 2>&1"
        ]

        onExited: (code) => {
            root.available = code === 0
        }
    }


    Process {
        id: cavaProc

        command: [
            "/bin/bash",
            "-c",
            "exec cava -p /dev/stdin <<< \"$1\"",
            "_",
            root.config
        ]


        stdout: SplitParser {
            onRead: (line) => {
                if (!line)
                    return

                const parts = line.split(";")
                const frame = new Array(root.bars)
                let peak = 0

                for (let i = 0; i < frame.length; i++) {
                    const value = Math.max(
                        0,
                        Math.min(
                            1,
                            Number(parseInt(parts[i])) / 1000 || 0
                        )
                    )

                    frame[i] = value

                    if (value > peak)
                        peak = value
                }


                root.levels = frame


                if (peak > 0.02) {
                    root.active = true
                    idle.restart()
                }
            }
        }


        onExited:
            if (root.wanted)
                relaunch.restart()
    }


    Timer {
        id: relaunch

        interval: 1500

        onTriggered:
            if (root.wanted)
                cavaProc.running = true
    }


    Timer {
        id: idle

        /**
         * How long a silent stretch keeps the bars alive before they drop.
         * Long enough to ride out short speech pauses without flicker, short
         * enough that the bars retract promptly once audio actually stops.
         */
        interval: 300

        onTriggered: {
            root.active = false
            root.levels = Array(root.bars).fill(0)
        }
    }

    /**
     * Lock-glow capture, piped the generated 12-bar config so the glow
     * shader's bands get one real cava bar each instead of a
     * spread-downsampled 4/7-bar feed.
     */
    Process {
        id: lockProc

        command: ["/bin/bash", "-c", "exec cava -p /dev/stdin <<< \"$1\"", "_", root.lockConfig]

        stdout: SplitParser {
            onRead: (line) => {
                if (!line)
                    return

                const parts = line.split(";")
                const frame = new Array(root.lockBars)
                let peak = 0

                for (let i = 0; i < frame.length; i++) {
                    const value = Math.max(
                        0,
                        Math.min(
                            1,
                            Number(parseInt(parts[i])) / 100 || 0
                        )
                    )

                    frame[i] = value

                    if (value > peak)
                        peak = value
                }

                root.lockLevels = frame

                if (peak > 0.02) {
                    root.lockActive = true
                    lockIdle.restart()
                }
            }
        }

        onExited:
            if (root.enabled && root.available)
                lockRelaunch.restart()
    }

    Timer {
        id: lockRelaunch

        interval: 1500

        onTriggered:
            if (root.enabled && root.available)
                lockProc.running = true
    }

    Timer {
        id: lockIdle

        interval: 450

        onTriggered: {
            root.lockActive = false
            root.lockLevels = Array(root.lockBars).fill(0)
        }
    }
}

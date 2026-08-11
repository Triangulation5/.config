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

    readonly property int bars: Flags.vizStyle === "centered" ? 7 : 4

    property var levels: Array(bars).fill(0)
    property bool active: false

    property bool available: false

    /**
     * True while the resting pill can actually render the bars: the pill sets
     * this while in rest mode, so the 60fps capture never runs behind an
     * expanded pill, a hover, a surface, toast, OSD or game mode where the
     * bars cannot be seen. Defaults off; the pill flips it on at rest.
     */
    property bool pillWanted: false

    /**
     * The pill pipeline only answers to the pill visualizer flag and rest-mode
     * visibility; the lock's forced capture is a separate process below.
     */
    readonly property bool wanted: Flags.musicViz && available && root.pillWanted

    /**
     * Lock-glow capture: its own cava run from assets/cava.conf (12 bars,
     * ascii range 100), matching the 12 bands the glow shader interpolates.
     * Forced on while the lock screen is up, independent of the pill
     * visualizer flag.
     */
    property bool enabled: false
    readonly property int lockBars: 12
    property var lockLevels: Array(lockBars).fill(0)
    property bool lockActive: false

    readonly property string lockConfigPath: Quickshell.shellPath("assets/cava.conf")

    readonly property string config:
        "[general]\n"
        + "bars = " + bars + "\n"
        + "framerate = 60\n"
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

        if (!wanted) {
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
            "sh",
            "-c",
            "printf '%s' \"$1\" | cava -p /dev/stdin",
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
     * Lock-glow capture, driven straight from assets/cava.conf (12 bars,
     * ascii range 100) so the glow shader's twelve bands get one real cava
     * bar each instead of a spread-downsampled 4/7-bar feed.
     */
    Process {
        id: lockProc

        command: ["cava", "-p", root.lockConfigPath]

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

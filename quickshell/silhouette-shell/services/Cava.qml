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
     * Forced on while the lock screen is up, independent of the pill visualizer
     * flag: the lock's GlowField needs live levels even when the pill bars are
     * switched off, so `wanted` is the union of the two.
     */
    property bool enabled: false
    readonly property bool wanted: (Flags.musicViz || enabled) && available

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

    onAvailableChanged:
        cavaProc.running = wanted

    Component.onCompleted:
        cavaProc.running = wanted


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
                const frame = []
                let peak = 0

                for (let i = 0; i < root.bars; i++) {
                    const value = Math.max(
                        0,
                        Math.min(
                            1,
                            Number(parseInt(parts[i])) / 1000 || 0
                        )
                    )

                    frame.push(value)

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

        interval: 450

        onTriggered: {
            root.active = false
            root.levels = Array(root.bars).fill(0)
        }
    }
}

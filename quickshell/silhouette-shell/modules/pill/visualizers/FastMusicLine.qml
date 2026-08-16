import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Shapes
import qs.services

/**
 * String audio visualizer. Runs its own cava process and draws one flowing cubic
 * string across the pill from per-segment levels, with colored end dots and a
 * soft glow. Drawn in a 200x200 space so the pill can scale it freely; powers
 * MusicBars' string style.
 */

Rectangle {
    id: musicLineContainer

    height: parent ? parent.height : 150
    width: curveWidth * (1 + curveSpill * 2 / 10)

    color: "transparent"

    property int segments: 10
    property int curveWidth: 200
    property int curveHeight: 100
    property double curveSpill: 1.5

    /**
     * True while the visualizer feature is enabled (Flags.musicViz). The cava
     * capture runs whenever this is set, so the string is already warm by the
     * time audio flows - no spawn delay on the first note. Frames are still
     * only consumed while `resting`, and a long stretch away from rest puts
     * the capture down via forcedDown instead of parsing frames 24/7.
     */
    property bool live: false

    /**
     * True while the pill is at rest. The process stays alive (warm) whenever
     * live, but frames are only consumed while resting - so the string
     * resumes instantly on return to rest without parsing hidden frames.
     * Warmth only pays off for short peek-aways: after expandKill's interval
     * away from rest the capture is put down (forcedDown), so a long surface
     * session, parked hover or game mode can't burn a hidden capture.
     * Returning to rest clears forcedDown and respawns it.
     */
    property bool resting: false

    /**
     * Latched by expandKill after a long stretch away from rest. Kept as a
     * separate flag (instead of poking cava.running directly, which would
     * sever the running binding) so returning to rest revives the process.
     */
    property bool forcedDown: false

    property variant cavaData: [
        0,0,0,0,0,0,0,0,0,0
    ]

    property var colors: [
        "#9BB6FF",
        "#7FC4FF",
        "#E0B6FF",
        "#FFD27F",
        "#FF7F9A"
    ]

    Process {
        id: cava

        running: musicLineContainer.live && !musicLineContainer.forcedDown

        command: [
            "/bin/bash",
            "-c",
            'printf "[general]\n' +
            'framerate=' + Flags.vizFps + '\n' +
            'bars=' + segments + '\n' +
            '[output]\n' +
            'method=raw\n' +
            'raw_target=/dev/stdout\n' +
            'data_format=ascii\n' +
            'ascii_max_range=1000\n' +
            '[smoothing]\n' +
            'integral=0\n' +
            'waves=0\n' +
            'gravity=10000000\n' +
            '[input]\n' +
            'method=pulse\n' +
            'source=auto\n" | cava -p /dev/stdin'
        ]

        stdout: SplitParser {
            onRead: data => {
                if (!musicLineContainer.resting)
                    return

                var parts = data.trim().split(";")
                var out = new Array(parts.length - 1)
                for (var i = 0; i < out.length; i++)
                    out[i] = parseFloat(parts[i]) / 1000
                cavaData = out
            }
        }
    }

    /**
     * Kill-after-long-expand: quick hover-peeks keep the warm capture (instant
     * resume), but once the pill has been away from rest for this long the
     * hidden capture stops paying for itself (long surface session,
     * parked hover, or game mode where the string can't be seen anyway). Fires
     * once per stretch; returning to rest clears forcedDown and respawns, so
     * the only cost is a ~150ms warm-up on that first return. Matches the
     * pill bars capture's grace policy.
     */
    Timer {
        id: expandKill
        interval: 5000
        running: !musicLineContainer.resting
        repeat: false
        onTriggered: musicLineContainer.forcedDown = true
    }

    onRestingChanged: if (resting)
        forcedDown = false


    function color_mix(color1, color2, weight) {
        return Qt.rgba(
            color1.r + (color2.r - color1.r) * weight,
            color1.g + (color2.g - color1.g) * weight,
            color1.b + (color2.b - color1.b) * weight,
            1
        )
    }


    function getColor(index) {

        var pos = index / Math.max(1, segments - 1)

        var scaled = pos * (colors.length - 1)

        var first = Math.floor(scaled)
        var second = Math.min(first + 1, colors.length - 1)

        var amount = scaled - first

        return color_mix(
            Qt.color(colors[first]),
            Qt.color(colors[second]),
            amount
        )
    }


    Glow {
        anchors.fill: parent

        radius: 20
        /**
         * Samples kept low: at this tiny scale the 25-tap blur reads the same
         * as 12, and it's re-rendered every frame at 60fps - needless iGPU
         * work for a glow that barely shows.
         */
        samples: 12

        color: Qt.rgba(
            1.0,
            0.78,
            0.45,
            0.45
        )

        source: musicLine
    }


    Shape {

        id: musicLine

        width: parent.width
        height: parent.height

        anchors.centerIn: parent

        preferredRendererType: Shape.CurveRenderer


        Instantiator {

            model: segments


            onObjectAdded: (index, cubicPath) => {

                cubicPath.segments = segments
                cubicPath.curveHeight = curveHeight
                cubicPath.curveWidth = curveWidth

                musicLine.data.push(cubicPath)
            }


            delegate: ShapePath {

                readonly property int index: model.index

                property int segments: musicLineContainer.segments
                property int curveHeight: musicLineContainer.curveHeight
                property int curveWidth: musicLineContainer.curveWidth


                strokeWidth:
                    3.5 + (cavaData[index] || 0) * 6


                strokeColor:
                    getColor(index)


                fillColor: "transparent"


                startX: 0
                startY: parent.height / 2


                pathHints: ShapePath.PathQuadratic


                PathCubic {

                    x: curveWidth
                    y: parent.height / 2


                    control1X:
                        (
                            index > segments / 2
                            ? index - 1 + cavaData[index] * curveSpill
                            : index - 1 - cavaData[index] * curveSpill
                        )
                        *
                        curveWidth / segments


                    control1Y:
                        parent.height / 2 +
                        (
                            index < segments / 4 ||
                            index > segments * 3 / 4
                            ?
                            -(curveHeight) * (cavaData[index] || 0)
                            :
                            (curveHeight) * (cavaData[index] || 0)
                        )


                    control2X: curveWidth
                    control2Y: parent.height / 2
                }
            }
        }


        ShapePath {

            strokeColor: "transparent"

            fillColor: Qt.color("#9BB6FF")

            startX: 0
            startY: parent.height / 2


            PathAngleArc {

                centerX: 0
                centerY: parent.height / 2

                radiusX: 6
                radiusY: 6

                startAngle: 0
                sweepAngle: 360
            }
        }


        ShapePath {

            strokeColor: "transparent"

            fillColor: Qt.color("#FF7F9A")

            startX: curveWidth
            startY: parent.height / 2


            PathAngleArc {

                centerX: curveWidth
                centerY: parent.height / 2

                radiusX: 6
                radiusY: 6

                startAngle: 0
                sweepAngle: 360
            }
        }
    }
}

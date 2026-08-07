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

        running: true

        command: [
            "/bin/bash",
            "-c",
            'printf "[general]\n' +
            'framerate=60\n' +
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

                var bars = data.trim().split(";")
                bars.pop()

                cavaData = bars.map(function(bar) {
                    return parseFloat(bar) / 1000
                })
            }
        }
    }


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
        samples: 25

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

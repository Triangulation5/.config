import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import qs.services

Rectangle {
    height: 150
    width: 500
    color: "transparent"

    property int sections: 3

    property variant values: []
    property double prev_end: 0.0

    property var colors: [
        Theme.flameCore,
        Theme.vermLit,
        Theme.verm,
        Theme.vermBurn,
        Theme.vermDeep,
        Theme.flameTip
    ]

    onValuesChanged: {
        canvas.requestPaint();
    }


    Process {
        id: cava

        running: true

        command: [
            "/bin/bash",
            "-c",
            'printf "[general]\n' +
            'framerate=60\n' +
            'bars=' + sections + '\n' +
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

                values = bars.map(function(bar) {
                    return parseFloat(bar) / 1000
                })
            }
        }
    }


    function color_mix(color1, color2, weight) {
        return Qt.rgba(
            color1.r * (1 - weight) + color2.r * weight,
            color1.g * (1 - weight) + color2.g * weight,
            color1.b * (1 - weight) + color2.b * weight,
            1
        )
    }


    function getSectionColor(index) {

        var pos = index / Math.max(1, sections - 1)

        var scaled = pos * (colors.length - 1)

        var first = Math.floor(scaled)
        var second = Math.min(first + 1, colors.length - 1)

        var amount = scaled - first

        return color_mix(
            colors[first],
            colors[second],
            amount
        )
    }


    Canvas {
        id: canvas

        anchors.fill: parent

        onPaint: {

            var ctx = canvas.getContext("2d")

            ctx.clearRect(
                0,
                0,
                canvas.width,
                canvas.height
            )


            for (var i = 0; i < sections; i++) {

                var value = values[i] || 0

                ctx.beginPath()

                var lineColor = getSectionColor(i)

                ctx.strokeStyle = lineColor

                ctx.lineWidth = 2 + (5 * value)


                ctx.shadowBlur = 15

                ctx.shadowColor = lineColor


                ctx.moveTo(
                    0,
                    canvas.height / 2
                )


                ctx.bezierCurveTo(
                    0,
                    canvas.height / 2,

                    (i * canvas.width) / sections,

                    canvas.height / 2 +
                    (
                        (i < sections / 4 || i > sections * 3 / 4)
                            ? -(canvas.height * value)
                            : (canvas.height * value)
                    ),

                    canvas.width,
                    canvas.height / 2
                )


                ctx.stroke()

                ctx.shadowBlur = 0

                ctx.closePath()
            }
        }
    }
}

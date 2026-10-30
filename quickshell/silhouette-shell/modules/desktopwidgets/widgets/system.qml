import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components.icons

Item {
    id: root

    readonly property real s: Math.max(0.75, Math.min(1.7, Math.min(width / 260, height / 168)))
    property var samples: []
    readonly property color loadColor: Sysmon.cpu > 85 ? Theme.error : Theme.primary

    function appendSample() {
        var next = root.samples.slice();
        next.push(Sysmon.cpu);
        while (next.length > 42)
            next.shift();
        root.samples = next;
    }

    Component.onCompleted: root.appendSample()

    Connections {
        target: Sysmon
        function onCpuChanged() {
            root.appendSample();
            graph.requestPaint();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22 * root.s
        color: Theme.surfaceContainerLowest
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.25)
    }

    Row {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        anchors.topMargin: 13 * root.s
        spacing: 7 * root.s

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 14 * root.s
            height: width
            name: "monitor"
            color: Theme.primary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Load"
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 13 * root.s
            font.weight: Font.DemiBold
        }

        Item { width: Math.max(0, header.width - 136 * root.s); height: 1 }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * root.s
            height: width
            name: "sun"
            color: Theme.onSurfaceVariant
            visible: Sysmon.cpuTemp >= 0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Sysmon.cpuTemp >= 0 ? Sysmon.cpuTemp + "°C" : ""
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
    }

    Row {
        id: hero
        anchors.left: parent.left
        anchors.leftMargin: 18 * root.s
        anchors.top: header.bottom
        anchors.topMargin: 5 * root.s
        spacing: 7 * root.s

        Text {
            text: Sysmon.cpu + "%"
            color: root.loadColor
            font.family: Theme.font
            font.pixelSize: 34 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6 * root.s
            text: "CPU"
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
    }

    Canvas {
        id: graph
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 15 * root.s
        anchors.rightMargin: 15 * root.s
        anchors.top: hero.bottom
        anchors.bottom: footer.top
        anchors.topMargin: 1 * root.s
        anchors.bottomMargin: 9 * root.s
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var points = root.samples;
            if (points.length < 2)
                return;
            var step = width / (points.length - 1);
            ctx.beginPath();
            for (var i = 0; i < points.length; i++) {
                var x = i * step;
                var y = height - (points[i] / 100) * (height - 5) - 2;
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.lineWidth = 1.6 * root.s;
            ctx.strokeStyle = root.loadColor;
            ctx.stroke();
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.globalAlpha = 0.13;
            ctx.fillStyle = root.loadColor;
            ctx.fill();
            ctx.globalAlpha = 1;
        }
    }

    Row {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        anchors.bottomMargin: 12 * root.s
        spacing: 5 * root.s

        Repeater {
            model: [
                { label: "RAM", value: Sysmon.memPct + "%" },
                { label: "GPU", value: Sysmon.hasGpu ? Sysmon.gpu + "%" : "—" },
                { label: "DISK", value: Sysmon.diskPct + "%" }
            ]

            delegate: Row {
                required property var modelData
                width: (footer.width - 10 * root.s) / 3
                spacing: 4 * root.s

                Text {
                    text: modelData.label
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                }
                Text {
                    text: modelData.value
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}

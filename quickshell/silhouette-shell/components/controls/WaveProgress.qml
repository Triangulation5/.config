import QtQuick
import qs.services

Item {
    id: root

    property real value: 0
    property real actualValue: value
    property bool showActualPlaybackState: false
    property bool isPlaying: false
    property real lineWidth: 2
    property real wavelength: 20
    property real amplitude: 1.6
    property color trackColor: Qt.alpha(Theme.onSurfaceVariant, 0.4)
    property color fillColor: Theme.primary
    property color playheadColor: Theme.primary
    property color actualProgressColor: Theme.onSurfaceVariant
    property real phase: 0
    property real currentAmplitude: isPlaying ? amplitude : 0

    Behavior on currentAmplitude {
        enabled: !Flags.reduceMotion
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    onValueChanged: canvas.requestPaint()
    onActualValueChanged: canvas.requestPaint()
    onCurrentAmplitudeChanged: canvas.requestPaint()

    FrameAnimation {
        running: root.visible && root.isPlaying && !Flags.reduceMotion
        onTriggered: {
            root.phase = (root.phase + 0.03 * frameTime * 60) % (Math.PI * 2);
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        Connections {
            target: root
            function onPhaseChanged() { canvas.requestPaint(); }
        }

        function yAt(x) {
            const mid = height / 2;
            return mid + root.currentAmplitude
                * Math.sin((x / Math.max(1, width)) * (width / root.wavelength) * Math.PI * 2 + root.phase);
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0)
                return;

            const end = Math.max(0, Math.min(1, root.value)) * width;
            const steps = Math.max(1, Math.ceil(width / 2));
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            ctx.beginPath();
            ctx.moveTo(0, yAt(0));
            for (let i = 1; i <= steps; i++) {
                const x = width * i / steps;
                ctx.lineTo(x, yAt(x));
            }
            ctx.strokeStyle = root.trackColor;
            ctx.lineWidth = root.lineWidth;
            ctx.stroke();

            if (end > 0) {
                ctx.beginPath();
                ctx.moveTo(0, yAt(0));
                const fillSteps = Math.max(1, Math.ceil(steps * end / width));
                for (let i = 1; i <= fillSteps; i++) {
                    const x = end * i / fillSteps;
                    ctx.lineTo(x, yAt(x));
                }
                ctx.strokeStyle = root.fillColor;
                ctx.lineWidth = root.lineWidth;
                ctx.stroke();
            }

            function drawMarker(ratio, color, lineWidth) {
                const x = Math.max(0, Math.min(1, ratio)) * width;
                ctx.beginPath();
                ctx.moveTo(x, Math.max(0, height / 2 - 7));
                ctx.lineTo(x, Math.min(height, height / 2 + 7));
                ctx.strokeStyle = color;
                ctx.lineWidth = lineWidth;
                ctx.stroke();
            }

            if (root.showActualPlaybackState)
                drawMarker(root.actualValue, root.actualProgressColor, 1.5);
            drawMarker(root.value, root.playheadColor, 2);
        }
    }
}

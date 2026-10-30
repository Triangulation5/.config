import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.desktopwidgets

Item {
    id: root

    readonly property real faceSize: Math.min(width, height)
    readonly property real faceScale: faceSize / 160
    property var now: new Date()
    readonly property real hourAngle: ((now.getHours() % 12) + now.getMinutes() / 60) * 30
    readonly property real minuteAngle: (now.getMinutes() + now.getSeconds() / 60) * 6
    readonly property real secondAngle: now.getSeconds() * 6

    function facePoint(angle) {
        const center = 80;
        const radius = 71;
        const roundness = 0.22;
        const squirclePower = 1 + roundness * 2.8;
        const a = angle - Math.PI / 2;
        const ux = Math.cos(a);
        const uy = Math.sin(a);
        const wave = Math.pow((Math.cos(12 * a) + 1) / 2, 0.92);
        const modulation = 1 + 0.075 * wave;
        const sx = (ux < 0 ? -1 : 1) * Math.pow(Math.abs(ux), 1 / squirclePower);
        const sy = (uy < 0 ? -1 : 1) * Math.pow(Math.abs(uy), 1 / squirclePower);
        return Qt.point(
            center + radius * modulation * (ux * (1 - roundness) + sx * roundness),
            center + radius * modulation * (uy * (1 - roundness) + sy * roundness)
        );
    }

    function buildFacePath() {
        const segments = 96;
        const dt = Math.PI * 2 / segments;
        const epsilon = dt * 0.25;
        function derivative(angle) {
            const before = root.facePoint(angle - epsilon);
            const after = root.facePoint(angle + epsilon);
            return Qt.point(
                (after.x - before.x) / (2 * epsilon),
                (after.y - before.y) / (2 * epsilon)
            );
        }

        const first = root.facePoint(0);
        let path = `M ${first.x.toFixed(2)} ${first.y.toFixed(2)} `;
        for (let i = 0; i < segments; i++) {
            const startAngle = i * dt;
            const endAngle = (i + 1) * dt;
            const start = root.facePoint(startAngle);
            const end = root.facePoint(endAngle);
            const startTangent = derivative(startAngle);
            const endTangent = derivative(endAngle);
            path += `C ${(start.x + dt / 3 * startTangent.x).toFixed(2)} ${(start.y + dt / 3 * startTangent.y).toFixed(2)}, `;
            path += `${(end.x - dt / 3 * endTangent.x).toFixed(2)} ${(end.y - dt / 3 * endTangent.y).toFixed(2)}, `;
            path += `${end.x.toFixed(2)} ${end.y.toFixed(2)} `;
        }
        return path + "Z";
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Item {
        width: 160
        height: 160
        scale: root.faceScale
        transformOrigin: Item.Center
        anchors.centerIn: parent

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            visible: DesktopWidgetState.clockStyle !== "circle"

            ShapePath {
                fillColor: Theme.surfaceContainerLowest
                strokeColor: Qt.alpha(Theme.outlineVariant, 0.35)
                strokeWidth: 1
                PathSvg {
                    path: DesktopWidgetState.clockStyle === "nebula"
                        ? "M80 4 C94 4 101 17 113 17 C128 16 141 26 141 41 C141 54 156 60 156 74 C156 88 143 96 145 109 C147 123 136 136 122 135 C109 134 102 156 87 156 C73 156 66 142 53 143 C39 144 26 134 27 120 C28 106 5 102 5 87 C5 73 20 66 18 53 C16 39 27 27 41 28 C56 29 63 4 80 4 Z"
                        : root.buildFacePath()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: width / 2
            color: Theme.surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.45)
            visible: DesktopWidgetState.clockStyle === "circle"

            Repeater {
                model: 12

                delegate: Item {
                    id: tick
                    required property int index
                    anchors.fill: parent
                    rotation: index * 30

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 13
                        width: tick.index % 3 === 0 ? 2 : 1
                        height: tick.index % 3 === 0 ? 7 : 4
                        radius: width / 2
                        color: tick.index % 3 === 0 ? Theme.primary : Theme.outlineVariant
                        opacity: tick.index % 3 === 0 ? 0.9 : 0.7
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 8
            height: 39
            radius: 4
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            transformOrigin: Item.Bottom
            rotation: root.hourAngle

            Behavior on rotation {
                RotationAnimation { duration: 360; direction: RotationAnimation.Clockwise; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 5
            height: 53
            radius: 2.5
            color: Theme.onSurface
            transformOrigin: Item.Bottom
            rotation: root.minuteAngle
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 2
            height: 58
            radius: 1
            color: Theme.primary
            transformOrigin: Item.Bottom
            rotation: root.secondAngle
        }

        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: width
            radius: width / 2
            color: Theme.primary
            z: 2
        }
    }
}

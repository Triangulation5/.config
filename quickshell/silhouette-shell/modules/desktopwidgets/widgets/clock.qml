import QtQuick
import QtQuick.Shapes
import qs.services

Item {
    id: root

    readonly property real faceSize: Math.min(width, height)
    readonly property real faceScale: faceSize / 160
    property var now: new Date()
    readonly property real hourAngle: ((now.getHours() % 12) + now.getMinutes() / 60) * 30
    readonly property real minuteAngle: (now.getMinutes() + now.getSeconds() / 60) * 6
    readonly property real secondAngle: now.getSeconds() * 6

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

            ShapePath {
                fillColor: Theme.surfaceContainerLowest
                strokeColor: Qt.alpha(Theme.outlineVariant, 0.35)
                strokeWidth: 1
                PathSvg {
                    path: "M80 4 C94 4 101 17 113 17 C128 16 141 26 141 41 C141 54 156 60 156 74 C156 88 143 96 145 109 C147 123 136 136 122 135 C109 134 102 156 87 156 C73 156 66 142 53 143 C39 144 26 134 27 120 C28 106 5 102 5 87 C5 73 20 66 18 53 C16 39 27 27 41 28 C56 29 63 4 80 4 Z"
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

import QtQuick
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

        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: width / 2
            color: Theme.surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.45)
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            width: 6
            height: width
            radius: width / 2
            color: Theme.primary
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 6
            height: 160 * 0.30
            radius: width / 2
            color: Theme.onSurfaceVariant
            transformOrigin: Item.Bottom
            rotation: root.hourAngle

            Behavior on rotation {
                RotationAnimation { duration: 360; direction: RotationAnimation.Clockwise; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 3
            height: 160 * 0.40
            radius: width / 2
            color: Theme.onSurfaceVariant
            transformOrigin: Item.Bottom
            rotation: root.minuteAngle
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 2
            height: 160 * 0.42
            radius: 1
            color: Theme.primary
            transformOrigin: Item.Bottom
            rotation: root.secondAngle

            Behavior on rotation {
                RotationAnimation {
                    duration: 200
                    direction: RotationAnimation.Clockwise
                    easing.type: Easing.Linear
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: width
            radius: width / 2
            color: Theme.onSurfaceVariant
            z: 2
        }

        Rectangle {
            id: dateBadge
            x: parent.width / 2 + parent.width * 0.36 - width / 2
            y: parent.height / 2 + parent.height * 0.04 - height / 2
            height: 22
            width: dateLabel.implicitWidth + 16
            radius: height / 2
            color: Theme.primary
            z: 3

            Text {
                id: dateLabel
                anchors.centerIn: parent
                text: Qt.formatDate(root.now, "d")
                color: Theme.onPrimary
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }
    }
}

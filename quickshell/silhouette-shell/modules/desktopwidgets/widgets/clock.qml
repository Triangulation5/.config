import QtQuick
import qs.services

Item {
    id: root

    readonly property real faceSize: Math.min(width, height)
    readonly property real faceScale: faceSize / 160
    property date now: new Date()
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
            anchors.margins: 4
            radius: width / 2
            color: Theme.surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.55)
        }

        Repeater {
            model: 60
            delegate: Rectangle {
                required property int index
                readonly property real tickWidth: index % 5 === 0 ? 2 : 1
                readonly property real tickHeight: index % 5 === 0 ? 8 : 3
                x: 80 - width / 2
                y: 8
                width: tickWidth
                height: tickHeight
                radius: width / 2
                color: index % 5 === 0 ? Theme.onSurfaceVariant : Theme.outlineVariant
                transform: Rotation {
                    origin.x: parent.width / 2
                    origin.y: 72
                    angle: index * 6
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 23
            text: "12"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 22
            text: "3"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 23
            text: "6"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 22
            text: "9"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 7
            height: 42
            radius: width / 2
            color: Theme.onSurface
            transformOrigin: Item.Bottom
            rotation: root.hourAngle
            Behavior on rotation {
                RotationAnimation { duration: 360; direction: RotationAnimation.Clockwise; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 4
            height: 58
            radius: width / 2
            color: Theme.onSurfaceVariant
            transformOrigin: Item.Bottom
            rotation: root.minuteAngle
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 2
            height: 64
            radius: width / 2
            color: Theme.primary
            transformOrigin: Item.Bottom
            rotation: root.secondAngle
            Behavior on rotation {
                RotationAnimation { duration: 200; direction: RotationAnimation.Clockwise; easing.type: Easing.Linear }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: width
            radius: width / 2
            color: Theme.onSurface
            z: 2
        }
        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: width
            radius: width / 2
            color: Theme.primary
            z: 3
        }
    }
}

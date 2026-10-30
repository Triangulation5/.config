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

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 8
            height: 36
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
            height: 51
            radius: 2.5
            color: Theme.onSurface
            transformOrigin: Item.Bottom
            rotation: root.minuteAngle
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            width: 2
            height: 59
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

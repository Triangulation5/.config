pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Item {
    id: battery

    property real s: 1.1
    property bool expanded: false
    property real pressScale: 1

    readonly property string icon: {
        if (Battery.full)
            return "battery-full";
        if (Battery.charging)
            return "battery-charging";
        if (Battery.pct >= 90)
            return "battery-full";
        if (Battery.pct >= 70)
            return "battery-high";
        if (Battery.pct >= 50)
            return "battery-medium";
        if (Battery.pct >= 30)
            return "battery-low";
        if (Battery.low)
            return "battery-warning";
        return "battery-empty";
    }

    readonly property string timeRemaining: {
        if (!Battery.dev)
            return "";
        if (Battery.full)
            return "Plugged in";
        if (!Battery.hasTime)
            return "Calculating...";
        return Battery.timeStr + (Battery.charging ? " to full" : " remaining");
    }

    width: batteryBackground.width
    height: batteryBackground.height
    visible: Battery.dev !== null
    scale: pressScale

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: batteryBackground

        anchors.centerIn: parent

        width: battery.expanded
            ? 220 * battery.s
            : batteryRow.width + 12 * battery.s

        height: battery.expanded
            ? 105 * battery.s
            : batteryRow.height + 8 * battery.s

        radius: battery.expanded ? 18 * battery.s : height / 2

        color: battery.expanded ? Theme.capsule : "transparent"

        border.width: battery.expanded ? 1 : 0
        border.color: Theme.capsuleBorder

        Behavior on width {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 260
            }
        }

        Behavior on border.width {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: batteryRow

            anchors.centerIn: parent

            spacing: 7 * battery.s

            opacity: battery.expanded ? 0 : 1
            scale: battery.expanded ? 0.8 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                }
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter

                name: battery.icon

                width: 17 * battery.s
                height: 17 * battery.s

                color: Theme.cream

                stroke: 1.8
                opacity: 0.9
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: Battery.pct + "%"

                color: Theme.cream
                opacity: 0.85

                font.family: Theme.font
                font.pixelSize: 12 * battery.s
                font.weight: 600
                font.letterSpacing: 1.3 * battery.s
            }
        }

        Row {
            id: batteryInfo

            anchors.centerIn: parent

            spacing: 18 * battery.s

            opacity: battery.expanded ? 1 : 0
            scale: battery.expanded ? 1 : 0.82

            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 360
                    easing.type: Easing.OutBack
                }
            }

            Item {
                width: 72 * battery.s
                height: 72 * battery.s

                GlyphIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -6 * battery.s

                    name: battery.icon

                    width: 72 * battery.s
                    height: 72 * battery.s

                    color: Theme.cream

                    stroke: 1.8
                    opacity: 0.95
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                spacing: 4 * battery.s

                Text {
                    text: Battery.charging ? "Charging" : "Battery"

                    color: Theme.cream

                    font.family: Theme.font
                    font.pixelSize: 14 * battery.s
                    font.weight: 600
                }

                Text {
                    text: Battery.pct + "%"

                    color: Theme.bright

                    font.family: Theme.font
                    font.pixelSize: 22 * battery.s
                    font.weight: 700
                }

                Text {
                    text: battery.timeRemaining

                    color: Theme.dim

                    font.family: Theme.font
                    font.pixelSize: 11 * battery.s
                    font.weight: 500
                }
            }
        }
    }

    MouseArea {
        anchors.centerIn: parent

        width: parent.width + 30 * battery.s
        height: parent.height + 25 * battery.s

        z: 100

        hoverEnabled: true

        onPressed: battery.pressScale = 0.96
        onReleased: battery.pressScale = 1
        onCanceled: battery.pressScale = 1

        onClicked: battery.expanded = !battery.expanded
    }
}

import QtQuick
import Quickshell.Hyprland

Row {
    property bool animateWorkspaces: true

    spacing: 8

    Repeater {
        model: Hyprland.workspaces.values

        delegate: Rectangle {
            width: modelData.active ? 32 : 22
            height: 20

            color: modelData.active
                ? "#D8647E"
                : "transparent"

            Behavior on width {
                enabled: animateWorkspaces

                NumberAnimation {
                    duration: 250
                    easing.type: Easing.Bezier
                    easing.bezierCurve: [0.16, 1.00, 0.30, 1.00]
                }
            }

            Behavior on color {
                enabled: animateWorkspaces

                ColorAnimation {
                    duration: 120
                    easing.type: Easing.Bezier
                    easing.bezierCurve: [0.15, 0, 0.1, 1]
                }
            }

            Text {
                anchors.centerIn: parent

                text: modelData.id

                color: modelData.active
                    ? "#141415"
                    : "#CDCDCD"

                font.pixelSize: 12

                Behavior on color {
                    enabled: animateWorkspaces

                    ColorAnimation {
                        duration: 150
                        easing.type: Easing.Bezier
                        easing.bezierCurve: [0.5, 0.5, 0.75, 1]
                    }
                }
            }

            MouseArea {
                anchors.fill: parent

                onClicked:
                    Hyprland.dispatch("workspace " + modelData.id)

                onWheel: {
                    Hyprland.dispatch(
                        wheel.angleDelta.y > 0
                            ? "workspace e+1"
                            : "workspace e-1"
                    )
                }
            }
        }
    }
}

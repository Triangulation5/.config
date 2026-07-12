import QtQuick
import Quickshell.Hyprland

Row {
    spacing: 8

    Repeater {
        model: Hyprland.workspaces.values

        delegate: Rectangle {
            width: 22
            height: 20

            color: modelData.active
                ? "#ffffff"
                : "transparent"

            Text {
                anchors.centerIn: parent
                text: modelData.id

                color: modelData.active
                    ? "#000000"
                    : "#ffffff"
            }

            MouseArea {
                anchors.fill: parent

                onClicked:
                    Hyprland.dispatch("workspace " + modelData.id)

                onWheel: {
                    if (wheel.angleDelta.y > 0)
                        Hyprland.dispatch("workspace e+1")
                    else
                        Hyprland.dispatch("workspace e-1")
                }
            }
        }
    }
}

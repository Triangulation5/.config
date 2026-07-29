import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: notch

    visible: true
    color: "transparent"

    WlrLayershell.namespace: "test:notch"
    WlrLayershell.layer: WlrLayer.Top

    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 80

    Item {
        id: notchContainer

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        width: notchBody.width + cornerSize * 2
        height: notchBody.height

        property int cornerSize: 45

        Rectangle {
            id: notchBody

            anchors.centerIn: parent

            width: 220
            height: 45

            color: "#111111"

            // Only bottom corners are rounded
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: 24
            bottomRightRadius: 24

            Text {
                anchors.centerIn: parent

                text: "Notch"
                color: "white"
                font.pixelSize: 18
            }
        }

        // Left ear overlaps the body
        RoundCorner {
            anchors.right: notchBody.left
            anchors.top: notchBody.top

            size: notchContainer.cornerSize

            corner: RoundCorner.CornerEnum.TopRight
            color: "#111111"
        }

        // Right ear overlaps the body
        RoundCorner {
            anchors.left: notchBody.right
            anchors.top: notchBody.top

            size: notchContainer.cornerSize

            corner: RoundCorner.CornerEnum.TopLeft
            color: "#111111"
        }
    }
}

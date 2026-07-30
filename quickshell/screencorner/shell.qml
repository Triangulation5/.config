import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: corners

    visible: true

    color: "transparent"

    WlrLayershell.namespace: "quickshell:screen-corners"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        item: null
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property int cornerSize: 18
    readonly property color cornerColor: "#111111"

    // Top-left outward corner
    RoundCorner {
        anchors.top: parent.top
        anchors.left: parent.left

        size: corners.cornerSize
        corner: RoundCorner.CornerEnum.TopLeft

        color: corners.cornerColor
    }

    // Top-right outward corner
    RoundCorner {
        anchors.top: parent.top
        anchors.right: parent.right

        size: corners.cornerSize
        corner: RoundCorner.CornerEnum.TopRight

        color: corners.cornerColor
    }

    // Bottom-left outward corner
    RoundCorner {
        anchors.bottom: parent.bottom
        anchors.left: parent.left

        size: corners.cornerSize
        corner: RoundCorner.CornerEnum.BottomLeft

        color: corners.cornerColor
    }

    // Bottom-right outward corner
    RoundCorner {
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        size: corners.cornerSize
        corner: RoundCorner.CornerEnum.BottomRight

        color: corners.cornerColor
    }
}

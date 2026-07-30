import QtQuick
import Quickshell
import Quickshell.Wayland
import "Singletons"

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

    readonly property int cornerSize: 16

    // Always match the current pill/lockscreen surface.
    readonly property color cornerColor: Theme.capsule

    Repeater {
        model: [
            {
                h: Qt.AlignLeft,
                v: Qt.AlignTop,
                c: RoundCorner.CornerEnum.TopLeft
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignTop,
                c: RoundCorner.CornerEnum.TopRight
            },
            {
                h: Qt.AlignLeft,
                v: Qt.AlignBottom,
                c: RoundCorner.CornerEnum.BottomLeft
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignBottom,
                c: RoundCorner.CornerEnum.BottomRight
            }
        ]

        delegate: RoundCorner {
            size: corners.cornerSize
            corner: modelData.c
            color: corners.cornerColor

            anchors {
                left: modelData.h === Qt.AlignLeft ? parent.left : undefined
                right: modelData.h === Qt.AlignRight ? parent.right : undefined
                top: modelData.v === Qt.AlignTop ? parent.top : undefined
                bottom: modelData.v === Qt.AlignBottom ? parent.bottom : undefined
            }
        }
    }
}

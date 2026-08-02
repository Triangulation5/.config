import QtQuick
import Quickshell
import Quickshell.Wayland
import "Singletons"

PanelWindow {
    id: corners

    /**
     * Keep the layer alive so the corners can animate away.
     *
     * Visibility is controlled through opacity/scale morphing
     * instead of destroying the surface instantly.
     */
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

    readonly property int cornerSize: 14

    /**
     * Match the pill surface color.
     */
    readonly property color cornerColor: Theme.capsule

    /**
     * Shared state.
     */
    readonly property bool gameMode: Flags.gameMode
    readonly property bool notchStyle: Flags.notchStyle

    /**
     * The corner disappears when either:
     *
     * - game mode activates
     * - notch style is disabled
     *
     * This keeps both transitions using the same morph animation.
     */
    readonly property bool evaporating: gameMode || !notchStyle

    /**
     * Animation tuning.
     */
    readonly property int morphDuration: 1500

    /**
     * Inner bezel shadow only.
     */
    readonly property bool innerShadow: true
    readonly property color innerShadowColor: Qt.rgba(0, 0, 0, 0.28)
    readonly property real innerShadowSize: 8

    Repeater {
        model: [
            {
                h: Qt.AlignLeft,
                v: Qt.AlignTop,
                c: RoundCorner.CornerEnum.TopLeft,
                edge: "topLeft"
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignTop,
                c: RoundCorner.CornerEnum.TopRight,
                edge: "topRight"
            },
            {
                h: Qt.AlignLeft,
                v: Qt.AlignBottom,
                c: RoundCorner.CornerEnum.BottomLeft,
                edge: "bottomLeft"
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignBottom,
                c: RoundCorner.CornerEnum.BottomRight,
                edge: "bottomRight"
            }
        ]

        delegate: RoundCorner {
            id: corner

            size: corners.cornerSize
            corner: modelData.c
            color: corners.cornerColor

            /**
             * Shared collapse animation.
             *
             * Used for both game mode and notch toggle changes.
             */
            evaporating: corners.evaporating
            edgeDirection: modelData.edge
            morphDuration: corners.morphDuration

            /**
             * Inner shadow control.
             */
            innerShadow: corners.innerShadow
            innerShadowColor: corners.innerShadowColor
            innerShadowSize: corners.innerShadowSize

            anchors {
                left: modelData.h === Qt.AlignLeft
                      ? parent.left
                      : undefined

                right: modelData.h === Qt.AlignRight
                       ? parent.right
                       : undefined

                top: modelData.v === Qt.AlignTop
                     ? parent.top
                     : undefined

                bottom: modelData.v === Qt.AlignBottom
                        ? parent.bottom
                        : undefined
            }
        }
    }
}

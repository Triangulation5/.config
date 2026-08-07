import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components.layout

/**
 * Screen corner layer. One overlay PanelWindow paints the four rounded corners
 * over the desktop with RoundCorner, morphing their radius between notch, normal,
 * and game (collapsed) modes and evaporating them in game mode.
 */

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

    /**
     * Corner radius modes.
     *
     * Game mode removes the visible corner.
     *
     * Notch style uses a larger bezel-like rounding.
     *
     * Normal mode keeps a subtle screen corner rounding
     * instead of removing the corners entirely.
     */
    readonly property real notchCornerSize: 12
    readonly property real normalCornerSize: 8
    readonly property real hiddenCornerSize: 0

    /**
     * Shared state.
     */
    readonly property bool gameMode: Flags.gameMode
    readonly property bool notchStyle: Flags.notchStyle

    /**
     * Active corner radius.
     *
     * Priority:
     *
     * 1. Game mode:
     *    corners collapse away.
     *
     * 2. Notch style:
     *    larger bezel-like rounding.
     *
     * 3. Normal:
     *    subtle screen rounding.
     */
    property real cornerSize: gameMode
        ? hiddenCornerSize
        : notchStyle
            ? notchCornerSize
            : normalCornerSize

    Behavior on cornerSize {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    /**
     * Match the pill surface color.
     */
    readonly property color cornerColor: Theme.capsule

    /**
     * The corner disappearance animation.
     *
     * Geometry changes are handled by cornerSize.
     * The RoundCorner component still receives the
     * evaporating state for its collapse animation.
     */
    readonly property bool evaporating: gameMode

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
             * Used for game mode transitions.
             *
             * Notch style changes use corner radius
             * interpolation through cornerSize.
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

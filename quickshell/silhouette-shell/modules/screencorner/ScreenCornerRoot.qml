import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components.layout

/**
 * Screen corner layer. One overlay PanelWindow per monitor paints the four
 * rounded corners over that monitor with RoundCorner, morphing their radius
 * between notch, normal, and collapsed modes. Both things that take the corners
 * away — game mode and the dwm-style bar — take them away the same way, by
 * driving that one radius to zero: see `dissolving`.
 */

Variants {
    id: cornersRoot

    model: Quickshell.screens

    PanelWindow {
        id: corners

        required property var modelData

        screen: modelData

        /**
         * The corners belong to the pill: they are the rounding the notch and the
         * rest pill sit inside, and the radius morph below *is* the pill changing.
         * With the minimal bar across the top edge there is nothing for them to
         * belong to, so switching the bar on takes them away too.
         *
         * The surface is always mapped, exactly as game mode has always left it.
         * A zero radius paints nothing, so there is nothing to gain from dropping
         * the window, and a fullscreen overlay that comes and goes is a second
         * source of flicker at the top edge during the swap.
         */
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
        readonly property real notchCornerSize: Flags.cornerNotchRadius
        readonly property real normalCornerSize: Flags.cornerNormalRadius
        readonly property real hiddenCornerSize: Flags.cornerGameRadius

        /**
         * Shared state.
         */
        readonly property bool gameMode: Flags.gameMode
        readonly property bool notchStyle: Flags.notchStyle

        /**
         * True while nothing on the top edge wants the corners: game mode, or the
         * minimal dwm-style bar.
         *
         * This is the whole of the bar's effect on the corners, and it is
         * deliberately the same condition game mode uses rather than a second,
         * separately timed mechanism. The corners used to fade out and back in on
         * `BarSwap`'s clock, and the return was the wrong shape: fading in draws
         * the corner at its *final* radius and merely fades the weight up, so it
         * arrived as a pop rather than a return. Game mode has never had that
         * problem, because it moves the radius itself and the corner grows back
         * out of the radius it collapsed into.
         *
         * So turning the bar off now plays exactly the motion turning game mode
         * off plays — the same 400ms OutCubic on the same property — and the two
         * cannot drift apart, because they are one condition and one `Behavior`.
         */
        readonly property bool dissolving: corners.gameMode || Flags.barEnabled

        /**
         * Active corner radius.
         *
         * Priority:
         *
         * 1. Dissolved (game mode or the dwm bar):
         *    corners collapse away.
         *
         * 2. Notch style:
         *    larger bezel-like rounding.
         *
         * 3. Normal:
         *    subtle screen rounding.
         */
        property real cornerSize: dissolving
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
        readonly property int morphDuration: Flags.cornerMorphMs

        /**
         * Inner bezel shadow only.
         */
        readonly property bool innerShadow: Flags.cornerShadowSize > 0
        readonly property color innerShadowColor: Qt.rgba(0, 0, 0, 0.28)
        readonly property real innerShadowSize: Flags.cornerShadowSize

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
}

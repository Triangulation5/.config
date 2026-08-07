pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Rest-pill spectrum: one rounded ember bar per cava band, packed into the
 * clock-glyph slot so the cluster never widens the pill. Heights chase
 * Cava.levels with a short ease so the motion stays liquid instead of strobing
 * on every frame cava emits.
 */

Row {
    id: root

    property real s: 1.1
    property real span: 10
    property bool centeredVisualizer: false
    property bool stringVisualizer: false

    height: span * s
    width: stringVisualizer ? 24 * s : Cava.bars * (2.8 * s + 1.4 * s)
    spacing: stringVisualizer ? 0 : 1.8 * s

    Loader {
        active: root.stringVisualizer
        width: root.width
        height: root.height
        visible: root.stringVisualizer
        sourceComponent: musicLineComponent
    }

    Component {
        id: musicLineComponent

        FastMusicLine {
            width: parent.width
            height: parent.height

            /**
             * The string is drawn in a 200×200 coordinate space with its origin
             * at the item's top-left. Scale it down to 0.12·s (≈26px) so it reads
             * as a graceful line balanced against the clock instead of a band
             * that nearly fills the pill, then recentre that footprint inside
             * the slot. The slot (24·s) is exactly the string's width, so there
             * is no dead space shoving the clock right - the gap to the clock
             * matches the bars mode and the string's middle lines up with the
             * clock's.
             */
            transformOrigin: Item.TopLeft
            scale: 0.16 * root.s
            x: (root.width - 280 * scale) / 2
            y: root.height / 2 * (1 - scale)
        }
    }

    Repeater {
        model: root.stringVisualizer ? 0 : Cava.bars

        Rectangle {
            required property int index

            width: 1.8 * root.s
            radius: width / 2

            anchors.verticalCenter: root.centeredVisualizer ? parent.verticalCenter : undefined
            anchors.bottom: root.centeredVisualizer ? undefined : parent.bottom

            height: Math.max(
                2 * root.s,
                (Cava.levels[index] || 0) * root.span * root.s * 1.4
            )

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.flameGlow
                }

                GradientStop {
                    position: 1.0
                    color: Theme.vermLit
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
}

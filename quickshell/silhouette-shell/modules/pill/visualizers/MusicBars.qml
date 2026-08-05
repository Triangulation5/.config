pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

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
    width: stringVisualizer ? 80 * s : Cava.bars * (2.8 * s + 1.4 * s)
    spacing: stringVisualizer ? 0 : 1.8 * s
    y: 2 * s

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
            x: -18 * root.s
            y: -0.8 * root.s
            scale: 0.15 * root.s
            transformOrigin: Item.Center
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

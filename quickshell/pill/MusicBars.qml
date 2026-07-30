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

    property real s: 1.1 // Global scale multiplier. Increase to make the entire visualizer larger.
    property real span: 10 // Maximum height range of the Cava bars. Increase for taller reactions.
    property bool centeredVisualizer: false // true = bars grow from the center, false = bars grow from the bottom.

    property bool stringVisualizer: true // true = use FastMusicLine strings, false = use normal Cava bars.

    // Overall visualizer height.
    height: span * s
    // String mode width; normal mode width is based on number of Cava bars.
    width: stringVisualizer ? 80 * s : Cava.bars * (1.8 * s + 1.4 * s)

    // Space between bars in normal mode. String mode has no bar spacing.
    spacing: stringVisualizer ? 0 : 1.4 * s
    // Vertical offset inside the pill.
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

            x: -18 * root.s // Moves the string visualizer left/right.
            y: -0.8 * root.s // Moves the string visualizer vertically.
            scale: 0.12 // Controls string thickness/size.
            transformOrigin: Item.Center
        }
    }


    Repeater {
        // Disable normal bars when string visualizer is enabled.
        model: root.stringVisualizer ? 0 : Cava.bars

        Rectangle {
            required property int index

            // Controls bar thickness.
            width: 1.8 * root.s
            // Makes bars rounded.
            radius: width / 2

            // Controls whether bars expand from center or bottom.
            anchors.verticalCenter: root.centeredVisualizer ? parent.verticalCenter : undefined
            anchors.bottom: root.centeredVisualizer ? undefined : parent.bottom

            // Controls bar reaction height.
            // Increase 1.4 for stronger/larger movement.
            height: Math.max(
                2 * root.s,
                (Cava.levels[index] || 0)
                * root.span
                * root.s
                * 1.4
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

            // Smooths Cava movement instead of instant jumps.
            Behavior on height {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
}

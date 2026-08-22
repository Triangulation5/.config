pragma ComponentBehavior: Bound

import QtQuick

/**
 * Pulse: a reusable breathing wrapper. Drop any content inside and it eases
 * between `minScale` and `maxScale` over `duration` on an infinite in-out sine,
 * scaling around the item's centre. Used by the Face ID glyph's idle breath and
 * reusable for any "alive" indicator that should swell and settle.
 */
Item {
    id: root

    property real minScale: 0.96
    property real maxScale: 1.04
    property int duration: 1600
    property bool running: true

    property real scale: 1

    SequentialAnimation on scale {
        running: root.running
        loops: Animation.Infinite

        NumberAnimation { from: root.minScale; to: root.maxScale; duration: root.duration / 2; easing.type: Easing.InOutSine }
        NumberAnimation { from: root.maxScale; to: root.minScale; duration: root.duration / 2; easing.type: Easing.InOutSine }
    }

    transform: Scale {
        xScale: root.scale
        yScale: root.scale
        origin.x: root.width / 2
        origin.y: root.height / 2
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.animation

/**
 * FaceIdOrbit: the orbiting particle ring that appears during the scanning
 * phase. Radius is animated by the owner (FaceIdUnlock) — it grows to full size
 * while scanning and collapses back to the centre on success, with the shared
 * Orbit component supplying the continuous rotation.
 */
Item {
    id: root

    property real s: 1.1
    property color color: Theme.flameGlow
    property real radius: 0

    Behavior on radius { NumberAnimation { duration: Motion.shapeshift; easing.type: Easing.OutCubic } }

    Orbit {
        anchors.centerIn: parent
        radius: root.radius
        speed: 1.1
        count: 8
        particleSize: 4 * root.s
        color: root.color
        running: root.radius > 1
        opacity: root.radius > 1 ? 1 : 0
    }
}

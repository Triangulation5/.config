pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Small pulsing flame dot — the busy indicator shown while a wifi network
 * connects or a bluetooth device pairs. Runs the shared Motion.pulse opacity
 * loop while `running`; callers control visibility themselves.
 */
Rectangle {
    id: dot

    property real s: 1.1
    property bool running: true

    width: 4 * dot.s
    height: 4 * dot.s
    radius: width / 2
    color: Theme.flameGlow

    SequentialAnimation on opacity {
        running: dot.running
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
    }
}

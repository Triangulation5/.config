pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Small flame-glow dot over a soft halo — the unread marker used by the Link
 * header badge and unread notification titles. Property `s` controls the scale
 * (typically inherited from the root surface).
 */
Item {
    id: ember

    property real s: 1.1
    property real size: 4 * s

    width: size * 2.2
    height: size * 2.2

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: width / 2
        color: Theme.flameGlow
        opacity: 0.22
    }

    Rectangle {
        anchors.centerIn: parent
        width: ember.size
        height: ember.size
        radius: width / 2
        color: Theme.flameGlow
    }
}

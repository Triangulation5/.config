pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.animation

/**
 * FaceIdGlyph: the Face ID outline (a rounded face with eyes and a smile) that
 * sits over the live feed. Breathing is delegated to the shared Pulse wrapper,
 * so this component is just the static artwork plus its tint; FaceIdUnlock
 * decides when it breathes and what colour it takes.
 */
Item {
    id: root

    property real s: 1.1
    property color color: Theme.cream
    property bool breathing: false

    Pulse {
        anchors.fill: parent
        running: root.breathing
        minScale: 0.97
        maxScale: 1.03
        duration: 1800

        GlyphIcon {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            name: "faceid"
            color: root.color
            stroke: 1.8
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Icon button: a GlyphIcon whose hover area extends `hitPad` beyond the glyph
 * and whose color swaps to `hoverColor` while hovered. `hovered` is exposed so
 * callers can style siblings off the same state (fade a label in, tint a
 * badge); the action goes through `clicked`. Purely visual and stateless, so
 * any number of surfaces can share one.
 */
Item {
    id: root

    property string name: ""
    property color color: Theme.dim
    property color hoverColor: Theme.cream
    property real stroke: 1.8
    /** How far the click target extends past the glyph, in px. */
    property real hitPad: 6

    readonly property bool hovered: area.containsMouse
    signal clicked()

    GlyphIcon {
        anchors.fill: parent
        name: root.name
        color: root.hovered ? root.hoverColor : root.color
        stroke: root.stroke
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -root.hitPad
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

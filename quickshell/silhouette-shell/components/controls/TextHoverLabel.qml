pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Text hover label: a Text that lights on hover with a fat, invisible hit area
 * (negative margins) so small affordances like a dismiss ✕ are easy to click.
 * The component IS a Text, so font styling passes straight through. Emits
 * `clicked`; `hoverColor`/`idleColor` drive the light, `hitMargins` controls
 * the hit-area expansion, and `hitEnabled` gates the area (e.g. a dismiss that
 * only works while its row is hovered).
 */
Text {
    id: label

    property real s: 1.1
    property color hoverColor: Theme.cream
    property color idleColor: Theme.dim
    property real hitMargins: -6 * s
    property bool hitEnabled: true

    signal clicked()

    color: hitArea.containsMouse ? label.hoverColor : label.idleColor
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    MouseArea {
        id: hitArea
        anchors.fill: parent
        anchors.margins: label.hitMargins
        hoverEnabled: true
        enabled: label.hitEnabled
        cursorShape: Qt.PointingHandCursor
        onClicked: label.clicked()
    }
}

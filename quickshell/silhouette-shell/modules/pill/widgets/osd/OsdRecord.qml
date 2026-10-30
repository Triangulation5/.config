pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.pill.widgets.osd

/**
 * Record OSD face: a pulsing record dot and a started/stopped line. Driven by
 * the Osd root through `active` and `recordStarted`.
 */
OsdFace {
    id: face

    property bool recordStarted: false

    Rectangle {
        id: recGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 13 * face.s
        height: 13 * face.s
        radius: width / 2
        color: face.recordStarted ? Theme.verm : Theme.dim

        SequentialAnimation on opacity {
            running: face.recordStarted && face.active
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
        }
    }

    Text {
        anchors.left: recGlyph.right
        anchors.leftMargin: 13 * face.s
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: face.recordStarted ? "Recording started" : "Recording stopped"
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 11.5 * face.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        maximumLineCount: 1
    }
}

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
        id: recordContainer
        visible: Theme.material
        anchors.left: parent.left
        anchors.leftMargin: 4 * face.s
        anchors.verticalCenter: parent.verticalCenter
        width: 38 * face.s
        height: width
        radius: 14 * face.s
        color: face.recordStarted ? Qt.alpha(Theme.error, 0.16) : Theme.surfaceContainerHigh
    }

    Rectangle {
        id: recGlyph
        anchors.left: Theme.material ? undefined : parent.left
        anchors.centerIn: Theme.material ? recordContainer : undefined
        anchors.verticalCenter: parent.verticalCenter
        width: (Theme.material ? 12 : 13) * face.s
        height: 13 * face.s
        radius: width / 2
        color: Theme.material
            ? (face.recordStarted ? Theme.error : Theme.onSurfaceVariant)
            : (face.recordStarted ? Theme.verm : Theme.dim)

        SequentialAnimation on opacity {
            running: face.recordStarted && face.active
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
        }
    }

    Text {
        anchors.left: Theme.material ? recordContainer.right : recGlyph.right
        anchors.leftMargin: 13 * face.s
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: face.recordStarted ? "Recording started" : "Recording stopped"
        color: Theme.material ? Theme.onSurface : Theme.cream
        font.family: Theme.font
        font.pixelSize: 11.5 * face.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        maximumLineCount: 1
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Binary segmented-toggle chip. Two adjacent rounded pills: left ("off") and
 * right ("on"). The host binds `on` to toggle state and handles `clicked` to
 * flip it.
 *
 * @property label  Display text for the chip
 * @property on     Whether this chip is the selected side
 * @property corner -1 for left edge, 1 for right edge (handles border-radius welding)
 * @signal  clicked()  Emitted when the chip is tapped
 */
Rectangle {
    id: seg

    property string label: ""
    property bool on: false
    property int corner: 0

    signal clicked()

    width: segText.implicitWidth + 18 * root.s
    height: 24 * root.s
    radius: 7 * root.s
    topLeftRadius: corner === -1 ? radius : 0
    bottomLeftRadius: corner === -1 ? radius : 0
    topRightRadius: corner === 1 ? radius : 0
    bottomRightRadius: corner === 1 ? radius : 0
    color: seg.on ? Qt.alpha(Theme.vermLit, 0.20) : Theme.frameBg
    border.width: 1
    border.color: seg.on ? Qt.alpha(Theme.vermLit, 0.55) : Theme.hairSoft
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: segText
        anchors.centerIn: parent
        text: seg.label
        color: seg.on ? Theme.bright : Theme.dim
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: seg.on ? Font.DemiBold : Font.Medium
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: seg.clicked()
    }
}

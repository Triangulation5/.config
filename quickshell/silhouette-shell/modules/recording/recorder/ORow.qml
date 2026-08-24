pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One options-drawer line: a cream label on the left and a control pushed to
 * the right, capped by a top hairline on every row but the first.
 */
Item {
    id: orow

    property real s: 1.1
    property string name: ""
    property bool first: false
    default property alias control: controlSlot.data

    width: parent ? parent.width : 0
    height: 35 * s

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hairSoft
        visible: !orow.first
    }

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: orow.name
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 12 * s
        font.weight: Font.DemiBold
    }

    Item {
        id: controlSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}

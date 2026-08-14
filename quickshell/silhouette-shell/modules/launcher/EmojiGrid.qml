pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls

/**
 * Launcher emoji mode: a scrollable grid of emoji cells with keyboard-following
 * highlight, plus a floating name label bar at the bottom (which turns into a
 * "Copied!" flash after the pick). All results and selection state live on the
 * launcher surface (`host`).
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    GridView {
        id: emojiGrid
        visible: host.emojiActive
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: 40 * root.s
        cellHeight: 40 * root.s
        model: host.emojiResults.length
        currentIndex: host.selectedIndex

        delegate: Rectangle {
            required property int index
            width: emojiGrid.cellWidth - 2 * root.s
            height: emojiGrid.cellHeight - 2 * root.s
            radius: 8 * root.s
            color: index === host.selectedIndex ? Theme.frameBg : (emoArea.containsMouse ? Qt.rgba(0.94, 0.88, 0.84, 0.04) : "transparent")
            border.width: index === host.selectedIndex ? 1 : 0
            border.color: Theme.frameBorder

            readonly property var emoji: host.emojiResults[index]

            Text {
                anchors.centerIn: parent
                text: parent.emoji ? parent.emoji.e : ""
                font.pixelSize: 22 * root.s
            }

            MouseArea {
                id: emoArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    host.selectedIndex = index;
                    host.copyEmoji();
                }
                onEntered: host.selectedIndex = index
            }
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: emojiGrid
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        width: nameLabel.implicitWidth + 20 * root.s
        height: visible ? 22 * root.s : 0
        radius: 6 * root.s
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: host.emojiActive && host.emojiResults.length > 0 && host.selectedIndex < host.emojiResults.length

        Text {
            id: nameLabel
            anchors.centerIn: parent
            text: host.emojiCopied ? "Copied!" : (host.emojiResults[host.selectedIndex] ? host.emojiResults[host.selectedIndex].n : "")
            color: host.emojiCopied ? Theme.vermLit : Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }
    }
}

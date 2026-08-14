pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls
import qs.components.icons

/**
 * Device list for the Localsend surface: Link-surface-style rows with a
 * selected highlight and a Send chip on the focused row. Owns its own
 * scroll; `sendTo(index)` fires when a row is clicked.
 */
Item {
    id: list

    property real s: 1.1
    property var devices: []
    property int selectedIndex: -1
    property bool sendEnabled: false
    property bool sending: false
    property bool scanning: false

    signal sendTo(int index)

    ListView {
        id: devList
        width: parent.width
        height: count > 0 ? Math.min(count * 54 * list.s + (count - 1) * 4 * list.s, 280 * list.s) : 0
        visible: height > 0 && !list.scanning
        spacing: 4 * list.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: list.devices.length
        interactive: count * 54 * list.s > 280 * list.s

        delegate: Rectangle {
            id: devRow
            required property int index
            width: devList.width
            height: 54 * list.s
            radius: 10 * list.s
            color: index === list.selectedIndex ? Theme.frameBg
                : (devArea.containsMouse ? Qt.rgba(1, 1, 1, 0.035) : "transparent")
            border.width: index === list.selectedIndex ? 1 : 0
            border.color: index === list.selectedIndex ? Theme.frameBorder : "transparent"

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            readonly property var dev: list.devices[index]

            MouseArea {
                id: devArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onEntered: list.selectedIndex = index
                onClicked: list.sendTo(index)
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12 * list.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * list.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18 * list.s; height: 18 * list.s
                    name: "smartphone"
                    color: index === list.selectedIndex ? Theme.cream : Theme.iconDim
                    stroke: 2
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3 * list.s

                    Text {
                        text: devRow.dev.name || devRow.dev.hostname || devRow.dev.alias || "Unknown device"
                        color: index === list.selectedIndex ? Theme.cream : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 12.5 * list.s
                        font.weight: index === list.selectedIndex ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        width: devList.width - 140 * list.s
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        visible: (devRow.dev.hostname || devRow.dev.ip || devRow.dev.model || "").length > 0
                        text: devRow.dev.model
                            || (devRow.dev.hostname && devRow.dev.ip ? devRow.dev.hostname + " · " + devRow.dev.ip
                            : (devRow.dev.hostname || devRow.dev.ip || ""))
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * list.s
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: devList.width - 140 * list.s
                    }
                }
            }

            /** Send action chip — aligned right on selected row. */
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 12 * list.s
                anchors.verticalCenter: parent.verticalCenter
                visible: list.sendEnabled && index === list.selectedIndex
                width: sendPillText.implicitWidth + 20 * list.s
                height: 28 * list.s
                radius: 14 * list.s
                color: list.sending ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.94, 0.55, 0.38, 0.14)
                border.width: 1
                border.color: list.sending ? Theme.frameBorder : Qt.rgba(0.94, 0.55, 0.38, 0.22)

                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: sendPillText
                    anchors.centerIn: parent
                    text: list.sending ? "…" : "Send"
                    color: list.sending ? Theme.subtle : Theme.flameGlow
                    font.family: Theme.font
                    font.pixelSize: 11 * list.s
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: devList
        s: list.s
        flick: devList
        visible: height > 0 && devList.interactive
    }
}

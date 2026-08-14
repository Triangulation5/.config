pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.components.layout
import qs.components.icons
import qs.components.controls

/**
 * Bluetooth device list for the link surface: empty/scanning placeholder,
 * scrollable device rows, and the connect/forget confirm strip. All device
 * state and actions live on the host surface (`host`); this view renders the
 * list and forwards rows to it.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    height: host.devices.length > 0 ? Math.min(devCol.implicitHeight, 200 * root.s) : 24 * root.s

    Text {
        visible: host.devices.length === 0
        anchors.centerIn: parent
        text: host.discovering ? "Scanning…" : "No devices found"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Flickable {
        id: devFlick
        visible: host.devices.length > 0
        anchors.fill: parent
        contentHeight: devCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: devCol
            width: devFlick.width
            spacing: 2 * root.s

            Repeater {
                model: host.devicesSorted

                Column {
                    id: devItem
                    required property var modelData
                    required property int index
                    readonly property bool isConnected: modelData ? modelData.connected === true : false
                    readonly property bool isPaired: modelData ? modelData.paired === true : false
                    readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
                    readonly property bool pairing: addr.length > 0 && host.pairingAddress === addr
                    readonly property bool failed: addr.length > 0 && host.failedAddress === addr
                    readonly property bool busy: (modelData && typeof BluetoothDeviceState !== "undefined")
                        ? (modelData.state === BluetoothDeviceState.Connecting
                            || modelData.state === BluetoothDeviceState.Disconnecting)
                        : false
                    readonly property bool confirming: addr.length > 0 && host.expandedAddress === addr
                    readonly property bool focused: host.kbIndex === index
                    readonly property bool focusPrimary: host.confirmFocus === 0
                    readonly property bool focusForget: host.confirmFocus === 1
                    readonly property int battery: host.batteryLevel(modelData)
                    width: devCol.width
                    spacing: 2 * root.s

                    /**
                     * Keep the keyboard-focused (or just-expanded) row in
                     * view when the list overflows its fixed-height frame.
                     * `mapToItem` gives viewport coords, so scroll by the
                     * deficit against the visible bounds.
                     */
                    function ensureVisible() {
                        var y = devItem.mapToItem(devFlick, 0, 0).y;
                        var h = devItem.height;
                        if (y < 0)
                            devFlick.contentY += y;
                        else if (y + h > devFlick.height)
                            devFlick.contentY += y + h - devFlick.height;
                    }
                    onFocusedChanged: if (focused) Qt.callLater(devItem.ensureVisible)
                    onConfirmingChanged: if (confirming) Qt.callLater(devItem.ensureVisible)

                    Rectangle {
                        width: parent.width
                        height: 38 * root.s
                        radius: 9 * root.s
                        color: rowHover.hovered || devItem.focused ? Theme.frameBg : "transparent"

                        HoverHandler {
                            id: rowHover
                            onHoveredChanged: if (hovered) host.kbIndex = devItem.index
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.activateDevice(devItem.modelData)
                        }

                        Rectangle {
                            id: devTile
                            anchors.left: parent.left
                            anchors.leftMargin: 6 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26 * root.s
                            height: 26 * root.s
                            radius: 8 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.border

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 15 * root.s
                                height: 15 * root.s
                                name: "bluetooth"
                                color: devItem.isConnected ? Theme.vermLit : Theme.iconDim
                                stroke: 1.7
                            }
                        }

                        Column {
                            anchors.left: devTile.right
                            anchors.leftMargin: 10 * root.s
                            anchors.right: devRight.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1 * root.s

                            Text {
                                width: parent.width
                                text: devItem.modelData ? (devItem.modelData.deviceName || devItem.modelData.name || "Unknown") : "Unknown"
                                color: devItem.isConnected ? Theme.cream : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: devItem.isConnected ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: host.metaFor(devItem.modelData)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: devRight
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * root.s

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: devItem.pairing || devItem.busy
                                width: 4 * root.s
                                height: 4 * root.s
                                radius: width / 2
                                color: Theme.flameGlow

                                SequentialAnimation on opacity {
                                    running: devItem.pairing || devItem.busy
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                }
                            }

                            Filament {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: devItem.isConnected && devItem.battery >= 0
                                s: root.s
                                kind: "battery"
                                level: Math.max(0, devItem.battery) / 100
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !devItem.isPaired && !devItem.pairing
                                radius: 999
                                color: pairArea.containsMouse ? Theme.frameBg : Theme.tileBg
                                border.width: 1
                                border.color: pairArea.containsMouse ? Theme.vermDim : Theme.border
                                height: 18 * root.s
                                width: pairText.implicitWidth + 16 * root.s
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                                Text {
                                    id: pairText
                                    anchors.centerIn: parent
                                    text: "Pair"
                                    color: pairArea.containsMouse ? Theme.cream : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 9.5 * root.s
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: pairArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: host.activateDevice(devItem.modelData)
                                }
                            }
                        }
                    }

                    Item {
                        visible: devItem.confirming
                        width: parent.width
                        height: 30 * root.s

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10 * root.s
                            anchors.right: confirmBtns.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: devItem.isConnected ? "Connected" : "Paired"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Row {
                            id: confirmBtns
                            anchors.right: parent.right
                            anchors.rightMargin: 10 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6 * root.s

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: primaryLabel.implicitWidth + 20 * root.s
                                height: 22 * root.s
                                radius: 7 * root.s
                                color: (primaryArea.containsMouse || devItem.focusPrimary) ? Theme.tileBg : "transparent"
                                border.width: 1
                                border.color: (primaryArea.containsMouse || devItem.focusPrimary) ? Theme.vermDim : Theme.border

                                Text {
                                    id: primaryLabel
                                    anchors.centerIn: parent
                                    text: devItem.isConnected ? "Disconnect" : "Connect"
                                    color: Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.3 * root.s
                                }

                                MouseArea {
                                    id: primaryArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: devItem.isConnected
                                        ? host.disconnectDevice(devItem.modelData)
                                        : host.connectDevice(devItem.modelData)
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: forgetLabel.implicitWidth + 20 * root.s
                                height: 22 * root.s
                                radius: 7 * root.s
                                color: (forgetArea.containsMouse || devItem.focusForget)
                                    ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.2)
                                    : Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.45)

                                Text {
                                    id: forgetLabel
                                    anchors.centerIn: parent
                                    text: "Forget"
                                    color: Theme.vermLit
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.3 * root.s
                                }

                                MouseArea {
                                    id: forgetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: host.forgetDevice(devItem.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        visible: devItem.failed
                        text: "Pairing failed"
                        color: Theme.vermLit
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        leftPadding: 42 * root.s
                    }
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: parent
        s: root.s
        flick: devFlick
    }
}

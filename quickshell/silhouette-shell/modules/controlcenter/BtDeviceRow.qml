pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.components.animation
import qs.components.layout
import qs.components.icons
import qs.components.controls

/**
 * Single device row for the bluetooth drill-in's list, carrying every state a
 * row can show: plain, pairing ember, inline confirm (disconnect/connect +
 * forget) and the transient failure line. Pure view — the list state comes in
 * as props and every action goes back out as a signal, so delegates keep
 * their identity across scans without owning any device logic.
 */
Column {
    id: dev

    required property var modelData
    required property int index

    property real s: 1.1
    property bool expanded: false
    property bool focused: false
    property int confirmFocus: -1
    property bool pairing: false
    property bool failed: false
    property int battery: -1
    property string meta: ""
    /** The list frame, for scroll-into-view on focus/expansion. */
    property var list: null

    readonly property bool isConnected: modelData ? modelData.connected === true : false
    readonly property bool isPaired: modelData ? modelData.paired === true : false
    readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
    readonly property bool busy: (modelData && typeof BluetoothDeviceState !== "undefined")
        ? (modelData.state === BluetoothDeviceState.Connecting
            || modelData.state === BluetoothDeviceState.Disconnecting)
        : false
    readonly property bool confirming: expanded
    readonly property bool focusPrimary: confirmFocus === 0
    readonly property bool focusForget: confirmFocus === 1

    signal requestActivate()
    signal requestConnect()
    signal requestDisconnect()
    signal requestForget()
    signal requestFocus()

    width: parent ? parent.width : 0
    spacing: 2 * s

    /**
     * The confirm row's text stays invisible until the shared 100ms delay
     * after the row expands, so the expand reads as one motion instead of
     * text popping in mid-animation.
     */
    RevealLatch {
        id: confirmReveal
        shown: dev.confirming
    }
    onExpandedChanged: if (expanded) Qt.callLater(dev.ensureVisible)
    onFocusedChanged: if (focused) Qt.callLater(dev.ensureVisible)

    /** Keep the keyboard-focused (or just-expanded) row in view. */
    function ensureVisible() {
        if (dev.list)
            dev.list.ensureVisible(dev);
    }

    Rectangle {
        width: parent.width
        height: 38 * dev.s
        radius: 9 * dev.s
        color: rowHover.hovered || dev.focused ? Theme.frameBg : "transparent"

        HoverHandler {
            id: rowHover
            onHoveredChanged: if (hovered) dev.requestFocus()
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dev.requestActivate()
        }

        Rectangle {
            id: devTile
            anchors.left: parent.left
            anchors.leftMargin: 6 * dev.s
            anchors.verticalCenter: parent.verticalCenter
            width: 26 * dev.s
            height: 26 * dev.s
            radius: 8 * dev.s
            color: Theme.tileBg
            border.width: 1
            border.color: Theme.border

            GlyphIcon {
                anchors.centerIn: parent
                width: 15 * dev.s
                height: 15 * dev.s
                name: "bluetooth"
                color: dev.isConnected ? Theme.vermLit : Theme.iconDim
                stroke: 1.7
            }
        }

        Column {
            anchors.left: devTile.right
            anchors.leftMargin: 10 * dev.s
            anchors.right: devRight.left
            anchors.rightMargin: 8 * dev.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * dev.s

            Text {
                width: parent.width
                text: dev.modelData ? (dev.modelData.deviceName || dev.modelData.name || "Unknown") : "Unknown"
                color: dev.isConnected ? Theme.cream : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11.5 * dev.s
                font.weight: dev.isConnected ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: dev.meta
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * dev.s
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Row {
            id: devRight
            anchors.right: parent.right
            anchors.rightMargin: 8 * dev.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * dev.s

            PulseDot {
                anchors.verticalCenter: parent.verticalCenter
                visible: dev.pairing || dev.busy
                s: dev.s
                running: dev.pairing || dev.busy
            }

            Filament {
                anchors.verticalCenter: parent.verticalCenter
                visible: dev.isConnected && dev.battery >= 0
                s: dev.s
                kind: "battery"
                level: Math.max(0, dev.battery) / 100
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !dev.isPaired && !dev.pairing
                radius: 999
                color: pairArea.containsMouse ? Theme.frameBg : Theme.tileBg
                border.width: 1
                border.color: pairArea.containsMouse ? Theme.vermDim : Theme.border
                height: 18 * dev.s
                width: pairText.implicitWidth + 16 * dev.s
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: pairText
                    anchors.centerIn: parent
                    text: "Pair"
                    color: pairArea.containsMouse ? Theme.cream : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * dev.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: pairArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dev.requestActivate()
                }
            }
        }
    }

    Item {
        visible: dev.confirming
        width: parent.width
        height: 30 * dev.s
        opacity: confirmReveal.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 * dev.s
            anchors.right: confirmBtns.left
            anchors.rightMargin: 8 * dev.s
            anchors.verticalCenter: parent.verticalCenter
            text: dev.isConnected ? "Connected" : "Paired"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * dev.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Row {
            id: confirmBtns
            anchors.right: parent.right
            anchors.rightMargin: 10 * dev.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * dev.s

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                s: dev.s
                text: dev.isConnected ? "Disconnect" : "Connect"
                focused: dev.focusPrimary
                onClicked: dev.isConnected ? dev.requestDisconnect() : dev.requestConnect()
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                s: dev.s
                text: "Forget"
                kind: "danger"
                focused: dev.focusForget
                onClicked: dev.requestForget()
            }
        }
    }

    Text {
        visible: dev.failed
        text: "Pairing failed"
        color: Theme.vermLit
        font.family: Theme.font
        font.pixelSize: 9.5 * dev.s
        leftPadding: 42 * dev.s
    }
}

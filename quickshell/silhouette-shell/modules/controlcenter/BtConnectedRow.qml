pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.components.animation
import qs.components.layout
import qs.components.icons
import qs.components.controls

/**
 * Connected-peripheral row for the bluetooth drill-in's CONNECTED block. Taller
 * than a nearby row, with a full-width battery thread fed by Peripherals
 * (BlueZ keeps Battery1 behind Experimental, so UPower is the source), the
 * charging bolt and the same inline disconnect/forget confirm. A row with no
 * Bluetooth device behind it is a USB-dongle peripheral: display-only, tagged
 * USB, no confirm. Pure view — state comes in as props and actions go back out
 * as signals, so delegates keep their identity across scans.
 */
Column {
    id: con

    required property var modelData
    required property int index

    property real s: 1.1
    property bool expanded: false
    property bool focused: false
    property int confirmFocus: -1
    property var list: null
    /** All of it straight off the peripheral model row: charge, power, kind, tag. */
    property int level: -1
    property bool onPower: false
    property bool pending: false
    property string tag: ""
    property string glyph: "bluetooth"
    property string name: "Unknown"
    property string stateLabel: ""

    readonly property var bt: modelData ? modelData.bt : null
    readonly property var up: modelData ? modelData.up : null
    readonly property bool isUsb: bt === null
    readonly property string addr: (bt && bt.address) ? bt.address : ""
    readonly property bool hasBattery: level >= 0
    readonly property bool low: hasBattery && !onPower && level <= Peripherals.lowAt
    readonly property bool busy: (bt && typeof BluetoothDeviceState !== "undefined")
        ? bt.state === BluetoothDeviceState.Disconnecting
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

    /** The confirm row fades in one beat after expanding, like the nearby rows. */
    RevealLatch {
        id: confirmReveal
        shown: con.confirming
    }
    onExpandedChanged: if (expanded) Qt.callLater(con.ensureVisible)
    onFocusedChanged: if (focused) Qt.callLater(con.ensureVisible)

    /** Keep the keyboard-focused (or just-expanded) row in view. */
    function ensureVisible() {
        if (con.list)
            con.list.ensureVisible(con);
    }

    Rectangle {
        width: parent.width
        height: 50 * con.s
        radius: 10 * con.s
        color: ((rowHover.hovered && !con.isUsb) || con.focused) ? Theme.frameBg : "transparent"

        HoverHandler {
            id: rowHover
            onHoveredChanged: if (hovered) con.requestFocus()
        }

        MouseArea {
            anchors.fill: parent
            enabled: !con.isUsb
            cursorShape: Qt.PointingHandCursor
            onClicked: con.requestActivate()
        }

        Rectangle {
            id: conTile
            anchors.left: parent.left
            anchors.leftMargin: 6 * con.s
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * con.s
            height: 32 * con.s
            radius: 9 * con.s
            color: Theme.tileBg
            border.width: 1
            border.color: con.low ? Qt.alpha(Theme.vermLit, 0.55) : Theme.border

            GlyphIcon {
                anchors.centerIn: parent
                width: 17 * con.s
                height: 17 * con.s
                name: con.glyph
                color: Theme.vermLit
                stroke: 1.7
            }
        }

        Item {
            anchors.left: conTile.right
            anchors.leftMargin: 11 * con.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * con.s
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8 * con.s
            anchors.bottomMargin: 10 * con.s

            Row {
                id: nameRow
                anchors.left: parent.left
                anchors.right: conRight.left
                anchors.rightMargin: 8 * con.s
                anchors.top: parent.top
                spacing: 6 * con.s

                Text {
                    id: conName
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, nameRow.width - (usbTag.visible ? usbTag.width + nameRow.spacing : 0))
                    text: con.name
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * con.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: usbTag
                    anchors.verticalCenter: parent.verticalCenter
                    visible: con.tag.length > 0
                    width: usbLabel.implicitWidth + 8 * con.s
                    height: 13 * con.s
                    radius: 4 * con.s
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.hair

                    Text {
                        id: usbLabel
                        anchors.centerIn: parent
                        text: con.tag
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 7.5 * con.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1 * con.s
                    }
                }
            }

            Row {
                id: conRight
                anchors.right: parent.right
                anchors.verticalCenter: nameRow.verticalCenter
                spacing: 5 * con.s

                PulseDot {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: con.busy
                    s: con.s
                    running: con.busy
                }

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    /** On power, not merely charging: a pack held at its limit is plugged in too. */
                    visible: con.onPower
                    width: 10 * con.s
                    height: 10 * con.s
                    name: "bolt"
                    color: Theme.flameGlow
                    stroke: 2
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: con.hasBattery
                    text: con.level + "%"
                    color: con.low ? Theme.vermLit : (con.onPower ? Theme.flameGlow : Theme.subtle)
                    font.family: Theme.font
                    font.pixelSize: 11 * con.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            Filament {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: con.hasBattery
                s: con.s
                kind: "battery"
                level: Math.max(0, con.level) / 100
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -2 * con.s
                visible: !con.hasBattery
                text: "No battery reading"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * con.s
                font.weight: Font.Medium
            }
        }
    }

    /**
     * Inline confirm under a connected device: Disconnect plus Forget, keyed by
     * the shared expandedRow the nearby rows use.
     */
    Item {
        visible: con.confirming
        width: parent.width
        height: 30 * con.s
        opacity: confirmReveal.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 * con.s
            anchors.right: confirmBtns.left
            anchors.rightMargin: 8 * con.s
            anchors.verticalCenter: parent.verticalCenter
            text: con.stateLabel.length > 0 ? con.stateLabel : "Connected"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * con.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Row {
            id: confirmBtns
            anchors.right: parent.right
            anchors.rightMargin: 10 * con.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * con.s

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                s: con.s
                text: "Disconnect"
                focused: con.focusPrimary
                onClicked: con.requestDisconnect()
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                s: con.s
                text: "Forget"
                kind: "danger"
                focused: con.focusForget
                onClicked: con.requestForget()
            }
        }
    }
}

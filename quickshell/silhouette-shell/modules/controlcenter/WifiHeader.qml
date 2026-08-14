pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking
import qs.services
import qs.components.icons

/**
 * Wifi drill-in header: back chevron, WIFI title with live status text, the
 * scan/reload spinner, and the adapter enable toggle. All state and actions
 * live on the host surface (`host`).
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    height: 24 * root.s

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * root.s

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s

            GlyphIcon {
                anchors.fill: parent
                name: "chevron-left"
                color: backArea.containsMouse ? Theme.cream : Theme.iconDim
                stroke: 1.8
            }

            MouseArea {
                id: backArea
                anchors.fill: parent
                anchors.margins: -6 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: host.back()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "WIFI"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * root.s
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "· " + host.statusText
            color: host.activeNet ? Theme.vermLit : Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12 * root.s

        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: host.wifiOn
            width: 16 * root.s
            height: 16 * root.s

            GlyphIcon {
                id: reloadGlyph
                anchors.fill: parent
                name: "reboot"
                color: host.scanning ? Theme.flameGlow : (reloadArea.containsMouse ? Theme.cream : Theme.iconDim)
                stroke: 1.8

                RotationAnimator {
                    target: reloadGlyph
                    running: host.scanning
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) reloadGlyph.rotation = 0
                }
            }

            MouseArea {
                id: reloadArea
                anchors.fill: parent
                anchors.margins: -6 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: host.scanning ? host.stopScan() : host.startScan()
            }
        }

        LinkToggle {
            s: root.s
            anchors.verticalCenter: parent.verticalCenter
            on: host.wifiOn
            onToggled: {
                if (typeof Networking !== "undefined" && Networking)
                    Networking.wifiEnabled = !Networking.wifiEnabled;
            }
        }
    }
}

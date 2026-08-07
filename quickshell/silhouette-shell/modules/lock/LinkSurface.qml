pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.services
import qs.components.icons

/**
 * Lock screen connectivity glance. A compact capsule shows the wifi network (or
 * Bluetooth/offline state) and expands on click into rows with wifi and bluetooth
 * status toggles.
 */

Item {
    id: link

    property real s: 1.1
    property bool expanded: false
    property real pressScale: 1

    readonly property var wifiDevice:
        Networking?.devices?.values.find(d => d && d.type === DeviceType.Wifi) ?? null

    readonly property var wifiNetworks:
        wifiDevice?.networkIds?.values ?? wifiDevice?.networks?.values ?? []

    readonly property var activeWifi:
        wifiNetworks.find(n => n && n.connected) ?? null

    readonly property bool wifiOn:
        Networking?.wifiEnabled ?? false

    readonly property var btAdapter:
        Bluetooth?.defaultAdapter ?? null

    readonly property bool bluetoothOn:
        btAdapter?.enabled ?? false

    readonly property real wifiLevel:
        activeWifi && activeWifi.strength !== undefined
        ? activeWifi.strength / 100
        : 0

    readonly property string wifiName:
        activeWifi
        ? activeWifi.name
        : "Not Connected"

    implicitWidth: panel.width
    implicitHeight: panel.height

    scale: pressScale

    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutBack
        }
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent

        transformOrigin: Item.Center

        width: expanded
            ? 240 * link.s
            : compact.width + 14 * link.s

        height: expanded
            ? 112 * link.s
            : compact.height + 8 * link.s

        radius: expanded
            ? 18 * link.s
            : height / 2

        color: expanded
            ? Theme.capsule
            : "transparent"

        border.width: expanded ? 1 : 0
        border.color: Theme.capsuleBorder

        Behavior on width {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 260
            }
        }

        Behavior on border.width {
            NumberAnimation {
                duration: 220
            }
        }

        Row {
            id: compact

            anchors.centerIn: parent

            spacing: 7 * link.s

            opacity: expanded ? 0 : 1
            scale: expanded ? 0.78 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                }
            }

            Loader {
                anchors.verticalCenter: parent.verticalCenter

                width: 18 * link.s
                height: 18 * link.s

                sourceComponent:
                    link.wifiOn
                    ? wifiCompact
                    : link.bluetoothOn
                        ? bluetoothCompact
                        : offlineCompact
            }

            Component {
                id: wifiCompact

                WifiGlyph {
                    anchors.fill: parent

                    s: link.s
                    level: link.wifiLevel
                    on: link.wifiOn
                }
            }

            Component {
                id: bluetoothCompact

                GlyphIcon {
                    anchors.fill: parent

                    name: "bluetooth"
                    color: Theme.cream
                    stroke: 1.8
                }
            }

            Component {
                id: offlineCompact

                GlyphIcon {
                    anchors.fill: parent

                    name: "network-off"
                    color: Theme.dim
                    stroke: 1.8
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text:
                    link.wifiOn && link.activeWifi
                    ? link.wifiName
                    : link.bluetoothOn
                        ? "Bluetooth"
                        : "Offline"

                color: Theme.cream

                font.family: Theme.font
                font.pixelSize: 12 * link.s
                font.weight: 600
                font.letterSpacing: 1.2 * link.s
            }
        }

        Column {
            id: expandedContent

            anchors.centerIn: parent

            width: parent.width - 30 * link.s

            spacing: 6 * link.s

            opacity: expanded ? 1 : 0
            scale: expanded ? 1 : 0.82

            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 340
                    easing.type: Easing.OutBack
                }
            }

            LinkRow {
                title:
                    link.wifiOn
                    ? link.wifiName
                    : "WiFi"

                status:
                    link.wifiOn
                    ? "On"
                    : "Off"

                active: link.wifiOn
                useWifiGlyph: true
            }

            Rectangle {
                width: parent.width
                height: 1

                color: Theme.cream
                opacity: expanded ? 0.4 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }
            }

            LinkRow {
                icon: "bluetooth"

                title: "Bluetooth"

                status:
                    link.bluetoothOn
                    ? "On"
                    : "Off"

                active: link.bluetoothOn
            }
        }

        states: [
            State {
                name: "expanded"
                when: expanded

                PropertyChanges {
                    target: expandedContent
                    opacity: 1
                    scale: 1
                }
            }
        ]
    }

    component LinkRow: Item {
        property string icon
        property string title
        property string status
        property bool active
        property bool useWifiGlyph: false

        width: parent.width
        height: 40 * link.s

        Row {
            anchors.fill: parent

            spacing: 12 * link.s

            Loader {
                anchors.verticalCenter: parent.verticalCenter

                width: 24 * link.s
                height: 24 * link.s

                sourceComponent:
                    useWifiGlyph
                    ? wifiIcon
                    : normalIcon
            }

            Component {
                id: wifiIcon

                WifiGlyph {
                    anchors.fill: parent

                    s: link.s
                    level: link.wifiLevel
                    on: link.wifiOn
                }
            }

            Component {
                id: normalIcon

                GlyphIcon {
                    anchors.fill: parent

                    name: icon

                    color:
                        active
                        ? Theme.cream
                        : Theme.dim

                    stroke: 1.8
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width - statusText.width - 48 * link.s

                text: title

                color:
                    active
                    ? Theme.cream
                    : Theme.dim

                font.family: Theme.font
                font.pixelSize: 13 * link.s
                font.weight: 600

                elide: Text.ElideRight
            }

            Text {
                id: statusText

                anchors.verticalCenter: parent.verticalCenter

                text: status

                color:
                    active
                    ? Theme.cream
                    : Theme.dim

                font.family: Theme.font
                font.pixelSize: 12 * link.s
                font.weight: 600
            }
        }
    }

    MouseArea {
        anchors.centerIn: parent

        width: parent.width + 30 * link.s
        height: parent.height + 25 * link.s

        z: 100

        hoverEnabled: true

        onPressed: link.pressScale = 0.96
        onReleased: link.pressScale = 1
        onCanceled: link.pressScale = 1

        onClicked: {
            link.expanded = !link.expanded
        }
    }
}

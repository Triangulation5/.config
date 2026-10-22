pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.services
import qs.components.icons
import qs.components.animation

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

    /** Open/close choreography: clear one face before the geometry moves. */
    readonly property int compactFadeMs: 140
    readonly property int openDelayMs: 160
    readonly property int contentFadeMs: 220
    readonly property int closeDelayMs: 240
    readonly property int compactReturnMs: 300

    /**
     * The panel's geometry target, deliberately separate from `expanded`.
     * Opening waits for the compact face to clear; closing waits for the
     * expanded rows to clear, so the two faces never overlap in the capsule.
     */
    property bool panelOpen: false
    property bool compactShown: true

    /**
     * Redaction gate (Flags.lockPrivacy): a network name is an address the room
     * can read, so the glance falls back to the bare "WiFi" label while the
     * session is locked. The toggles and the signal glyph stay live.
     */
    readonly property bool redacted: Flags.lockPrivacy

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

    /**
     * Content reveal latch: the rows stay hidden for the shared latch delay
     * after the panel starts expanding, so their text doesn't pop in while the
     * capsule is still growing. On close the latch drops immediately, letting
     * the rows fade completely before the panel starts shrinking.
     */
    RevealLatch {
        id: contentReveal
        shown: link.panelOpen && link.expanded
    }

    onExpandedChanged: {
        if (expanded) {
            closeTimer.stop();
            compactTimer.stop();
            compactShown = false;
            if (!panelOpen)
                openTimer.restart();
        } else {
            openTimer.stop();
            compactTimer.stop();
            if (panelOpen)
                closeTimer.restart();
            else
                compactShown = true;
        }
    }

    Timer {
        id: openTimer
        interval: link.openDelayMs
        onTriggered: if (link.expanded) link.panelOpen = true
    }

    Timer {
        id: closeTimer
        interval: link.closeDelayMs
        onTriggered: {
            if (!link.expanded) {
                link.panelOpen = false;
                compactTimer.restart();
            }
        }
    }

    Timer {
        id: compactTimer
        interval: link.compactReturnMs
        onTriggered: if (!link.expanded && !link.panelOpen) link.compactShown = true
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent

        transformOrigin: Item.Center

        width: link.panelOpen
            ? 240 * link.s
            : compact.width + 14 * link.s

        height: link.panelOpen
            ? 112 * link.s
            : compact.height + 8 * link.s

        radius: BarMode.dwmStyle
            ? 0
            : (link.panelOpen ? 18 * link.s : height / 2)

        color: link.panelOpen
            ? Theme.capsule
            : "transparent"

        border.width: link.panelOpen ? 1 : 0
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

            opacity: link.compactShown ? 1 : 0
            scale: link.compactShown ? 1 : 0.78

            Behavior on opacity {
                NumberAnimation {
                    duration: link.compactFadeMs
                    easing.type: Easing.OutCubic
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
                    ? (link.redacted ? "WiFi" : link.wifiName)
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

            opacity: link.panelOpen && link.expanded && contentReveal.ready ? 1 : 0
            scale: link.expanded ? 1 : 0.82

            Behavior on opacity {
                NumberAnimation {
                    duration: link.contentFadeMs
                    easing.type: Easing.OutCubic
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
                    ? (link.redacted ? "WiFi" : link.wifiName)
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
                /** Fades with the parent Column; no independent exit. */
                opacity: 0.4
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
                textFormat: Text.PlainText

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

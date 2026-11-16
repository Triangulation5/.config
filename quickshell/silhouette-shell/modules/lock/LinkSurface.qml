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
 *
 * The compact identity — its glyph and its label, whichever network state is
 * current — travels into the row it belongs to as the capsule opens, the same
 * travelling-glyph idea the battery glance uses, instead of fading out in place.
 * The label is part of that unit on purpose: a glyph that flies while its name
 * dissolves reads as two things, and which name it is (the wifi network, or
 * "Bluetooth" when that is what the capsule speaks for) must not change that.
 * The identity hands over to the expanded row's own copy once the rows reveal.
 */

Item {
    id: link

    property real s: 1.1
    property bool expanded: false
    property real pressScale: 1

    /** Open/close choreography: clear one face before the geometry moves. */
    readonly property int compactFadeMs: 140
    readonly property int openDelayMs: 160
    readonly property int openMotionMs: 320
    readonly property int contentFadeMs: 180
    readonly property int closeDelayMs: 240
    readonly property int compactReturnMs: 350

    /**
     * The panel's geometry target, deliberately separate from `expanded`.
     * Opening waits for the compact face to clear; closing waits for the
     * expanded rows to clear, so the two faces never overlap in the capsule.
     */
    CompactExpandState {
        id: transition
        expanded: link.expanded
        hideCompactOnExpand: false
        openDelay: link.openDelayMs
        closeDelay: link.closeDelayMs
        compactReturnDelay: link.compactReturnMs
    }

    readonly property bool panelOpen: transition.panelOpen
    readonly property bool compactShown: transition.compactShown

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

    /**
     * Which face the capsule is speaking for. Wifi needs a network to name, not
     * just a live radio: an on-but-unconnected wifi makes the capsule fall
     * through to Bluetooth, or to Offline when that is off too. Keeping this in
     * one pair of properties is what makes the glyph, the label and the row the
     * identity travels to agree in every radio state.
     */
    readonly property bool showsWifi: link.wifiOn && link.activeWifi !== null
    readonly property bool showsBluetooth: !link.showsWifi && link.bluetoothOn

    /** The expanded row the compact identity flies toward; see showsWifi. */
    readonly property int identityRow: link.showsWifi ? 0 : (link.showsBluetooth ? 1 : 0)

    implicitWidth: panel.width
    implicitHeight: panel.height

    scale: pressScale

    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutBack
        }
    }

    /** The expanded rows wait until the capsule has settled. */
    RevealLatch {
        id: contentReveal
        shown: link.panelOpen && link.expanded
        delay: link.openMotionMs
        jitter: 0
    }

    /**
     * The compact glyph stays visible through the panel morph; its label subtly
     * shrinks and fades as the panel opens, before the expanded rows appear.
     */
    Connections {
        target: contentReveal
        function onReadyChanged() {
            if (contentReveal.revealed)
                transition.compactShown = false;
        }
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent

        transformOrigin: Item.Center

        width: link.panelOpen
            ? 240 * link.s
            : compactLabel.implicitWidth + 39 * link.s

        height: link.panelOpen
            ? 112 * link.s
            : Math.max(18 * link.s, compactLabel.implicitHeight) + 8 * link.s

        radius: BarMode.dwmStyle
            ? 0
            : (link.panelOpen ? 18 * link.s : height / 2)

        color: link.panelOpen
            ? ColorScheme.capsule
            : "transparent"

        border.width: link.panelOpen ? 1 : 0
        border.color: ColorScheme.capsuleBorder

        Behavior on width {
            NumberAnimation {
                duration: link.openMotionMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: link.openMotionMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: link.openMotionMs
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

            /**
             * Fixed endpoints keep this row from chasing the panel's changing
             * implicit size during the morph. The closed capsule leaves 7*s
             * and 4*s insets; the expanded rows start at 15*s. Their icon
             * centres are 29.5*s and 82.5*s, with a fixed 24*s glyph.
             */
            width: implicitWidth
            height: implicitHeight

            x: link.panelOpen ? 15 * link.s : 7 * link.s
            y: link.panelOpen
                ? (link.identityRow === 1 ? 82.5 : 29.5) * link.s - 12 * link.s
                : 4 * link.s

            spacing: link.panelOpen ? 12 * link.s : 7 * link.s

            Behavior on spacing {
                NumberAnimation {
                    duration: link.panelOpen ? link.openMotionMs : link.compactReturnMs
                    easing.type: Easing.OutCubic
                }
            }

            opacity: link.compactShown ? 1 : 0
            scale: link.compactShown ? 1 : 0.78

            Behavior on x {
                NumberAnimation {
                    duration: link.panelOpen ? link.openMotionMs : link.compactReturnMs
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: link.panelOpen ? link.openMotionMs : link.compactReturnMs
                    easing.type: Easing.OutCubic
                }
            }

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

                width: link.panelOpen ? 24 * link.s : 18 * link.s
                height: width

                Behavior on width {
                    NumberAnimation {
                        duration: link.panelOpen ? link.openMotionMs : link.compactReturnMs
                        easing.type: Easing.OutCubic
                    }
                }

                sourceComponent:
                    link.showsWifi
                    ? wifiCompact
                    : link.showsBluetooth
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
                id: compactLabel
                anchors.verticalCenter: parent.verticalCenter

                text:
                    link.showsWifi
                    ? (link.redacted ? "WiFi" : link.wifiName)
                    : link.showsBluetooth
                        ? "Bluetooth"
                        : "Offline"

                color: Theme.cream

                font.family: Theme.font
                font.pixelSize: 12 * link.s
                font.weight: 600
                font.letterSpacing: 1.2 * link.s

                opacity: link.panelOpen ? 0 : 1
                scale: link.panelOpen ? 0.9 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Column {
            id: expandedContent

            anchors.centerIn: parent

            width: parent.width - 30 * link.s

            spacing: 6 * link.s

            opacity: contentReveal.revealed ? 1 : 0
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

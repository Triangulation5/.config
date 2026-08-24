pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Notifications
import qs.services
import qs.modules.pill.surfaces
import qs.components.layout
import qs.components.icons

/**
 * 繋 LINK surface: connectivity rows (auto-detected Netz, Bluetooth) over the
 * 報 INBOX notification center, with WLAN and Bluetooth drill-in subviews that
 * cross-fade in place. Owns the `subview` state machine and exposes
 * `desiredW` and `back()` for the pill's morph and Escape plumbing. Opening marks all
 * notifications seen after a short beat so unread embers register first.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 16
    mRight: 16
    mBottom: 13

    property string subview: "main"

    /**
     * Subview to land on the next time the surface opens. The pill sets this from
     * the glance that opened the surface (wifi → "wifi", inbox → "main") so the
     * wifi glance drills straight to the network list past the connectivity rows.
     */
    property string initialView: "main"

    readonly property real desiredW: (subview === "wifi" ? 272 : subview === "bt" ? 286 : 330) * s

    /**
     * Row-soul focus registry. Each hoverable row reports itself here; the bead
     * docks as a glowing seam at the left edge of the focused row and hides
     * when nothing is focused. Only the main subview participates.
     */
    property Item focusRowItem: null

    /**
     * Sticky: once a row has been focused the seam stays parked on it when the
     * pointer leaves, gliding to the next focused row instead of re-waking
     * from the pill centre on every hover. Cleared only when the surface
     * closes.
     */
    function reportRowHover(item, hovered) {
        if (hovered)
            focusRowItem = item;
    }

    readonly property bool rowFocused: focusRowItem !== null && subview === "main" && active

    readonly property point rowPoint: {
        void root.width;
        void root.height;
        void mainCol.implicitHeight;
        void root.focusRowItem;
        if (!focusRowItem)
            return Qt.point(4 * s, root.height / 2);
        return focusRowItem.mapToItem(root, 4 * s, focusRowItem.height / 2);
    }

    ameForm: rowFocused ? "rowseam" : "off"
    amePoint: rowPoint

    implicitHeight: subview === "wifi" ? wifiPage.implicitHeight
        : subview === "bt" ? btPage.implicitHeight
        : mainCol.implicitHeight

    readonly property var netDevices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var eth: netDevices.find(function(d) { return d && d.type === DeviceType.Wired && d.connected }) || null
    readonly property var wifiDev: netDevices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wired: eth !== null

    readonly property real ethSpeed: (eth && eth.linkSpeed) ? eth.linkSpeed : 0
    readonly property string ethSpeedText: ethSpeed > 0
        ? (ethSpeed >= 1000 ? (ethSpeed / 1000).toFixed(ethSpeed % 1000 === 0 ? 0 : 1) + " Gb/s" : ethSpeed + " Mb/s")
        : ""

    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var wifiNets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var wifiActive: wifiNets.find(function(n) { return n && n.connected }) || null

    readonly property string netzSubText: wired
        ? ("Ethernet"
            + (ethSpeedText.length ? " · " + ethSpeedText : "")
            + (ethIp.length ? " · " + ethIp : ""))
        : (wifiActive ? (wifiActive.name || "") : (wifiOn ? "Not connected" : "Off"))

    readonly property var btAdapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property var btDevices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices.values : []
    readonly property var btConnected: btDevices.filter(function(d) { return d && d.connected })
    readonly property bool btOn: btAdapter ? btAdapter.enabled === true : false
    readonly property var btPrimary: btConnected.length > 0 ? btConnected[0] : null
    readonly property int btBattery: batteryLevel(btPrimary)

    readonly property string btSubText: !btOn ? "Off"
        : (btPrimary
            ? ((btPrimary.deviceName || btPrimary.name || "Unknown")
                + (btConnected.length > 1 ? " +" + (btConnected.length - 1) : ""))
            : "Not connected")

    property string ethIp: ""

    /** Tracks explicit airplane mode state: toggles wifi + BT radios together. */
    property bool airplaneMode: false

    onAirplaneModeChanged: {
        if (!active) return;
        if (typeof Networking !== "undefined" && Networking)
            Networking.wifiEnabled = !airplaneMode;
        if (btAdapter)
            btAdapter.enabled = !airplaneMode;
    }

    /**
     * Pops one navigation level: an expanded subview row collapses first, then
     * the drill-in returns to main (true); main returns false so the caller
     * closes the surface instead.
     */
    function back() {
        if (subview === "wifi" && wifiPage.kbBack())
            return true;
        if (subview === "bt" && btPage.kbBack())
            return true;
        if (subview !== "main") {
            subview = "main";
            return true;
        }
        return false;
    }

    /**
     * Keyboard row focus for the main view: 0 = Network, 1 = Bluetooth,
     * 2 = Airplane Mode. The wifi and bt subviews hand off to their own pages,
     * which keep their own row focus. Returns true when the surface consumed
     * the move.
     */
    property int kbIndex: -1
    readonly property int kbCount: 3

    function kbMove(dir) {
        if (subview === "wifi")
            return wifiPage.kbMove(dir);
        if (subview === "bt")
            return btPage.kbMove(dir);
        if (kbIndex < 0 || kbIndex >= kbCount)
            kbIndex = 0;
        else
            kbIndex = (kbIndex + dir + kbCount) % kbCount;
        if (kbIndex === 0) focusRowItem = netzRow;
        else if (kbIndex === 1) focusRowItem = btRow;
        else focusRowItem = airplaneRow;
        return true;
    }

    /** Return on the link surface: drill into the focused row, toggle airplane, or activate subview row. */
    function kbActivate() {
        if (subview === "wifi")
            return wifiPage.kbActivate();
        if (subview === "bt")
            return btPage.kbActivate();
        var idx = kbIndex < 0 ? 0 : kbIndex;
        if (idx === 2) {
            airplaneMode = !airplaneMode;
            return true;
        }
        subview = idx === 0 ? "wifi" : "bt";
        return true;
    }

    /**
     * Left/right on the link surface: cycle the active subview page's expanded
     * row confirm buttons. Returns true when the page consumed it; the main
     * view has no horizontal controls.
     */
    function kbAdjust(dir) {
        if (subview === "wifi")
            return wifiPage.kbAdjust(dir);
        if (subview === "bt")
            return btPage.kbAdjust(dir);
        return false;
    }

    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    onActiveChanged: {
        if (active) {
            subview = (initialView === "wifi" && wifiDev) ? "wifi" : "main";
            seenTimer.restart();
        } else {
            seenTimer.stop();
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    Timer {
        id: seenTimer
        interval: 600
        repeat: false
        onTriggered: Notifs.markAllSeen()
    }

    Process {
        id: ipProc
        command: ["sh", "-c", "ip -4 -o addr show scope global up | awk '{for(i=1;i<=NF;i++) if($i==\"inet\"){print $(i+1); exit}}' | cut -d/ -f1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.ethIp = this.text.trim() }
    }

    Timer {
        interval: 15000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: ipProc.running = true
    }

    Item {
        id: mainView
        anchors.fill: parent
        opacity: root.subview === "main" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "main" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Column {
            id: mainCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 4 * root.s

            Item {
                width: parent.width
                height: 24 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Flags.showGlyphs
                        text: "繋"
                        color: Theme.cream
                        font.family: Theme.fontJp
                        font.weight: Font.Medium
                        font.pixelSize: 16 * root.s
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "LINK"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.6 * root.s
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s
                    visible: Notifs.unread > 0

                    Ember {
                        id: headerEmber
                        s: root.s
                        anchors.verticalCenter: parent.verticalCenter
                        size: 6 * root.s
                        visible: Notifs.unread > 0

                        SequentialAnimation on opacity {
                            running: headerEmber.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.55; to: 1; duration: 1200; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1; to: 0.55; duration: 1200; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Notifs.unread > 0
                        text: Notifs.unread + " NEW"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4 * root.s
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hair
            }

            LinkRow {
                id: netzRow
                s: root.s
                focused: root.kbIndex === 0
                icon: root.wired ? "ethernet" : "wifi"
                iconColor: !root.wired && root.wifiOn ? Theme.vermLit : Theme.iconDim
                name: "Network"
                sub: root.netzSubText
                subColor: !root.wired && root.wifiActive ? Theme.vermLit : Theme.dim
                subBold: !root.wired && root.wifiActive
                onRowHovered: (hovered) => {
                    if (hovered) {
                        root.reportRowHover(netzRow, true);
                        root.kbIndex = 0;
                    }
                }
                onClicked: root.subview = "wifi"

                Filament {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.wired && root.wifiOn && root.wifiActive !== null
                    s: root.s
                    kind: "signal"
                    level: (root.wifiActive && root.wifiActive.signalStrength) || 0
                }

                LinkToggle {
                    s: root.s
                    visible: !root.wired
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.wifiOn
                    onToggled: {
                        if (typeof Networking !== "undefined" && Networking)
                            Networking.wifiEnabled = !Networking.wifiEnabled;
                    }
                }
            }

            LinkRow {
                id: btRow
                s: root.s
                focused: root.kbIndex === 1
                icon: "bluetooth"
                iconColor: root.btConnected.length > 0 ? Theme.vermLit : Theme.iconDim
                name: "Bluetooth"
                sub: root.btSubText
                subColor: root.btPrimary ? Theme.vermLit : Theme.dim
                subBold: root.btPrimary !== null
                onRowHovered: (hovered) => {
                    if (hovered) {
                        root.reportRowHover(btRow, true);
                        root.kbIndex = 1;
                    }
                }
                onClicked: root.subview = "bt"

                Filament {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btPrimary !== null && root.btBattery >= 0
                    s: root.s
                    kind: "battery"
                    level: Math.max(0, root.btBattery) / 100
                }

                LinkToggle {
                    s: root.s
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.btOn
                    onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                }
            }

            LinkRow {
                id: airplaneRow
                s: root.s
                focused: root.kbIndex === 2
                icon: "airplane"
                iconColor: root.airplaneMode ? Theme.vermLit : Theme.iconDim
                name: "Airplane Mode"
                sub: root.airplaneMode ? "On" : "Off"
                subColor: root.airplaneMode ? Theme.vermLit : Theme.dim
                subBold: root.airplaneMode
                chevron: false
                onRowHovered: (hovered) => {
                    if (hovered) {
                        root.reportRowHover(airplaneRow, true);
                        root.kbIndex = 2;
                    }
                }
                onClicked: root.airplaneMode = !root.airplaneMode

                LinkToggle {
                    s: root.s
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.airplaneMode
                    onToggled: root.airplaneMode = !root.airplaneMode
                }
            }

            LinkInbox {
                s: root.s
                onReportRowHover: (item, hovered) => root.reportRowHover(item, hovered)
                onRequestClose: root.requestClose()
            }
        }
    }

    LinkWifi {
        id: wifiPage
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        active: root.active && root.subview === "wifi"
        opacity: root.subview === "wifi" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "wifi" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }
        onBack: root.subview = "main"
    }

    LinkBt {
        id: btPage
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        active: root.active && root.subview === "bt"
        opacity: root.subview === "bt" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "bt" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }
        onBack: root.subview = "main"
    }
}

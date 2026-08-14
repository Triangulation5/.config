pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services
import qs.components.layout
import qs.components.icons
import qs.components.controls

/**
 * Bluetooth drill-in for the link surface: back chevron, scan with 25s
 * auto-stop, adapter toggle, live device list. Known devices use the
 * Quickshell connect/disconnect calls; unpaired devices run a bluetoothctl
 * pair-trust-connect flow with an inline ember while running and a transient
 * failure line.
 */
Item {
    id: root

    property real s: 1.1
    property bool active: false

    signal back()

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property var devices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices.values : []

    /**
     * BlueZ hands the cache out in arbitrary order; sort connected first,
     * then paired, then named devices, nameless MACs last so a discovery scan
     * doesn't churn the useful rows around.
     */
    readonly property var devicesSorted: devices.slice().sort(function(a, b) {
        function rank(d) {
            if (!d) return 3;
            if (d.connected) return 0;
            if (d.paired) return 1;
            return (d.name && d.name.length) ? 2 : 3;
        }
        var r = rank(a) - rank(b);
        if (r !== 0) return r;
        return String((a && a.name) || "").localeCompare(String((b && b.name) || ""));
    })
    readonly property bool discovering: adapter ? adapter.discovering === true : false

    property string pairingAddress: ""
    property string failedAddress: ""

    /**
     * Address of the known device whose inline confirm row (disconnect or
     * connect, plus forget) is open, mirroring the wifi drill-in's expanded
     * SSID.
     */
    property string expandedAddress: ""

    implicitHeight: listFrame.y + listFrame.height

    function metaFor(d) {
        if (!d) return "";
        var parts = [];
        if (d.connected) parts.push("connected");
        else if (d.paired) parts.push("paired");
        if (d.state !== undefined && typeof BluetoothDeviceState !== "undefined") {
            var st = BluetoothDeviceState.toString(d.state);
            if (st && st.length > 0 && parts.indexOf(st.toLowerCase()) === -1) parts.push(st.toLowerCase());
        }
        return parts.join(" · ");
    }

    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    /**
     * Click dispatch for a device row. A connected or paired device toggles
     * the inline confirm row rather than acting at once; an unpaired device
     * runs the bluetoothctl pair-trust-connect flow.
     */
    function activateDevice(d) {
        if (!d)
            return;
        if (d.connected || d.paired) {
            var addr = d.address || "";
            expandedAddress = (addr.length && expandedAddress === addr) ? "" : addr;
            return;
        }
        pairDevice(d);
    }

    function connectDevice(d) {
        expandedAddress = "";
        if (d && typeof d.connect === "function")
            d.connect();
    }

    function disconnectDevice(d) {
        expandedAddress = "";
        if (d && typeof d.disconnect === "function")
            d.disconnect();
    }

    /**
     * Unpairs through the Quickshell device object, the same layer the
     * connect and disconnect calls use; BlueZ drops the bond and the row
     * falls back to its Pair chip.
     */
    function forgetDevice(d) {
        expandedAddress = "";
        if (d && typeof d.forget === "function")
            d.forget();
    }

    function pairDevice(d) {
        if (!d || !d.address || pairProc.running)
            return;
        pairingAddress = d.address;
        failedAddress = "";
        pairProc.command = ["sh", "-c",
            'timeout 30 bluetoothctl pair "$1" && bluetoothctl trust "$1" && timeout 30 bluetoothctl connect "$1"',
            "sh", d.address];
        pairProc.running = true;
    }

    onActiveChanged: {
        if (!active) {
            scanTimer.stop();
            expandedAddress = "";
            confirmFocus = -1;
            kbIndex = -1;
            if (adapter && adapter.discovering)
                adapter.discovering = false;
        }
    }

    Timer {
        id: scanTimer
        interval: 25000
        repeat: false
        onTriggered: if (root.adapter) root.adapter.discovering = false
    }

    Timer {
        id: failTimer
        interval: 4000
        repeat: false
        onTriggered: root.failedAddress = ""
    }

    Process {
        id: pairProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            var addr = root.pairingAddress;
            root.pairingAddress = "";
            if (exitCode !== 0) {
                root.failedAddress = addr;
                failTimer.restart();
            }
        }
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
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
                    onClicked: root.back()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BLUETOOTH"
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
            spacing: 10 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.adapter ? root.adapter.enabled === true : false
                text: root.discovering ? "Scanning…" : "Scan"
                color: root.discovering ? Theme.vermLit : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.adapter)
                            return;
                        root.adapter.discovering = !root.adapter.discovering;
                        if (root.adapter.discovering)
                            scanTimer.restart();
                        else
                            scanTimer.stop();
                    }
                }
            }

            LinkToggle {
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                on: root.adapter ? root.adapter.enabled === true : false
                onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
            }
        }
    }

    /**
     * Keyboard focus over the device rows; -1 until the first arrow so the
     * first press lands on the top device.
     */
    property int kbIndex: -1

    function kbMove(dir) {
        var n = root.devicesSorted.length;
        if (n === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= n)
            kbIndex = 0;
        else
            kbIndex = (kbIndex + dir + n) % n;
        return true;
    }

    /**
     * Return on the bt list: fire the focused confirm button when one is
     * armed, else activate (connect / pair / manage) the focused device.
     */
    function kbActivate() {
        var n = root.devicesSorted.length;
        if (n === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= n)
            kbIndex = 0;
        var d = root.devicesSorted[kbIndex];
        var addr = d ? (d.address || "") : "";
        if (addr.length && root.expandedAddress === addr && root.confirmFocus >= 0) {
            if (root.confirmFocus === 0) {
                if (d.connected) root.disconnectDevice(d);
                else root.connectDevice(d);
            } else {
                root.forgetDevice(d);
            }
            return true;
        }
        root.activateDevice(d);
        return true;
    }

    /**
     * Confirm-button focus for the expanded row: 0 = primary (Connect/
     * Disconnect), 1 = Forget. Resets whenever the expanded row changes.
     */
    property int confirmFocus: -1
    onExpandedAddressChanged: confirmFocus = -1

    /**
     * Left/right on the bt list: cycle the expanded row's confirm buttons.
     * Returns false when there is nothing to adjust, so vim h/l fall through
     * to back/enter.
     */
    function kbAdjust(dir) {
        var n = root.devicesSorted.length;
        if (n === 0 || kbIndex < 0 || kbIndex >= n)
            return false;
        var d = root.devicesSorted[kbIndex];
        var addr = d ? (d.address || "") : "";
        if (addr.length === 0 || root.expandedAddress !== addr)
            return false;
        if (confirmFocus < 0)
            confirmFocus = 0;
        else
            confirmFocus = (confirmFocus + dir + 2) % 2;
        return true;
    }

    /**
     * Backspace on the bt list: collapse the expanded row before the caller
     * pops the subview. Returns true when a row was open and got collapsed.
     */
    function kbBack() {
        if (root.expandedAddress.length) {
            root.expandedAddress = "";
            return true;
        }
        return false;
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    BtDeviceList {
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        host: root
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services

/**
 * Bluetooth drill-in for the link surface: back chevron, scan with 25s
 * auto-stop, adapter toggle, a connected block on top and the nearby list
 * below. Connected rows are taller and carry a full-width battery thread fed by
 * Peripherals (UPower), since BlueZ keeps Battery1 behind Experimental;
 * USB-dongle peripherals with a battery join that block as display-only rows.
 * Known devices use the Quickshell connect/disconnect calls; unpaired devices
 * run a bluetoothctl pair-trust-connect flow with an inline ember while running
 * and a transient failure line.
 *
 * Built on LinkDrillIn, which owns the header, divider, scroll list and the
 * keyboard scaffold; this panel supplies the adapter/device state, the row
 * delegates and the hook implementations (activateAt, confirmCount, scan).
 */
LinkDrillIn {
    id: root

    title: "BLUETOOTH"
    scanInterval: 25000

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property var devices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices.values : []

    /**
     * BlueZ hands the cache out in arbitrary order; sort connected first,
     * then paired, then named devices, nameless MACs last so a discovery scan
     * doesn't churn the useful rows around. Reads connectedCount so a connect
     * flip re-sorts, which the raw device list never signals.
     */
    readonly property var devicesSorted: {
        var tick = Peripherals.connectedCount;
        function rank(d) {
            if (!d) return 3;
            if (d.connected) return 0;
            if (d.paired) return 1;
            return (d.name && d.name.length) ? 2 : 3;
        }
        return devices.slice().sort(function(a, b) {
            var r = rank(a) - rank(b);
            if (r !== 0) return r;
            return String((a && a.name) || "").localeCompare(String((b && b.name) || ""));
        });
    }

    /**
     * Rows for the connected block: every connected Bluetooth device paired
     * with its UPower battery entry by MAC, then USB-dongle peripherals that
     * have no Bluetooth counterpart. `up` is null when nothing reports charge.
     */
    readonly property var connectedRows: {
        var rows = [];
        var byMac = Peripherals.byMac;
        for (var i = 0; i < devicesSorted.length; i++) {
            var d = devicesSorted[i];
            if (!d || !d.connected) continue;
            rows.push({ bt: d, up: byMac[String(d.address || "").toUpperCase()] || null });
        }
        var usb = Peripherals.usb;
        for (var j = 0; j < usb.length; j++)
            rows.push({ bt: null, up: usb[j] });
        return rows;
    }
    readonly property var nearbyRows: devicesSorted.filter(function(d) { return d && !d.connected; })

    property string pairingAddress: ""
    property string failedAddress: ""

    /**
     * The expanded confirm row is keyed by device address in `expandedRow`
     * (LinkDrillIn), so the shared Backspace-collapse and deactivation reset
     * cover it along with the wifi panel and the connected block.
     */

    implicitHeight: listFrame.y + listFrame.height

    function metaFor(d) {
        if (!d) return "";
        var parts = [];
        if (d.paired) parts.push("paired");
        if (d.state !== undefined && typeof BluetoothDeviceState !== "undefined") {
            var st = BluetoothDeviceState.toString(d.state);
            if (st && st.length > 0 && parts.indexOf(st.toLowerCase()) === -1) parts.push(st.toLowerCase());
        }
        return parts.join(" · ");
    }

    /** BlueZ battery, the fallback when UPower reports nothing for the device. */
    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    /** Battery for one block row: UPower first, BlueZ for a bare Bluetooth row. */
    function batteryFor(row) {
        if (!row) return -1;
        if (row.up) return Peripherals.pct(row.up);
        return root.batteryLevel(row.bt);
    }

    function rowName(row) {
        if (!row) return "Unknown";
        if (row.bt) return row.bt.deviceName || row.bt.name || "Unknown";
        return (row.up && row.up.model) ? row.up.model : "Unknown";
    }

    /**
     * Click dispatch for a row. A connected or paired device toggles the inline
     * confirm row rather than acting at once; an unpaired device runs the
     * bluetoothctl pair-trust-connect flow.
     */
    function activateDevice(d) {
        if (!d)
            return;
        if (d.connected || d.paired) {
            var addr = d.address || "";
            expandedRow = (addr.length && expandedRow === addr) ? "" : addr;
            return;
        }
        pairDevice(d);
    }

    /** Connected-block row click: only a Bluetooth-backed row is interactive. */
    function activateConnected(row) {
        if (row && row.bt)
            activateDevice(row.bt);
    }

    function connectDevice(d) {
        expandedRow = "";
        if (d && typeof d.connect === "function")
            d.connect();
    }

    function disconnectDevice(d) {
        expandedRow = "";
        if (d && typeof d.disconnect === "function")
            d.disconnect();
    }

    /**
     * Unpairs through the Quickshell device object, the same layer the
     * connect and disconnect calls use; BlueZ drops the bond and the row
     * falls back to its Pair chip.
     */
    function forgetDevice(d) {
        expandedRow = "";
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

    /** ---- keyboard scaffold hooks (LinkDrillIn) ---- */

    function rowCount() {
        return root.connectedRows.length + root.nearbyRows.length;
    }

    function confirmCount(i) {
        if (i < root.connectedRows.length) {
            var b = root.connectedRows[i] ? root.connectedRows[i].bt : null;
            var bAddr = b ? (b.address || "") : "";
            return (bAddr.length && root.expandedRow === bAddr) ? 2 : 0;
        }
        var d = root.nearbyRows[i - root.connectedRows.length];
        var addr = d ? (d.address || "") : "";
        if (addr.length && root.expandedRow === addr)
            return 2;
        return 0;
    }

    /**
     * Return on the bt list: fire the focused confirm button when one is
     * armed, else activate (connect / pair / manage) the focused row. The
     * connected block runs first, so the index walk spans both sections.
     */
    function activateAt(i) {
        if (i < root.connectedRows.length) {
            var b = root.connectedRows[i] ? root.connectedRows[i].bt : null;
            var bAddr = b ? (b.address || "") : "";
            if (bAddr.length && root.expandedRow === bAddr) {
                return root.confirmFire(b, [
                    (it) => root.disconnectDevice(it),
                    (it) => root.forgetDevice(it)
                ]);
            }
            root.activateConnected(root.connectedRows[i]);
            return true;
        }
        var d = root.nearbyRows[i - root.connectedRows.length];
        var addr = d ? (d.address || "") : "";
        if (addr.length && root.expandedRow === addr) {
            return root.confirmFire(d, [
                (it) => root.connectDevice(it),
                (it) => root.forgetDevice(it)
            ]);
        }
        root.activateDevice(d);
        return true;
    }

    /** Scan side effects: BlueZ discovery is the scan; the 25s timer stops it. */
    function scanStarted() {
        if (root.adapter)
            root.adapter.discovering = true;
    }

    function scanStopped() {
        if (root.adapter && root.adapter.discovering)
            root.adapter.discovering = false;
    }

    /** Section caption inside the list column. */
    component Eyebrow: Item {
        property string label: ""
        width: parent ? parent.width : 0
        height: 18 * root.s

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.s
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2 * root.s
            text: parent.label
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4 * root.s
        }
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

    Row {
        anchors.right: root.headerBar.right
        anchors.verticalCenter: root.headerBar.verticalCenter
        spacing: 10 * root.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.adapter ? root.adapter.enabled === true : false
            text: root.scanning ? "Scanning…" : "Scan"
            color: root.scanning ? Theme.vermLit : Theme.dim
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.DemiBold

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6 * root.s
                cursorShape: Qt.PointingHandCursor
                onClicked: root.scanning ? root.stopScan() : root.startScan()
            }
        }

        LinkToggle {
            s: root.s
            anchors.verticalCenter: parent.verticalCenter
            on: root.adapter ? root.adapter.enabled === true : false
            onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }
    }

    LinkListFrame {
        id: listFrame
        anchors.top: root.dividerBar.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        emptyText: root.scanning ? "Scanning…" : "No devices found"
        listEmpty: root.connectedRows.length === 0 && root.nearbyRows.length === 0
        listMaxH: 260 * root.s
        listMinH: 24 * root.s

        Eyebrow {
            visible: root.connectedRows.length > 0
            label: "CONNECTED"
        }

        Repeater {
            model: root.connectedRows

            BtConnectedRow {
                s: root.s
                expanded: (modelData && modelData.bt && modelData.bt.address)
                    ? root.expandedRow === modelData.bt.address
                    : false
                focused: root.kbIndex === index
                confirmFocus: root.confirmFocus
                battery: root.batteryFor(modelData)
                charging: (modelData && modelData.up) ? Peripherals.charging(modelData.up) : false
                glyph: (modelData && modelData.bt)
                    ? "bluetooth"
                    : Peripherals.glyphFor(modelData ? modelData.up : null)
                name: root.rowName(modelData)
                list: listFrame
                onRequestActivate: root.activateConnected(modelData)
                onRequestConnect: root.connectDevice(modelData.bt)
                onRequestDisconnect: root.disconnectDevice(modelData.bt)
                onRequestForget: root.forgetDevice(modelData.bt)
                onRequestFocus: root.kbIndex = index
            }
        }

        Eyebrow {
            visible: root.connectedRows.length > 0 && root.nearbyRows.length > 0
            label: "NEARBY"
        }

        Repeater {
            model: root.nearbyRows

            BtDeviceRow {
                s: root.s
                expanded: (modelData && modelData.address)
                    ? root.expandedRow === modelData.address
                    : false
                focused: root.kbIndex === root.connectedRows.length + index
                confirmFocus: root.confirmFocus
                pairing: root.pairingAddress.length > 0
                    && root.pairingAddress === (modelData && modelData.address)
                failed: root.failedAddress.length > 0
                    && root.failedAddress === (modelData && modelData.address)
                battery: root.batteryLevel(modelData)
                meta: root.metaFor(modelData)
                list: listFrame
                onRequestActivate: root.activateDevice(modelData)
                onRequestConnect: root.connectDevice(modelData)
                onRequestDisconnect: root.disconnectDevice(modelData)
                onRequestForget: root.forgetDevice(modelData)
                onRequestFocus: root.kbIndex = root.connectedRows.length + index
            }
        }
    }
}

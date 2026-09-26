pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services

/**
 * Bluetooth drill-in for the link surface: back chevron, scan with a
 * flag-set auto-stop (`btScanMs`, 25s shipped), adapter toggle, a connected
 * block on top and the nearby list below. Connected rows are taller and carry
 * a full-width battery thread fed by
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
    scanInterval: Flags.btScanMs

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null

    /**
     * The connected block: every peripheral Peripherals says is connected — a
     * Bluetooth device BlueZ reports connected, or a USB-dongle peripheral that
     * only UPower knows about — one row each, sorted by name so a row keeps its
     * place across scans. The matching, and the fact that a device can appear
     * here once and only once, is the model's job, not this panel's.
     */
    readonly property var connectedRows: Peripherals.connected.slice().sort(function(a, b) {
        return String(a.name || "").localeCompare(String(b.name || ""));
    })

    /**
     * Devices BlueZ knows that are not connected, ranked for display: paired
     * first, then named devices, nameless MACs last so a discovery scan does not
     * churn the useful rows around; name breaks the ties.
     */
    readonly property var nearbyRows: Peripherals.nearby.slice().sort(function(a, b) {
        var r = rank(a) - rank(b);
        if (r !== 0) return r;
        return String(a.name || "").localeCompare(String(b.name || ""));
    })

    function rank(row) {
        if (!row || !row.bt) return 3;
        if (row.paired) return 1;
        return (row.name && row.name.length) ? 2 : 3;
    }

    property string pairingAddress: ""
    property string failedAddress: ""

    /**
     * The expanded confirm row is keyed by device address in `expandedRow`
     * (LinkDrillIn), so the shared Backspace-collapse and deactivation reset
     * cover it along with the wifi panel and the connected block.
     */

    implicitHeight: listFrame.y + listFrame.height


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
                expanded: modelData.address.length > 0 && root.expandedRow === modelData.address
                focused: root.kbIndex === index
                confirmFocus: root.confirmFocus
                /** Everything the row shows comes from the model row it is handed. */
                level: modelData.level
                onPower: modelData.onPower
                pending: modelData.pending
                glyph: modelData.glyph
                tag: modelData.tag
                name: modelData.name
                stateLabel: modelData.stateLabel
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
                level: modelData.level
                glyph: modelData.glyph
                meta: modelData.stateLabel
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

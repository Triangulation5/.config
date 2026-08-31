pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * WLAN drill-in for the link surface: back chevron, wifi enable toggle and the
 * live network list sorted by signal strength. Security and known-profile
 * ground truth come from nmcli; clicking a secured unknown network expands an
 * inline password row that connects through `nmcli dev wifi connect`. The
 * shared hotspot is rendered by WifiHotspot with its state and nmcli processes
 * owned by HotspotControl. The pill body provides the surface material, so
 * this item draws no background.
 *
 * Built on LinkDrillIn, which owns the header, divider, scroll list and the
 * keyboard scaffold; this panel supplies the network state, the row delegate,
 * the hotspot footer and the hook implementations (activateAt, confirmCount,
 * adjustExtra, scan, activate/deactivate resets).
 */
LinkDrillIn {
    id: root

    title: "WIFI"
    caption: !wifiOn ? "Off"
        : (activeNet ? (activeNet.name || "Connected") : "Not connected")
    captionColor: root.activeNet ? Theme.vermLit : Theme.faint

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var nets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var netsSorted: nets.slice().sort(function(a, b) {
        return ((b ? b.signalStrength : 0) || 0) - ((a ? a.signalStrength : 0) || 0)
    })
    readonly property var activeNet: nets.find(function(n) { return n && n.connected }) || null

    property var securityMap: ({})
    property var knownProfiles: ({})
    property bool connecting: false
    property bool connectFailed: false

    /**
     * SSID of the saved network whose stored password is currently shown, plus
     * the revealed secret itself. Keying both to one SSID keeps the reveal local
     * to the row the user asked about and lets `revealResolved` distinguish "not
     * yet read" from "read but empty" so an open profile shows a clear message.
     */
    property string revealedSsid: ""
    property string revealedPw: ""
    property bool revealResolved: false

    readonly property string hsIface: wifiDev ? (wifiDev.name || "wlan0") : "wlan0"

    /**
     * Draft of the password being typed for the expanded network. Lives on the
     * root so the field can restore itself from the draft if the keyed list
     * model swaps the delegate's network object under it on a rescan.
     */
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    /**
     * Hotspot rows follow the network list in the keyboard cursor: index
     * offset 0 = the hotspot toggle, 1 = network name, 2 = password. The
     * whole block is skipped while wifi is off (it is hidden then).
     */
    readonly property int hsRowCount: root.wifiOn ? 3 : 0
    readonly property int hsToggleIndex: root.netsSorted.length

    implicitHeight: hsBlock.y + hsBlock.height

    function isSecured(ssid) {
        var sec = securityMap[ssid];
        return sec !== undefined && sec !== "" && sec !== "--";
    }

    function refresh() {
        secProc.running = true;
        profProc.running = true;
    }

    /**
     * Splits one `nmcli -t` line at its last unescaped colon and unescapes the
     * leading field. Returns null for lines without a field separator.
     */
    function splitTerse(line) {
        for (var k = line.length - 1; k >= 0; k--) {
            if (line[k] === ":" && (k === 0 || line[k - 1] !== "\\"))
                return { head: line.slice(0, k).replace(/\\:/g, ":"), tail: line.slice(k + 1) };
        }
        return null;
    }

    /**
     * Click dispatch for a network row. A connected or saved network expands the
     * inline confirm row (disconnect/connect plus forget) rather than acting at
     * once; an open unknown network connects directly; an unknown secured network
     * expands the password row. Tapping the open row again collapses it.
     */
    function activateNetwork(net) {
        if (!net)
            return;
        var ssid = net.name || "";
        if (expandedRow === ssid && ssid.length) {
            expandedRow = "";
            return;
        }
        if (net.connected || knownProfiles[ssid] === true) {
            connectFailed = false;
            pwDraft = "";
            expandedRow = ssid;
            return;
        }
        if (!isSecured(ssid)) {
            expandedRow = "";
            if (typeof net.connect === "function")
                net.connect();
            refresh();
            return;
        }
        connectFailed = false;
        pwDraft = "";
        expandedRow = ssid;
    }

    /**
     * Connects a saved profile from its confirm row. Known profiles connect by
     * name through the device so no password prompt is needed.
     */
    function connectKnown(net) {
        if (!net)
            return;
        expandedRow = "";
        if (typeof net.connect === "function")
            net.connect();
        refresh();
    }

    function disconnectNetwork(net) {
        if (!net)
            return;
        expandedRow = "";
        if (typeof net.disconnect === "function")
            net.disconnect();
        refresh();
    }

    /**
     * Drops the saved connection profile for `ssid`. The SSID is passed as its
     * own argv element so an odd character can neither break nor inject the
     * command. The list refreshes once nmcli exits.
     */
    function forgetNetwork(ssid) {
        if (forgetProc.running || !ssid.length)
            return;
        expandedRow = "";
        forgetProc.command = ["nmcli", "connection", "delete", "id", ssid];
        forgetProc.running = true;
    }

    /**
     * Reveals the stored password of a saved profile, or hides it again if the
     * same row is already showing. NetworkManager lets the owning user read their
     * own saved secret without root, so this runs unprivileged. The SSID is
     * passed as its own argv element so an odd character can neither break nor
     * inject the command.
     */
    function revealPassword(ssid) {
        if (!ssid.length)
            return;
        if (revealedSsid === ssid) {
            hidePassword();
            return;
        }
        revealedSsid = ssid;
        revealedPw = "";
        revealResolved = false;
        revealProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "id", ssid];
        revealProc.running = true;
    }

    function hidePassword() {
        revealedSsid = "";
        revealedPw = "";
        revealResolved = false;
    }

    /**
     * Connects via `nmcli --ask`, feeding the password through stdin so the
     * secret never appears in the process command line (`/proc/<pid>/cmdline`
     * is world-readable for the whole connection attempt).
     */
    function connectWithPassword(ssid, pw) {
        if (connProc.running || !pw.length)
            return;
        connecting = true;
        connectFailed = false;
        attemptSsid = ssid;
        attemptWasKnown = knownProfiles[ssid] === true;
        pendingPw = pw;
        connProc.command = ["nmcli", "--ask", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    // ---- keyboard scaffold hooks (LinkDrillIn) ----

    function rowCount() {
        return root.netsSorted.length + root.hsRowCount;
    }

    /**
     * Confirm buttons on the expanded network row: 3 for a saved profile
     * (Connect/Disconnect, Show/Hide, Forget), 2 otherwise (no reveal).
     */
    function confirmCount(i) {
        if (i >= root.netsSorted.length)
            return 0;
        var net = root.netsSorted[i];
        var ssid = net ? (net.name || "") : "";
        if (ssid.length && root.expandedRow === ssid
            && (net.connected === true || root.knownProfiles[ssid] === true))
            return root.knownProfiles[ssid] === true ? 3 : 2;
        return 0;
    }

    /**
     * Return on the wifi list: fire the focused confirm button when one is
     * armed, else activate (expand / connect) the focused network, or drive
     * the hotspot rows. Connect/Disconnect at index 0, Show/Hide at 1 for
     * saved networks, Forget at the last index.
     */
    function activateAt(i) {
        var n = root.netsSorted.length;
        if (i >= n) {
            var row = i - n;
            if (row === 0) {
                hs.toggle();
            } else if (row === 1) {
                hsBlock.startEdit("name");
            } else {
                hsBlock.startEdit("pw");
            }
            return true;
        }
        var net = root.netsSorted[i];
        var ssid = net ? (net.name || "") : "";
        if (ssid.length && root.expandedRow === ssid) {
            var actions = [
                net.connected ? (it) => root.disconnectNetwork(it) : (it) => root.connectKnown(it)
            ];
            if (root.knownProfiles[ssid] === true)
                actions.push((it) => root.revealPassword(ssid));
            actions.push((it) => root.forgetNetwork(ssid));
            return root.confirmFire(net, actions);
        }
        root.activateNetwork(net);
        return true;
    }

    /**
     * Left/right off the network list: flip the hotspot toggle (left = off,
     * right = on). Network rows with no confirm row return false so vim h/l
     * fall through to back/enter.
     */
    function adjustExtra(dir) {
        if (root.kbIndex === root.netsSorted.length && root.wifiOn) {
            if ((dir > 0 && !hs.active) || (dir < 0 && hs.active))
                hs.toggle();
            return true;
        }
        return false;
    }

    /** Scan side effects: a fresh nmcli rescan; the 10s timer stops the spin. */
    function scanStarted() {
        if (root.wifiOn)
            rescanProc.running = true;
    }

    /** The reveal row follows the expanded row: closing one hides the other. */
    function onExpandedChanged() {
        if (root.revealedSsid !== root.expandedRow)
            root.hidePassword();
    }

    function onActivated() {
        root.refresh();
        root.hs.refresh();
    }

    function onDeactivated() {
        root.connectFailed = false;
        root.hs.edit = "";
        root.hidePassword();
    }

    onWifiOnChanged: if (!wifiOn) stopScan()

    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.active && root.wifiOn
        when: root.wifiDev !== null
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                root.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                root.knownProfiles = set;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            write(root.pendingPw + "\n");
            root.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.connecting = false;
            if (exitCode === 0) {
                root.expandedRow = "";
                root.pwDraft = "";
                root.connectFailed = false;
                root.refresh();
            } else {
                root.connectFailed = true;
                if (!root.attemptWasKnown && root.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", root.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    /**
     * A failed `nmcli dev wifi connect` still leaves a connection profile
     * named after the SSID behind; without deleting it the network would be
     * treated as known on the next click and silently fail forever.
     */
    Process {
        id: cleanupProc
        onExited: root.refresh()
    }

    /**
     * Drops a saved profile on Forget. The list refreshes on exit so the row
     * loses its known/connected state and its lock falls back to dim.
     */
    Process {
        id: forgetProc
        onExited: root.refresh()
    }

    /**
     * Reads one saved profile's PSK on demand. The result is held only as long as
     * the row stays open; an empty result means the profile is open or stores no
     * recoverable secret, surfaced by the row as a plain note.
     */
    Process {
        id: revealProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.revealedPw = this.text.replace(/\n+$/, "");
                root.revealResolved = true;
            }
        }
    }

    onNetsChanged: if (active) secRefresh.restart()

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (root.active) secProc.running = true
    }

    /**
     * Keys the network list by SSID so a rescan diffs into the existing rows
     * rather than tearing every delegate down and rebuilding it. Delegates keep
     * their identity across scans, so the inline confirm or password row stays
     * open under the network the user tapped.
     */
    ScriptModel {
        id: netModel
        objectProp: "name"
        values: root.netsSorted
    }

    Row {
        anchors.right: root.headerBar.right
        anchors.verticalCenter: root.headerBar.verticalCenter
        spacing: 12 * root.s

        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.wifiOn
            width: 16 * root.s
            height: 16 * root.s

            HoverIcon {
                id: reloadGlyph
                anchors.fill: parent
                name: "reboot"
                color: root.scanning ? Theme.flameGlow : Theme.iconDim
                hoverColor: root.scanning ? Theme.flameGlow : Theme.cream
                stroke: 1.8
                hitPad: 6 * root.s
                onClicked: root.scanning ? root.stopScan() : root.startScan()

                RotationAnimator {
                    target: reloadGlyph
                    running: root.scanning
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) reloadGlyph.rotation = 0
                }
            }
        }

        LinkToggle {
            s: root.s
            anchors.verticalCenter: parent.verticalCenter
            on: root.wifiOn
            onToggled: {
                if (typeof Networking !== "undefined" && Networking)
                    Networking.wifiEnabled = !Networking.wifiEnabled;
            }
        }
    }

    LinkListFrame {
        id: listFrame
        anchors.top: root.dividerBar.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        emptyText: "Searching networks…"
        listEmpty: root.wifiOn && root.nets.length === 0
        listMaxH: 280 * root.s
        listMinH: 26 * root.s
        listHidden: !root.wifiOn

        Repeater {
            model: netModel

            WifiNetRow {
                s: root.s
                secured: root.isSecured((modelData && modelData.name) || "")
                known: root.knownProfiles[(modelData && modelData.name) || ""] === true
                expanded: (modelData && modelData.name) ? root.expandedRow === modelData.name : false
                focused: root.kbIndex === index
                confirmFocus: root.confirmFocus
                revealed: root.revealedSsid === ((modelData && modelData.name) || "")
                revealedPw: root.revealedPw
                revealResolved: root.revealResolved
                pwDraft: root.pwDraft
                connecting: root.connecting
                connectFailed: root.connectFailed
                list: listFrame
                onRequestActivate: root.activateNetwork(modelData)
                onRequestConnectKnown: root.connectKnown(modelData)
                onRequestDisconnect: root.disconnectNetwork(modelData)
                onRequestForget: root.forgetNetwork((modelData && modelData.name) || "")
                onRequestReveal: root.revealPassword((modelData && modelData.name) || "")
                onRequestConnectWithPassword: function(pw) {
                    root.connectWithPassword((modelData && modelData.name) || "", pw);
                }
                onRequestFocus: root.kbIndex = index
            }
        }
    }

    WifiHotspot {
        id: hsBlock
        anchors.top: listFrame.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.wifiOn
        height: root.wifiOn ? implicitHeight + 9 * root.s : 0
        clip: true
        s: root.s
        active: hs.active
        busy: hs.busy
        name: hs.name
        pw: hs.pw
        edit: hs.edit
        draft: hs.draft
        kbIndex: root.kbIndex
        toggleIndex: root.hsToggleIndex
        onToggle: hs.toggle()
        onCommitEdit: hs.commitEdit()
        onEditRequested: function(f, v) { hs.draft = v; hs.edit = f; }
        onDraftEdited: function(t) { hs.draft = t }
        onFocusRequested: function(i) { root.kbIndex = i }
    }

    HotspotControl {
        id: hs
        iface: root.hsIface
    }
}

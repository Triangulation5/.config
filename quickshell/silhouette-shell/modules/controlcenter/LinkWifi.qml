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
 * inline password row that connects through `nmcli dev wifi connect`. The pill
 * body provides the surface material, so this item draws no background.
 */
Item {
    id: root

    property real s: 1.1
    property bool active: false

    signal back()

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var nets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var netsSorted: nets.slice().sort(function(a, b) {
        return ((b ? b.signalStrength : 0) || 0) - ((a ? a.signalStrength : 0) || 0)
    })
    readonly property var activeNet: nets.find(function(n) { return n && n.connected }) || null
    readonly property string statusText: !wifiOn ? "Off"
        : (activeNet ? (activeNet.name || "Connected") : "Not connected")

    property var securityMap: ({})
    property var knownProfiles: ({})
    property string expandedSsid: ""
    property bool connecting: false
    property bool connectFailed: false
    property bool scanning: false

    /**
     * SSID of the saved network whose stored password is currently shown, plus
     * the revealed secret itself. Keying both to one SSID keeps the reveal local
     * to the row the user asked about and lets `revealResolved` distinguish "not
     * yet read" from "read but empty" so an open profile shows a clear message.
     */
    property string revealedSsid: ""
    property string revealedPw: ""
    property bool revealResolved: false

    readonly property string hsCon: "silhouette-shell"
    readonly property string hsIface: wifiDev ? (wifiDev.name || "wlan0") : "wlan0"
    property string hsName: "SilhouetteShell"
    property string hsPw: ""
    property bool hsActive: false
    property bool hsBusy: false
    property string hsEdit: ""
    property string hsDraft: ""

    /**
     * Draft of the password being typed for `expandedSsid`. Lives on the root so
     * the field can restore itself from the draft if the keyed list model swaps
     * the delegate's network object under it on a rescan.
     */
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    implicitHeight: hsBlock.y + hsBlock.height

    /**
     * Keyboard focus over the network rows and hotspot block; -1 until the
     * first arrow so the first press lands on the top network.
     */
    property int kbIndex: -1

    /**
     * Hotspot rows follow the network list in the keyboard cursor: index
     * offset 0 = the hotspot toggle, 1 = network name, 2 = password. The
     * whole block is skipped while wifi is off (it is hidden then).
     */
    readonly property int hsRowCount: root.wifiOn ? 3 : 0
    readonly property int hsToggleIndex: root.netsSorted.length

    function kbMove(dir) {
        var n = root.netsSorted.length;
        var total = n + root.hsRowCount;
        if (total === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= total)
            kbIndex = 0;
        else
            kbIndex = (kbIndex + dir + total) % total;
        return true;
    }

    /**
     * Return on the wifi list: fire the focused confirm button when one is
     * armed, else activate (expand / connect) the focused network. Connect/
     * Disconnect at index 0, Show/Hide at 1 for saved networks, Forget at the
     * last index. Hotspot rows toggle the AP or start an inline name/password
     * edit.
     */
    function kbActivate() {
        var n = root.netsSorted.length;
        var total = n + root.hsRowCount;
        if (total === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= total)
            kbIndex = 0;
        if (kbIndex >= n) {
            var row = kbIndex - n;
            if (row === 0) {
                root.toggleHotspot();
            } else if (row === 1) {
                hsBlock.startEdit("name");
            } else {
                hsBlock.startEdit("pw");
            }
            return true;
        }
        var net = root.netsSorted[kbIndex];
        var ssid = net ? (net.name || "") : "";
        if (ssid.length && root.expandedSsid === ssid && root.confirmFocus >= 0) {
            if (root.confirmFocus === 0) {
                if (net.connected) root.disconnectNetwork(net);
                else root.connectKnown(net);
            } else if (root.confirmFocus === 1) {
                if (root.knownProfiles[ssid] === true) root.revealPassword(ssid);
                else root.forgetNetwork(ssid);
            } else {
                root.forgetNetwork(ssid);
            }
            return true;
        }
        root.activateNetwork(net);
        return true;
    }

    /**
     * Confirm-button focus for the expanded row: 0 = primary (Connect/
     * Disconnect), 1 = Show/Hide (saved only) or Forget, 2 = Forget (saved
     * only). Resets whenever the expanded row changes.
     */
    property int confirmFocus: -1

    /**
     * Left/right on the wifi list: cycle the expanded row's confirm buttons,
     * or flip the hotspot toggle (left = off, right = on). Returns false when
     * there is nothing to adjust, so vim h/l fall through to back/enter.
     */
    function kbAdjust(dir) {
        var n = root.netsSorted.length;
        if (kbIndex >= 0 && kbIndex < n) {
            var net = root.netsSorted[kbIndex];
            var ssid = net ? (net.name || "") : "";
            if (ssid.length && root.expandedSsid === ssid
                && (net.connected === true || root.knownProfiles[ssid] === true)) {
                var count = root.knownProfiles[ssid] === true ? 3 : 2;
                if (confirmFocus < 0)
                    confirmFocus = 0;
                else
                    confirmFocus = (confirmFocus + dir + count) % count;
                return true;
            }
            return false;
        }
        if (kbIndex === n && root.wifiOn) {
            if ((dir > 0 && !root.hsActive) || (dir < 0 && root.hsActive))
                root.toggleHotspot();
            return true;
        }
        return false;
    }

    /**
     * Backspace on the wifi list: collapse the expanded row before the caller
     * pops the subview. Returns true when a row was open and got collapsed.
     */
    function kbBack() {
        if (root.expandedSsid.length) {
            root.expandedSsid = "";
            return true;
        }
        return false;
    }

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
        if (expandedSsid === ssid && ssid.length) {
            expandedSsid = "";
            return;
        }
        if (net.connected || knownProfiles[ssid] === true) {
            connectFailed = false;
            pwDraft = "";
            expandedSsid = ssid;
            return;
        }
        if (!isSecured(ssid)) {
            expandedSsid = "";
            if (typeof net.connect === "function")
                net.connect();
            refresh();
            return;
        }
        connectFailed = false;
        pwDraft = "";
        expandedSsid = ssid;
    }

    /**
     * Connects a saved profile from its confirm row. Known profiles connect by
     * name through the device so no password prompt is needed.
     */
    function connectKnown(net) {
        if (!net)
            return;
        expandedSsid = "";
        if (typeof net.connect === "function")
            net.connect();
        refresh();
    }

    function disconnectNetwork(net) {
        if (!net)
            return;
        expandedSsid = "";
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
        expandedSsid = "";
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

    /**
     * Reload pulse: forces a fresh nmcli rescan and spins the control for up to
     * 10s. The device scanner already runs while the drill-in is open, so the
     * list never empties; this only refreshes results and drives the spinner.
     */
    function startScan() {
        if (!wifiOn)
            return;
        scanning = true;
        rescanProc.running = true;
        scanTimer.restart();
    }

    function stopScan() {
        scanning = false;
        scanTimer.stop();
    }

    onActiveChanged: {
        if (active) {
            refresh();
            refreshHotspot();
        } else {
            stopScan();
            expandedSsid = "";
            confirmFocus = -1;
            kbIndex = -1;
            connectFailed = false;
            hsEdit = "";
            hidePassword();
        }
    }

    onWifiOnChanged: if (!wifiOn) stopScan()

    onExpandedSsidChanged: {
        confirmFocus = -1;
        if (revealedSsid !== expandedSsid) hidePassword();
    }

    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.active && root.wifiOn
        when: root.wifiDev !== null
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: root.stopScan()
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    /**
     * Brings the shared AP up with the current name and password, creating the
     * persistent connection on first use and modifying it on later changes. Name
     * and password are passed as positional arguments, never spliced into the
     * shell string, so an odd character cannot break or inject the command.
     */
    function applyHotspot() {
        if (hsBusy || hsPw.length < 8)
            return;
        hsBusy = true;
        hsApplyProc.command = ["sh", "-c",
            'c="' + hsCon + '"; '
            + 'if nmcli -t connection show "$c" >/dev/null 2>&1; then '
            +   'nmcli connection modify "$c" 802-11-wireless.ssid "$1" 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2"; '
            + 'else '
            +   'nmcli connection add type wifi ifname "$3" con-name "$c" autoconnect no 802-11-wireless.ssid "$1" 802-11-wireless.mode ap 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2" ipv4.method shared; '
            + 'fi; '
            + 'nmcli connection up "$c"',
            "sh", hsName, hsPw, hsIface];
        hsApplyProc.running = true;
    }

    function stopHotspot() {
        if (hsBusy)
            return;
        hsBusy = true;
        hsDownProc.running = true;
    }

    /**
     * Flips the shared hotspot: stop when active, else generate a password
     * (when none is set) and bring the AP up. Shared by the toggle and the
     * keyboard cursor.
     */
    function toggleHotspot() {
        if (hsBusy)
            return;
        if (hsActive) {
            stopHotspot();
        } else {
            if (hsPw.length < 8)
                hsPw = generatePw();
            applyHotspot();
        }
    }

    function refreshHotspot() {
        hsStateProc.running = true;
        hsReadProc.running = true;
    }

    /**
     * Commits an inline name or password edit, ignoring a password shorter than
     * the 8-character WPA2 minimum. A live hotspot is re-applied so the change
     * takes effect at once.
     */
    function commitHotspotEdit() {
        if (hsEdit === "name") {
            if (hsDraft.length)
                hsName = hsDraft;
        } else if (hsEdit === "pw") {
            if (hsDraft.length >= 8)
                hsPw = hsDraft;
        }
        hsEdit = "";
        if (hsActive)
            applyHotspot();
    }

    /**
     * Builds an eight-character WPA2 password from an unambiguous alphabet, used
     * when the hotspot is switched on before a password has been set.
     */
    function generatePw() {
        var cs = "abcdefghijkmnpqrstuvwxyz23456789";
        var s = "";
        for (var i = 0; i < 8; i++)
            s += cs.charAt(Math.floor(Math.random() * cs.length));
        return s;
    }

    Process {
        id: hsApplyProc
        onExited: {
            root.hsBusy = false;
            root.refreshHotspot();
        }
    }

    Process {
        id: hsDownProc
        command: ["nmcli", "connection", "down", root.hsCon]
        onExited: {
            root.hsBusy = false;
            root.refreshHotspot();
        }
    }

    Process {
        id: hsStateProc
        command: ["sh", "-c", "nmcli -t -f NAME connection show --active | grep -qx \"$1\" && echo on || echo off", "sh", root.hsCon]
        stdout: StdioCollector {
            onStreamFinished: root.hsActive = this.text.trim() === "on"
        }
    }

    Process {
        id: hsReadProc
        command: ["nmcli", "-t", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "connection", "show", root.hsCon]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length >= 1 && lines[0].length)
                    root.hsName = lines[0];
                if (lines.length >= 2 && lines[1].length)
                    root.hsPw = lines[1];
            }
        }
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
                root.expandedSsid = "";
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
                text: "· " + root.statusText
                color: root.activeNet ? Theme.vermLit : Theme.faint
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
                visible: root.wifiOn
                width: 16 * root.s
                height: 16 * root.s

                GlyphIcon {
                    id: reloadGlyph
                    anchors.fill: parent
                    name: "reboot"
                    color: root.scanning ? Theme.flameGlow : (reloadArea.containsMouse ? Theme.cream : Theme.iconDim)
                    stroke: 1.8

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

                MouseArea {
                    id: reloadArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scanning ? root.stopScan() : root.startScan()
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

    Item {
        id: listFrame
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.wifiOn ? Math.min(Math.max(netCol.implicitHeight, 26 * root.s), 280 * root.s) : 0

        Text {
            anchors.centerIn: parent
            visible: root.wifiOn && root.nets.length === 0
            text: "Searching networks…"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        Flickable {
            id: netFlick
            anchors.fill: parent
            contentHeight: netCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: netCol
                width: netFlick.width
                spacing: 2 * root.s

                Repeater {
                    model: netModel

                    WifiNetRow {
                        s: root.s
                        secured: root.isSecured((modelData && modelData.name) || "")
                        known: root.knownProfiles[(modelData && modelData.name) || ""] === true
                        expanded: (modelData && modelData.name) ? root.expandedSsid === modelData.name : false
                        focused: root.kbIndex === index
                        confirmFocus: root.confirmFocus
                        revealed: root.revealedSsid === ((modelData && modelData.name) || "")
                        revealedPw: root.revealedPw
                        revealResolved: root.revealResolved
                        pwDraft: root.pwDraft
                        connecting: root.connecting
                        connectFailed: root.connectFailed
                        flick: netFlick
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
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: netFlick
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
        active: root.hsActive
        busy: root.hsBusy
        name: root.hsName
        pw: root.hsPw
        edit: root.hsEdit
        draft: root.hsDraft
        kbIndex: root.kbIndex
        toggleIndex: root.hsToggleIndex
        onToggle: root.toggleHotspot()
        onCommitEdit: root.commitHotspotEdit()
        onEditRequested: function(f, v) { root.hsDraft = v; root.hsEdit = f; }
        onDraftEdited: function(t) { root.hsDraft = t }
        onFocusRequested: function(i) { root.kbIndex = i }
    }
}

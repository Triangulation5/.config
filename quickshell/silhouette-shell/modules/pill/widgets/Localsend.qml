pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import qs.components.layout

/**
 * 送 SEND — Localsend airdrop surface. Scans the local network for devices
 * and sends the queued file with one tap. The header shows kanji, label,
 * a live device-count badge, and a refresh button. A file pill appears when
 * a path is queued. The device list uses rounded rows with smooth hover
 * transitions, a smartphone glyph, and a Send action chip on selection.
 * Scanning pulses a dot; empty states show a centred glyph and message.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 14

    property string sendFile: ""
    property var devices: []
    property string status: ""
    property bool scanning: false
    property bool sending: false
    property bool installed: true
    property int selectedIndex: 0

    function refresh() {
        if (scanProc.running) return;
        root.scanning = true;
        root.devices = [];
        root.status = "";
        scanProc.running = true;
    }

    /** Keyboard: move selection up/down through the device list. */
    function move(dir) {
        if (root.devices.length === 0) return;
        root.selectedIndex = Math.max(0, Math.min(root.devices.length - 1, root.selectedIndex + dir));
    }

    /** Keyboard: send to the selected device. */
    function activate() {
        if (root.devices.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= root.devices.length)
            return;
        root.sendTo(root.selectedIndex);
    }

    function sendTo(index) {
        if (root.sending || index < 0 || index >= root.devices.length || !root.sendFile.length)
            return;
        root.sending = true;
        root.status = "Sending…";
        var dev = root.devices[index];
        sendProc.command = ["localsend", "send", root.sendFile, "--to", dev.id || dev.fingerprint || dev.ip || dev.name];
        sendProc.running = true;
    }

    onActiveChanged: {
        if (active) {
            root.status = "";
            root.sending = false;
            root.selectedIndex = 0;
            root.refresh();
        }
    }

    Process {
        id: scanProc
        command: ["localsend", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                try {
                    var parsed = JSON.parse(this.text);
                    root.devices = Array.isArray(parsed) ? parsed : (parsed.devices || []);
                } catch (e) {
                    root.devices = [];
                }
                if (root.devices.length === 0)
                    root.status = root.sendFile.length ? "No devices found" : "Drop a file to send";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                root.devices = [];
                var txt = this.text.toLowerCase();
                if (txt.indexOf("not found") !== -1 || txt.indexOf("command not found") !== -1) {
                    root.installed = false;
                    root.status = "Localsend not installed";
                } else {
                    root.status = root.sendFile.length ? "No devices found" : "Drop a file to send";
                }
            }
        }
    }

    Process {
        id: sendProc
        onExited: {
            root.sending = false;
            if (exitCode === 0) {
                root.status = "Sent ✓";
                Qt.callLater(function() { root.requestClose(); });
            } else {
                root.status = "Send failed";
            }
        }
    }

    ameForm: open ? "soul" : "off"
    amePoint: sendHeader.soulPoint(root)

    implicitHeight: content.implicitHeight

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        /* ── Header with inline refresh ── */
        Row {
            id: headerRow
            width: parent.width
            height: 24 * root.s

            SurfaceHeader {
                id: sendHeader
                width: parent.width - (root.sendFile.length > 0 ? 0 : 40 * root.s)
                kanji: "送"
                label: "SEND"
                badge: root.scanning ? "Scanning…"
                    : (root.devices.length > 0 ? root.devices.length + (root.devices.length === 1 ? " device" : " devices") : "")
                badgeColor: root.scanning ? Theme.flameGlow : Theme.dim
                s: root.s
            }

            /* Refresh button — only when no file is queued */
            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.sendFile.length > 0 ? 0 : 36 * root.s
                height: root.sendFile.length > 0 ? 0 : 22 * root.s
                visible: height > 0

                Row {
                    anchors.centerIn: parent
                    spacing: 3 * root.s

                    GlyphIcon {
                        id: refreshIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11 * root.s; height: 11 * root.s
                        name: "reboot"
                        color: refreshArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.8
                        rotation: 0

                        RotationAnimation on rotation {
                            running: root.scanning
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite
                            easing.type: Easing.Linear
                        }

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    anchors.margins: -4 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        /* ── File pill — only visible when a path is queued ── */
        Item {
            width: parent.width
            height: root.sendFile.length > 0 ? 24 * root.s + 36 * root.s : 0
            visible: height > 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 36 * root.s
                radius: 10 * root.s
                color: Qt.rgba(0.94, 0.55, 0.38, 0.08)
                border.width: 1
                border.color: Qt.rgba(0.94, 0.55, 0.38, 0.15)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s; height: 13 * root.s
                        name: "download"
                        color: Theme.flameGlow
                        stroke: 2.2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sendFile.split("/").pop()
                        color: Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                        width: parent.width - 60 * root.s
                    }
                }
            }
        }

        Item { width: 1; height: root.sendFile.length > 0 ? 10 * root.s : 6 * root.s }

        /* ── Scanning row — pulsing dot + label ── */
        Item {
            width: parent.width
            height: root.scanning ? 32 * root.s : 0
            visible: height > 0

            Row {
                anchors.centerIn: parent
                spacing: 10 * root.s

                Rectangle {
                    id: scanDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7 * root.s; height: 7 * root.s; radius: 3.5 * root.s
                    color: Theme.flameGlow
                    opacity: 0.4

                    SequentialAnimation on opacity {
                        running: root.scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.95; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Looking for devices…"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.Medium
                }
            }
        }

        /* ── Empty / status state ── */
        Item {
            width: parent.width
            height: (root.status.length > 0 && root.devices.length === 0 && !root.scanning)
                ? Math.max(72 * root.s, statusText.implicitHeight + 34 * root.s) : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: 8 * root.s

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.installed && Flags.showGlyphs
                    width: 22 * root.s; height: 22 * root.s
                    name: "share"
                    color: Theme.ghost
                    stroke: 1.6
                    opacity: 0.25
                }

                Text {
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.parent.width - 24 * root.s
                    text: root.status
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                /* Install hint pill */
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.installed
                    width: installHint.implicitWidth + 24 * root.s
                    height: 28 * root.s
                    radius: 14 * root.s
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Theme.frameBorder

                    Text {
                        id: installHint
                        anchors.centerIn: parent
                        text: "flatpak install localsend"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        /* ── Device list ── */
        ListView {
            id: devList
            width: parent.width
            height: count > 0 ? Math.min(count * 50 * root.s + (count - 1) * 2 * root.s, 260 * root.s) : 0
            visible: height > 0 && !root.scanning
            spacing: 2 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices.length
            interactive: count * 50 * root.s > 260 * root.s

            delegate: Rectangle {
                id: devRow
                required property int index
                width: devList.width
                height: 50 * root.s
                radius: 10 * root.s
                color: index === root.selectedIndex ? Theme.frameBg
                    : (devArea.containsMouse ? Qt.rgba(1, 1, 1, 0.035) : "transparent")
                border.width: index === root.selectedIndex ? 1 : 0
                border.color: index === root.selectedIndex ? Theme.frameBorder : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                readonly property var dev: root.devices[index]

                MouseArea {
                    id: devArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: root.selectedIndex = index
                    onClicked: root.sendTo(index)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16 * root.s; height: 16 * root.s
                        name: "smartphone"
                        color: index === root.selectedIndex ? Theme.cream : Theme.iconDim
                        stroke: 2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s

                        Text {
                            text: devRow.dev.name || devRow.dev.hostname || devRow.dev.alias || "Unknown device"
                            color: index === root.selectedIndex ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: devList.width - 120 * root.s
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            visible: (devRow.dev.hostname || devRow.dev.ip || devRow.dev.model || "").length > 0
                            text: devRow.dev.model
                                || (devRow.dev.hostname && devRow.dev.ip ? devRow.dev.hostname + " · " + devRow.dev.ip
                                : (devRow.dev.hostname || devRow.dev.ip || ""))
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: devList.width - 120 * root.s
                        }
                    }
                }

                /* Send action chip — right-aligned, only on selected row */
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.sendFile.length > 0 && index === root.selectedIndex
                    width: sendPillText.implicitWidth + 16 * root.s
                    height: 26 * root.s
                    radius: 13 * root.s
                    color: root.sending ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.94, 0.55, 0.38, 0.12)
                    border.width: 1
                    border.color: root.sending ? Theme.frameBorder : Qt.rgba(0.94, 0.55, 0.38, 0.18)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: sendPillText
                        anchors.centerIn: parent
                        text: root.sending ? "…" : "Send"
                        color: root.sending ? Theme.subtle : Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        WheelScroller {
            anchors.fill: devList
            s: root.s
            flick: devList
            visible: height > 0 && devList.interactive
        }

        /* Bottom breathing room when devices are shown */
        Item {
            width: parent.width
            height: root.devices.length > 0 ? 6 * root.s : 0
            visible: height > 0
        }
    }
}

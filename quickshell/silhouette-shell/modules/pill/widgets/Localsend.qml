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
 * 送 SEND — Localsend airdrop surface styled after the Battery and System
 * surfaces. A kanji header with a device-count badge, a file-info stat row when
 * a path is queued, a hairline, and a scrollable device list where each row
 * carries a phone glyph, the device name, a subline and a Send pill on the
 * selected row. Refresh lives in the header; scanning replaces the list with a
 * centred spinner. Ame rests as a soul above the kanji.
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

    function move(dir) {
        if (root.devices.length === 0) return;
        root.selectedIndex = Math.max(0, Math.min(root.devices.length - 1, root.selectedIndex + dir));
    }

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
                    root.status = "Localsend not installed\nInstall: flatpak install localsend";
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

    /* ── Ame ── */

    ameForm: open ? "soul" : "off"
    amePoint: sendHeader.soulPoint(root)

    implicitHeight: content.implicitHeight

    /* ── Layout ── */

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        /* Header */
        SurfaceHeader {
            id: sendHeader
            kanji: "送"
            label: "SEND"
            badge: !root.scanning
                ? (root.devices.length > 0 ? root.devices.length + (root.devices.length === 1 ? " device" : " devices")
                    : "")
                : ""
            s: root.s
        }

        /** Refresh spinner sits beside the badge area. */
        Item {
            anchors.right: parent.right
            anchors.top: parent.top
            width: 16 * root.s
            height: 22 * root.s

            GlyphIcon {
                anchors.centerIn: parent
                width: 16 * root.s; height: 16 * root.s
                name: "reboot"
                color: root.scanning ? Theme.flameGlow : (refreshArea.containsMouse ? Theme.cream : Theme.iconDim)
                stroke: 1.8

                RotationAnimator {
                    target: parent
                    running: root.scanning
                    from: 0; to: 360; duration: 1000
                    loops: Animation.Infinite
                }
            }

            MouseArea {
                id: refreshArea
                anchors.fill: parent
                anchors.margins: -6 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
            }
        }

        /* File info — stat row when a file is queued */
        Item {
            width: parent.width
            height: root.sendFile.length > 0 ? 24 * root.s : 0
            visible: root.sendFile.length > 0
            clip: true

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * root.s; height: 11 * root.s
                    name: "download"; color: Theme.flameGlow; stroke: 2.2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sendFile.split("/").pop()
                    color: Theme.flameGlow
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                    width: parent.parent.width - 40 * root.s
                }
            }
        }

        /* Hairline */
        Hairline { s: root.s }

        Item { width: 1; height: 12 * root.s }

        /* Status / empty state */
        Item {
            width: parent.width
            height: (root.status.length > 0 && root.devices.length === 0 && !root.scanning)
                ? Math.max(80 * root.s, statusText.implicitHeight + 40 * root.s) : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: 6 * root.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Flags.showGlyphs
                    text: root.installed ? "送" : "!"
                    color: Theme.ghost
                    opacity: 0.35
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 28 * root.s
                }

                Text {
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.parent.width - 20 * root.s
                    text: root.status
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        /* Scanning spinner */
        Item {
            width: parent.width
            height: root.scanning ? 80 * root.s : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: 10 * root.s

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 18 * root.s; height: 18 * root.s; radius: 9 * root.s
                    color: "transparent"
                    border.width: 2; border.color: Theme.flameGlow
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Looking for devices…"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.Medium
                }
            }
        }

        /* Device list */
        ListView {
            id: devList
            width: parent.width
            height: count > 0 ? Math.min(count * 46 * root.s + (count - 1) * 2 * root.s, 260 * root.s) : 0
            visible: height > 0 && !root.scanning
            spacing: 2 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices.length
            interactive: count * 46 * root.s > 260 * root.s

            delegate: Rectangle {
                id: devRow
                required property int index
                width: devList.width
                height: 46 * root.s
                radius: 10 * root.s
                color: index === root.selectedIndex ? Theme.frameBg
                    : (devArea.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
                border.width: index === root.selectedIndex ? 1 : 0
                border.color: index === root.selectedIndex ? Theme.frameBorder : "transparent"

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
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    spacing: 12 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16 * root.s; height: 16 * root.s
                        name: "smartphone"
                        color: index === root.selectedIndex ? Theme.cream : Theme.iconDim
                        stroke: 2
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s

                        Text {
                            text: devRow.dev.name || devRow.dev.hostname || devRow.dev.alias || "Unknown device"
                            color: index === root.selectedIndex ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: devList.width - 100 * root.s
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
                            width: devList.width - 100 * root.s
                        }
                    }

                    Item { width: 1; height: 1 }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.sendFile.length > 0 && index === root.selectedIndex
                        width: sendPillText.implicitWidth + 16 * root.s
                        height: 24 * root.s
                        radius: 12 * root.s
                        color: root.sending ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.94, 0.55, 0.38, 0.12)
                        border.width: 1
                        border.color: root.sending ? Theme.frameBorder : Qt.rgba(0.94, 0.55, 0.38, 0.18)

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
        }

        WheelScroller {
            anchors.fill: devList
            s: root.s
            flick: devList
            visible: height > 0 && devList.interactive
        }
    }
}

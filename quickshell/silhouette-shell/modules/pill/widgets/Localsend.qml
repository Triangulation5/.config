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
 * and sends the queued file with one tap. All dimensions are proportional to
 * the content column width so the surface scales uniformly. The header shows
 * 送 in file mode / 捜 while scanning, a live device-count badge, and an inline
 * refresh button. A file pill appears when a path is queued.  Device rows use
 * rounded cards with smooth hover transitions and a Send action chip.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 14

    /** Content column width — every dimension keys off this. */
    readonly property real cw: width - (mLeft + mRight) * s

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

        /* ── Header row — kanji, label, badge, refresh ── */
        Item {
            width: parent.width
            height: cw * 0.073

            SurfaceHeader {
                id: sendHeader
                /** 送 while a file is queued, 捜 while scanning, 送 otherwise. */
                readonly property string glyph: root.sendFile.length > 0 ? "送"
                    : (root.scanning ? "捜" : "送")
                width: parent.width - (root.sendFile.length > 0 ? 0 : cw * 0.122)
                kanji: glyph
                label: "SEND"
                badge: root.scanning ? "Scanning…"
                    : (root.devices.length > 0 ? root.devices.length + (root.devices.length === 1 ? " device" : " devices") : "")
                badgeColor: root.scanning ? Theme.flameGlow : Theme.dim
                s: root.s
            }

            /* Inline refresh — only when no file is queued */
            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.sendFile.length > 0 ? 0 : cw * 0.110
                height: root.sendFile.length > 0 ? 0 : cw * 0.067
                visible: height > 0

                GlyphIcon {
                    id: refreshIcon
                    anchors.centerIn: parent
                    width: cw * 0.034; height: cw * 0.034
                    name: "reboot"
                    color: refreshArea.containsMouse ? Theme.cream : Theme.iconDim
                    stroke: 1.8

                    RotationAnimation on rotation {
                        running: root.scanning
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite
                        easing.type: Easing.Linear
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
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

        /* ── Hairline ── */
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        /* ── File pill ── */
        Item {
            width: parent.width
            height: root.sendFile.length > 0 ? cw * 0.183 : 0
            visible: height > 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: cw * 0.110
                radius: cw * 0.030
                color: Qt.rgba(0.94, 0.55, 0.38, 0.08)
                border.width: 1
                border.color: Qt.rgba(0.94, 0.55, 0.38, 0.15)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: cw * 0.037
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cw * 0.024

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: cw * 0.040; height: cw * 0.040
                        name: "download"
                        color: Theme.flameGlow
                        stroke: 2.2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sendFile.split("/").pop()
                        color: Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: cw * 0.034
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                        width: parent.width - cw * 0.183
                    }
                }
            }
        }

        Item { width: 1; height: root.sendFile.length > 0 ? cw * 0.030 : cw * 0.018 }

        /* ── Scanning row — pulsing dot + label ── */
        Item {
            width: parent.width
            height: root.scanning ? cw * 0.098 : 0
            visible: height > 0

            Row {
                anchors.centerIn: parent
                spacing: cw * 0.030

                Rectangle {
                    id: scanDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: cw * 0.021; height: cw * 0.021; radius: width / 2
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
                    font.pixelSize: cw * 0.032
                    font.weight: Font.Medium
                }
            }
        }

        /* ── Empty / status state ── */
        Item {
            width: parent.width
            height: (root.status.length > 0 && root.devices.length === 0 && !root.scanning)
                ? Math.max(cw * 0.220, statusText.implicitHeight + cw * 0.104) : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: cw * 0.024

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.installed && Flags.showGlyphs
                    width: cw * 0.067; height: cw * 0.067
                    name: "share"
                    color: Theme.ghost
                    stroke: 1.6
                    opacity: 0.25
                }

                Text {
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.parent.width - cw * 0.073
                    text: root.status
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: cw * 0.032
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.installed
                    width: installHint.implicitWidth + cw * 0.073
                    height: cw * 0.085
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Theme.frameBorder

                    Text {
                        id: installHint
                        anchors.centerIn: parent
                        text: "flatpak install localsend"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: cw * 0.029
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
            height: count > 0 ? Math.min(count * cw * 0.152 + (count - 1) * cw * 0.006, cw * 0.793) : 0
            visible: height > 0 && !root.scanning
            spacing: cw * 0.006
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices.length
            interactive: count * cw * 0.152 > cw * 0.793

            delegate: Rectangle {
                id: devRow
                required property int index
                width: devList.width
                height: cw * 0.152
                radius: cw * 0.030
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
                    anchors.leftMargin: cw * 0.037
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cw * 0.030

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: cw * 0.049; height: cw * 0.049
                        name: "smartphone"
                        color: index === root.selectedIndex ? Theme.cream : Theme.iconDim
                        stroke: 2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: cw * 0.006

                        Text {
                            text: devRow.dev.name || devRow.dev.hostname || devRow.dev.alias || "Unknown device"
                            color: index === root.selectedIndex ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: cw * 0.035
                            font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: devList.width - cw * 0.366
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            visible: (devRow.dev.hostname || devRow.dev.ip || devRow.dev.model || "").length > 0
                            text: devRow.dev.model
                                || (devRow.dev.hostname && devRow.dev.ip ? devRow.dev.hostname + " · " + devRow.dev.ip
                                : (devRow.dev.hostname || devRow.dev.ip || ""))
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: cw * 0.027
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: devList.width - cw * 0.366
                        }
                    }
                }

                /* Send action chip */
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: cw * 0.030
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.sendFile.length > 0 && index === root.selectedIndex
                    width: sendPillText.implicitWidth + cw * 0.049
                    height: cw * 0.079
                    radius: height / 2
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
                        font.pixelSize: cw * 0.032
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

        Item {
            width: parent.width
            height: root.devices.length > 0 ? cw * 0.018 : 0
            visible: height > 0
        }
    }
}

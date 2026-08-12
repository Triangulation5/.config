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
 * 送 SEND — Localsend airdrop surface. Scans the local network for peer devices
 * and sends the queued file with one tap. The header swaps between 送 (file
 * queued) and 捜 (scanning). A warm gradient file pill sits beneath the header
 * when a path is queued, echoing the vermilion flame tokens. Device rows use
 * the Link surface's row style: rounded cards with a glyph, name, subtitle,
 * and a Send action chip. The empty state centres a large ghost 送 glyph and
 * message. A radar pulse animates while scanning.
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

    property real sentPulse: 0

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
                    root.status = root.sendFile.length ? "No devices found" : "Drop a file to share";
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
                    root.status = root.sendFile.length ? "No devices found" : "Drop a file to share";
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
                root.sentPulse = 1;
                pulseAnim.restart();
                Qt.callLater(function() { root.requestClose(); });
            } else {
                root.status = "Send failed";
            }
        }
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: root; property: "sentPulse"; to: 1; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "sentPulse"; to: 0; duration: 400; easing.type: Easing.OutCubic }
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

        /* ── Header ── */
        Item {
            width: parent.width
            height: 24 * root.s

            SurfaceHeader {
                id: sendHeader
                readonly property string glyph: root.sendFile.length > 0 ? "送"
                    : (root.scanning ? "捜" : "送")
                width: parent.width - (root.sendFile.length > 0 ? 0 : 40 * root.s)
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
                width: root.sendFile.length > 0 ? 0 : 36 * root.s
                height: root.sendFile.length > 0 ? 0 : 22 * root.s
                visible: height > 0

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 11 * root.s; height: 11 * root.s
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

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        /* ── File pill — warm gradient card ── */
        Item {
            width: parent.width
            height: root.sendFile.length > 0 ? 52 * root.s + 10 * root.s : 0
            visible: height > 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 52 * root.s
                radius: 10 * root.s
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.94, 0.55, 0.38, 0.09) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.94, 0.55, 0.38, 0.04) }
                }
                border.width: 1
                border.color: Qt.rgba(0.94, 0.55, 0.38, 0.18)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * root.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28 * root.s; height: 28 * root.s
                        radius: 7 * root.s
                        color: Qt.rgba(0.94, 0.55, 0.38, 0.15)

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 14 * root.s; height: 14 * root.s
                            name: "download"
                            color: Theme.flameGlow
                            stroke: 2.2
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sendFile.split("/").pop()
                        color: Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                        width: parent.width - 70 * root.s
                    }
                }
            }
        }

        Item { width: 1; height: root.sendFile.length > 0 ? 12 * root.s : 8 * root.s }

        /* ── Scanning — radar pulse ── */
        Item {
            width: parent.width
            height: root.scanning ? 44 * root.s : 0
            visible: height > 0

            Row {
                anchors.centerIn: parent
                spacing: 10 * root.s

                /* Radar rings */
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s; height: 16 * root.s

                    Rectangle {
                        anchors.centerIn: parent
                        width: 16 * root.s; height: 16 * root.s; radius: 8 * root.s
                        color: "transparent"
                        border.width: 1.2
                        border.color: Theme.flameGlow
                        opacity: 0.15 + 0.35 * root.sentPulse

                        SequentialAnimation on scale {
                            running: root.scanning
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.4; to: 1.2; duration: 1400; easing.type: Easing.OutCubic }
                            PropertyAction { property: "scale"; value: 0.4 }
                        }
                        SequentialAnimation on opacity {
                            running: root.scanning
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.5; to: 0.0; duration: 1400; easing.type: Easing.OutCubic }
                            PropertyAction { property: "opacity"; value: 0.5 }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 5 * root.s; height: 5 * root.s; radius: 2.5 * root.s
                        color: Theme.flameGlow
                        opacity: 0.9
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sending ? "Sending…" : "Looking for devices…"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Medium
                }
            }
        }

        /* ── Empty / status state — hero glyph ── */
        Item {
            width: parent.width
            height: (root.status.length > 0 && root.devices.length === 0 && !root.scanning)
                ? Math.max(130 * root.s, statusText.implicitHeight + 80 * root.s) : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: 12 * root.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Flags.showGlyphs && root.installed
                    text: "送"
                    color: Theme.ghost
                    opacity: 0.18
                    font.family: Theme.fontJp
                    font.weight: Font.Bold
                    font.pixelSize: 48 * root.s
                }

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !Flags.showGlyphs && root.installed
                    width: 32 * root.s; height: 32 * root.s
                    name: "share"
                    color: Theme.ghost
                    stroke: 1.6
                    opacity: 0.2
                }

                Text {
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.parent.width - 24 * root.s
                    text: root.status
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

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
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        /* ── Device list — Link-surface-style rows ── */
        ListView {
            id: devList
            width: parent.width
            height: count > 0 ? Math.min(count * 54 * root.s + (count - 1) * 4 * root.s, 280 * root.s) : 0
            visible: height > 0 && !root.scanning
            spacing: 4 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices.length
            interactive: count * 54 * root.s > 280 * root.s

            delegate: Rectangle {
                id: devRow
                required property int index
                width: devList.width
                height: 54 * root.s
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
                    spacing: 12 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.s; height: 18 * root.s
                        name: "smartphone"
                        color: index === root.selectedIndex ? Theme.cream : Theme.iconDim
                        stroke: 2
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * root.s

                        Text {
                            text: devRow.dev.name || devRow.dev.hostname || devRow.dev.alias || "Unknown device"
                            color: index === root.selectedIndex ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 12.5 * root.s
                            font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: devList.width - 140 * root.s
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            visible: (devRow.dev.hostname || devRow.dev.ip || devRow.dev.model || "").length > 0
                            text: devRow.dev.model
                                || (devRow.dev.hostname && devRow.dev.ip ? devRow.dev.hostname + " · " + devRow.dev.ip
                                : (devRow.dev.hostname || devRow.dev.ip || ""))
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: devList.width - 140 * root.s
                        }
                    }
                }

                /* Send action chip — aligned right on selected row */
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.sendFile.length > 0 && index === root.selectedIndex
                    width: sendPillText.implicitWidth + 20 * root.s
                    height: 28 * root.s
                    radius: 14 * root.s
                    color: root.sending ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.94, 0.55, 0.38, 0.14)
                    border.width: 1
                    border.color: root.sending ? Theme.frameBorder : Qt.rgba(0.94, 0.55, 0.38, 0.22)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: sendPillText
                        anchors.centerIn: parent
                        text: root.sending ? "…" : "Send"
                        color: root.sending ? Theme.subtle : Theme.flameGlow
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
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
            height: root.devices.length > 0 ? 8 * root.s : 0
            visible: height > 0
        }
    }
}

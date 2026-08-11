pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls

/**
 * Localsend share surface: lists nearby localsend devices and sends a file.
 * Opens with a target file path set via `sendFile`; shows a device list
 * from `localsend` CLI. Gracefully reports when localsend is not installed.
 * Note: requires localsend CLI to be installed separately.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 16
    mRight: 16
    mBottom: 14

    property string sendFile: ""
    property var devices: []
    property string status: ""
    property bool scanning: false
    property bool sending: false
    property bool found: false
    property int selectedIndex: 0

    function refresh() {
        if (scanProc.running) return;
        scanning = true;
        scanProc.running = true;
    }

    function move(dir) {
        if (devices.length === 0) return;
        selectedIndex = Math.max(0, Math.min(devices.length - 1, selectedIndex + dir));
    }

    function activate() {
        if (devices.length === 0 || selectedIndex < 0 || selectedIndex >= devices.length)
            return;
        sendTo(selectedIndex);
    }

    function sendTo(index) {
        if (sending || index < 0 || index >= devices.length || !sendFile.length)
            return;
        sending = true;
        var dev = devices[index];
        sendProc.command = ["localsend", "send", sendFile, "--to", dev.id || dev.name];
        sendProc.running = true;
    }

    onActiveChanged: {
        if (active) {
            status = "";
            sending = false;
            selectedIndex = 0;
            refresh();
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
                    root.found = true;
                } catch (e) {
                    root.devices = [];
                    root.found = root.status.length === 0;
                }
                if (root.devices.length === 0 && root.found) {
                    root.status = root.sendFile.length
                        ? "No devices found"
                        : "Drop a file to send";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                root.devices = [];
                root.found = false;
                if (this.text.indexOf("not found") !== -1 || this.text.indexOf("command not found") !== -1)
                    root.status = "Localsend not installed";
                else
                    root.status = "No devices found";
            }
        }
    }

    Process {
        id: sendProc
        onExited: {
            root.sending = false;
            if (exitCode === 0) {
                root.status = "Sent ✓";
                root.requestClose();
            } else {
                root.status = "Send failed";
            }
        }
    }

    Item {
        anchors.fill: parent

        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24 * root.s
            spacing: 8 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "送"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "SEND"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.sendFile.length > 0
                width: Math.min(fileLabel.implicitWidth, 120 * root.s)
                height: fileLabel.implicitHeight
                clip: true

                Text {
                    id: fileLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sendFile.split("/").pop()
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideMiddle
                }
            }
        }

        Rectangle {
            anchors.top: header.bottom
            anchors.topMargin: 9 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.hair
        }

        Item {
            anchors.top: header.bottom
            anchors.topMargin: 18 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.status.length > 0

            Text {
                anchors.centerIn: parent
                text: root.status
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        Item {
            anchors.top: header.bottom
            anchors.topMargin: 18 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.status.length === 0

            Flickable {
                id: devFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: devCol.implicitHeight

                Column {
                    id: devCol
                    width: devFlick.width
                    spacing: 4 * root.s

                    Repeater {
                        model: root.devices.length

                        Rectangle {
                            required property int index
                            width: devCol.width
                            height: 34 * root.s
                            radius: 8 * root.s
                            color: index === root.selectedIndex ? Theme.frameBg : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: root.selectedIndex = index
                                onClicked: root.sendTo(index)
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.devices[index].name || root.devices[index].hostname || "Unknown"
                                color: index === root.selectedIndex ? Theme.cream : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Medium
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.devices[index].hostname || ""
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9 * root.s
                            }
                        }
                    }
                }
            }
        }

        Item {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
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
                    from: 0; to: 360; duration: 1000
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
                onClicked: root.refresh()
            }
        }
    }
}

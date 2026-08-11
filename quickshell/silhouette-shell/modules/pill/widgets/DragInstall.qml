pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components.icons

/**
 * AppImage / package drag-install: the drop zone plus the corner-bracket face.
 * Owns the whole install pipeline - the queue, the streamed stdout parse, the
 * per-second elapsed timer and the dropped-font registration - so the pill body
 * stays about surfaces. File drops land only on the resting pill (surfaceOpen
 * false); app-install.sh routes each drop by type (apps install, fonts land in
 * the font dir, images become the wallpaper), anything else flashes a
 * rejection. `dragActive` is the pill's dragOver mode trigger.
 */
Item {
    id: root

    property real s: 1.1

    /** True while the pill is in a surface mode; drops only land on the resting pill. */
    property bool surfaceOpen: false

    /** How settled the pill is into its target geometry; drives the face fade. */
    property real morph: 0

    /**
     * AppImage drag-install state, live only while a file hovers the resting pill.
     * `dragStage` walks hover -> installing -> done, or bad for a non-AppImage drop.
     */
    property bool dragActive: false
    property string dragName: ""
    property string dragStage: ""

    /** A completed app install asked the pill to open the launcher. */
    signal launchRequested()
    /** An image was dropped — share it via the Send surface. */
    signal shareRequested(string filePath)

    property var installQueue: []

    function localPath(url) {
        var s = String(url);
        if (s.indexOf("file://") === 0)
            s = s.substring(7);
        return decodeURIComponent(s);
    }

    readonly property var dropExt: /\.(appimage|deb|rpm|flatpakref|zip|tgz|txz|tbz2|ttf|otf|png|jpe?g|webp)$|\.(pkg\.)?tar\.(gz|xz|bz2|zst)$/i
    readonly property var imageExt: /\.(png|jpe?g|webp)$/i

    function droppablePaths(urls) {
        var out = [];
        for (var i = 0; i < urls.length; i++)
            if (root.dropExt.test(String(urls[i])))
                out.push(root.localPath(urls[i]));
        return out;
    }

    function isImage(url) {
        return root.imageExt.test(String(url));
    }

    function dropLabel(urls) {
        var p = root.localPath(urls.length ? urls[0] : "");
        return p.substring(p.lastIndexOf("/") + 1).replace(root.dropExt, "");
    }

    property bool installedAny: false
    property bool installedApp: false
    property bool installFailed: false
    property string installKind: "app"
    property string installAction: "new"
    property string installLine: ""
    property string installProto: ""
    property string installPct: ""
    property int installSeconds: 0

    function runNextInstall() {
        if (root.installQueue.length === 0) {
            root.dragStage = root.installedAny ? "done" : "fail";
            (root.installedAny ? dropDoneTimer : dropBadTimer).restart();
            return;
        }
        var next = root.installQueue.shift();
        root.dragName = next.substring(next.lastIndexOf("/") + 1).replace(root.dropExt, "");
        root.installLine = "";
        root.installProto = "";
        root.installPct = "";
        installProc.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/app-install.sh", "install", next];
        installProc.running = true;
    }

    /**
     * Streams installer stdout instead of collecting it: slow backends (flatpak
     * runtime pulls, pacman) narrate their steps, and the drop face mirrors the
     * newest line live. The machine-readable result is the one tab-separated
     * kind-prefixed line, fished out of the stream as it passes.
     */
    Process {
        id: installProc
        stdout: SplitParser {
            onRead: (data) => {
                var seg = data.split("\r").pop().replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
                if (seg.length === 0)
                    return;
                if (/^(app|native|font|wallpaper)\t/.test(seg)) {
                    root.installProto = seg;
                } else {
                    root.installLine = seg;
                    var pct = seg.match(/(\d{1,3})\s*%/);
                    if (pct && Number(pct[1]) <= 100)
                        root.installPct = pct[1] + "%";
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && root.installProto.length > 0) {
                root.installedAny = true;
                var parts = root.installProto.split("\t");
                root.installKind = parts[0];
                root.installAction = parts[2];
                if (parts[0] === "app" || parts[0] === "native")
                    root.installedApp = true;
                if (parts[0] === "font" && parts.length >= 4)
                    droppedFont.source = "file://" + parts[3];
            } else {
                root.installFailed = true;
            }
            root.runNextInstall();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.dragStage === "installing"
        onTriggered: root.installSeconds++
    }

    /**
     * Registers a just-dropped font in this running process; the fontconfig
     * cache alone only reaches apps started later. Ready -> the font picker's
     * family list refreshes and the new face shows up without a restart.
     */
    FontLoader {
        id: droppedFont
        onStatusChanged: if (status === FontLoader.Ready) Theme.refreshFonts()
    }

    Timer {
        id: dropDoneTimer
        interval: 1100
        onTriggered: {
            root.dragActive = false;
            root.dragStage = "";
            if (root.installedApp)
                root.launchRequested();
        }
    }

    Timer {
        id: dropBadTimer
        interval: 1300
        onTriggered: {
            root.dragActive = false;
            root.dragStage = "";
        }
    }

    /**
     * File drops land only on the resting pill; an open surface turns the pill
     * into a fullscreen modal that swallows the drag before it can start.
     * app-install.sh routes each drop by type (apps install, fonts land in the
     * font dir, images become the wallpaper), anything else flashes a rejection.
     */
    DropArea {
        anchors.fill: parent
        enabled: !root.surfaceOpen && root.dragStage !== "installing" && root.dragStage !== "done"
        keys: ["text/uri-list"]
        onEntered: (drag) => {
            drag.acceptProposedAction();
            root.dragActive = true;
            root.dragStage = root.droppablePaths(drag.urls).length > 0 ? "hover" : "bad";
            root.dragName = root.dropLabel(drag.urls);
        }
        onExited: {
            if (root.dragStage === "hover" || root.dragStage === "bad") {
                root.dragActive = false;
                root.dragStage = "";
            }
        }
        onDropped: (drop) => {
            drop.acceptProposedAction();
            var files = root.droppablePaths(drop.urls);
            if (files.length === 0) {
                root.dragActive = true;
                root.dragStage = "bad";
                root.dragName = root.dropLabel(drop.urls);
                dropBadTimer.restart();
                return;
            }
            /** Images share directly — no two-step choice. */
            if (files.length === 1 && root.isImage(drop.urls[0])) {
                root.shareRequested(files[0]);
                root.dragActive = false;
                root.dragStage = "";
                return;
            }
            root.dragActive = true;
            root.dragStage = "installing";
            root.installedAny = false;
            root.installedApp = false;
            root.installFailed = false;
            root.installKind = "app";
            root.installAction = "new";
            root.installSeconds = 0;
            root.installQueue = files;
            root.runNextInstall();
        }
    }

    /**
     * Drop-zone face: corner brackets frame a stage glyph and label that walk
     * from "drop to install" through the spinner to a checkmark. Shares the morph
     * fade of the other pill faces, so it grows in as the pill reaches its size.
     */
    Item {
        id: dragOverView
        anchors.fill: parent
        anchors.margins: 11 * root.s
        enabled: root.dragActive
        opacity: root.dragActive ? Math.pow(root.morph, 1.2) : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        readonly property color accent: root.dragStage === "fail" ? "#e0533f"
            : (root.dragStage === "bad" ? "#4ec9b0" : Theme.vermLit)
        readonly property real brLen: 15 * root.s
        readonly property real brThick: 2 * root.s

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Item {
                id: corner
                required property var modelData
                readonly property bool rightSide: modelData[0] === 1
                readonly property bool bottomSide: modelData[1] === 1
                x: rightSide ? dragOverView.width - dragOverView.brLen : 0
                y: bottomSide ? dragOverView.height - dragOverView.brLen : 0
                width: dragOverView.brLen
                height: dragOverView.brLen

                Rectangle {
                    width: dragOverView.brLen
                    height: dragOverView.brThick
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
                Rectangle {
                    width: dragOverView.brThick
                    height: dragOverView.brLen
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 44 * root.s
            spacing: 7 * root.s

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26 * root.s
                height: 26 * root.s

                GlyphIcon {
                    id: dragGlyph
                    anchors.fill: parent
                    stroke: 2
                    color: dragOverView.accent
                    name: root.dragStage === "bad" ? "share"
                        : (root.dragStage === "fail" ? "close"
                        : (root.dragStage === "installing" ? "reboot"
                        : (root.dragStage === "done" ? "check" : "download")))

                    RotationAnimation on rotation {
                        running: root.dragStage === "installing"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                    onNameChanged: if (root.dragStage !== "installing") rotation = 0
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dragStage === "bad" ? "Not installable"
                    : (root.dragStage === "fail" ? "Install failed"
                    : (root.dragStage === "installing" ? ("Installing"
                        + (root.installPct.length > 0 ? " " + root.installPct : "")
                        + (root.installSeconds >= 3 ? "  " + Math.floor(root.installSeconds / 60) + ":" + String(root.installSeconds % 60).padStart(2, "0") : ""))
                    : (root.dragStage === "done" ? (root.installFailed ? "Installed, some failed"
                        : (!root.installedApp && root.installKind === "wallpaper" ? "Wallpaper set"
                        : (!root.installedApp && root.installKind === "font" ? "Font installed"
                        : (root.installAction === "updated" ? "Updated"
                        : (root.installAction === "reinstalled" ? "Reinstalled" : "Installed")))))
                    : "Drop to install")))
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.dragStage === "bad" ? "Use Send surface to share"
                    : (root.dragStage === "installing" && root.installLine.length > 0 ? root.installLine : root.dragName)
                color: root.dragStage === "bad" ? dragOverView.accent : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }
}

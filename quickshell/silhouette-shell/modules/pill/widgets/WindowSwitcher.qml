pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls

/**
 * Window switcher surface: fuzzy-filtered list of open Hyprland toplevel
 * windows with app icons and workspace badges. Type to filter by title or
 * class; Enter focuses the selected window and closes. Escape dismisses.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 11
    mRight: 11
    mBottom: 14

    readonly property var allWindows: {
        var tl = Hyprland.toplevels.values;
        var out = [];
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (!t || !t.address || !t.title)
                continue;
            var ipc = t.lastIpcObject;
            out.push({
                address: t.address,
                title: t.title || "",
                cls: (ipc && ipc.class) ? ipc.class : "",
                workspace: (ipc && ipc.workspace) ? ipc.workspace.name : ""
            });
        }
        return out;
    }

    readonly property var results: {
        var q = header.query.toLowerCase().trim();
        if (q.length === 0)
            return root.allWindows;
        var out = [];
        for (var i = 0; i < root.allWindows.length; i++) {
            var w = root.allWindows[i];
            if (w.title.toLowerCase().indexOf(q) !== -1 || w.cls.toLowerCase().indexOf(q) !== -1)
                out.push(w);
        }
        return out;
    }

    /** Resolve a desktop-entry icon for a window class. */
    function iconFor(cls) {
        if (!cls || !cls.length)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a || !a.id)
                continue;
            var id = a.id.toLowerCase();
            if (id === cls.toLowerCase() + ".desktop" || id.indexOf(cls.toLowerCase() + ".desktop") === 0)
                return a.icon ? Quickshell.iconPath(a.icon, true) : "";
        }
        return "";
    }

    function focusField() { header.focusField(); }
    function move(delta) { header.move(delta); }

    function activate() {
        var idx = header.selectedIndex;
        if (root.results.length === 0 || idx < 0 || idx >= root.results.length)
            return;
        var addr = root.results[idx].address;
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })');
        root.requestClose();
    }

    ameForm: "caret"
    amePoint: header.caretPos

    SearchHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: "窓"
        placeholder: "Switch windows"
        counterText: root.results.length + " windows"
        results: root.results
        surfaceActive: root.active

        onActivate: root.activate()
        onDismiss: root.requestClose()
    }

    Text {
        anchors.centerIn: list
        visible: root.results.length === 0
        text: root.results.length === 0 && header.query.length ? "No windows match" : "No windows open"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results.length

        delegate: Item {
            id: winRow
            required property int index
            width: list.width
            height: 38 * root.s

            readonly property var win: root.results[index]
            readonly property bool selected: index === header.selectedIndex
            readonly property string resolvedIcon: root.iconFor(winRow.win.cls)

            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                visible: winRow.selected || rowArea.containsMouse
                color: winRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
                border.width: winRow.selected ? 1 : 0
                border.color: Theme.frameBorder
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: header.selectedIndex = winRow.index
                onClicked: {
                    header.selectedIndex = winRow.index;
                    root.activate();
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 11 * root.s
                anchors.rightMargin: 11 * root.s

                Rectangle {
                    id: iconBg
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: 5 * root.s
                    color: Qt.rgba(1, 1, 1, 0.05)
                    visible: !(appIcon.status === Image.Ready && appIcon.source != "")
                }
                Image {
                    id: appIcon
                    anchors.fill: iconBg
                    sourceSize.width: Math.round(40 * root.s)
                    sourceSize.height: Math.round(40 * root.s)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready && source != ""
                    source: winRow.resolvedIcon
                }
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: iconBg.horizontalCenter
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "window"
                    color: winRow.selected ? Theme.dim : Theme.faint
                    stroke: 1.7
                    visible: winRow.resolvedIcon.length === 0 || (appIcon.status !== Image.Ready)
                }

                Column {
                    anchors.left: iconBg.right
                    anchors.leftMargin: 10 * root.s
                    anchors.right: wsBadge.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * root.s

                    Text {
                        width: parent.width
                        text: winRow.win.title
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: winRow.selected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: winRow.win.cls.length > 0
                        text: winRow.win.cls
                        color: winRow.selected ? Theme.dim : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: wsBadge
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: ret.left
                    anchors.rightMargin: winRow.selected ? 6 * root.s : 0
                    width: visible ? wsLabel.implicitWidth + 10 * root.s : 0
                    height: 18 * root.s
                    radius: 4 * root.s
                    color: winRow.selected ? Qt.rgba(0.94, 0.88, 0.84, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    visible: winRow.win.workspace.length > 0 && winRow.win.workspace !== "special:minimized"

                    Text {
                        id: wsLabel
                        anchors.centerIn: parent
                        text: winRow.win.workspace
                        color: winRow.selected ? Theme.dim : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                Text {
                    id: ret
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "↵"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    visible: winRow.selected
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: list
        s: root.s
        flick: list
    }
}

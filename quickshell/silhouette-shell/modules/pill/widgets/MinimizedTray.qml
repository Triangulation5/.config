pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components.controls
import qs.components.icons

/**
 * Row of icon buttons for windows parked on Hyprland's `special:minimized`
 * workspace (Super+M). Clicking one moves it back to the focused workspace.
 */
Row {
    id: root

    property real s: 1.1
    property string screenName: ""
    spacing: 8 * s

    /**
     * Resolve the workspace id to restore into: the active workspace of the
     * monitor this pill lives on, so a window reappears on the screen the user
     * clicked, falling back to the focused workspace.
     */
    function restoreWorkspace() {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++)
            if (ms[i].name === root.screenName && ms[i].activeWorkspace)
                return ms[i].activeWorkspace.id;
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
    }

    readonly property var items: {
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (t && t.workspace && t.workspace.name === "special:minimized")
                out.push(t);
        }
        return out;
    }
    readonly property int count: items.length

    /**
     * Keyboard per-icon focus, driven by the hover face while its ring sits on
     * this row (faceActive). Left/right walks the chips, Return restores.
     */
    property int focusIndex: -1
    property bool faceActive: false

    function restore(t) {
        if (!t)
            return;
        var addr = t.address;
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr;
        Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + root.restoreWorkspace() + ', window = "address:' + addr + '" })');
    }

    function moveFocus(dir) {
        if (root.count === 0)
            return false;
        if (focusIndex < 0 || focusIndex >= root.count)
            focusIndex = 0;
        focusIndex = (focusIndex + dir + root.count) % root.count;
        return true;
    }

    /** Return on the focused chip: move that window back to the active workspace. */
    function activate() {
        if (focusIndex < 0 || focusIndex >= root.count)
            return false;
        root.restore(root.items[focusIndex]);
        return true;
    }

    /**
     * Resolve an icon path for a toplevel by matching its window class to a
     * desktop entry id (the class often differs from the icon-theme name), with
     * a direct icon-theme lookup as fallback.
     */
    function iconFor(t) {
        var cls = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class
            : (t && t.wayland && t.wayland.appId ? t.wayland.appId : "");
        if (!cls)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (e && e.id && e.id.toLowerCase() === cls.toLowerCase() && e.icon)
                return Quickshell.iconPath(e.icon, "application-x-executable");
        }
        return Quickshell.iconPath(cls, "application-x-executable");
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: chip
            required property var modelData
            required property int index
            width: 18 * root.s
            height: 18 * root.s

            readonly property string iconSrc: root.iconFor(chip.modelData)

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3 * root.s
                radius: 6 * root.s
                visible: root.faceActive && root.focusIndex === index
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(Theme.vermLit, 0.65)
            }

            Image {
                anchors.fill: parent
                sourceSize.width: Math.round(36 * root.s)
                sourceSize.height: Math.round(36 * root.s)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: chip.iconSrc
                opacity: (area.containsMouse || (root.faceActive && root.focusIndex === index)) ? 1 : 0.78
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.focusIndex = index
                onClicked: root.restore(chip.modelData)
            }

            Tooltip {
                s: root.s
                placement: "below"
                title: chip.modelData.title
                show: area.containsMouse
            }
        }
    }
}

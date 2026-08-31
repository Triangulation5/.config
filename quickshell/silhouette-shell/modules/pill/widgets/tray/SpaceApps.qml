pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.launcher
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import qs.components.layout

/**
 * App manager for a user-defined special workspace (the one named by
 * Spaces.editing). The same two-view shape as Stash: the list view shows each
 * routed window class as an app tile with friendly name and faint raw-class
 * subtitle and a ✕ to drop it, capped by a dashed "add app" bar; the add view
 * swaps in the launcher's fuzzy picker whose pick derives a window class from the
 * entry's StartupWMClass. Reads and writes through the Spaces singleton, which
 * owns spaces.lua and fires the debounced reload — this surface holds no file.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    implicitHeight: content.implicitHeight

    signal requestSurface(string name)

    ameForm: "off"

    readonly property var editingSpace: {
        var sl = Spaces.list;
        for (var i = 0; i < sl.length; i++)
            if (sl[i] && sl[i].id === Spaces.editing)
                return sl[i];
        return null;
    }
    readonly property var entries: editingSpace ? editingSpace.apps : []
    readonly property string spaceName: editingSpace && editingSpace.name ? editingSpace.name : "SPACE"

    /** Pill.qml folds the picker back when the surface leaves */
    readonly property alias addOpen: picker.addOpen
    function closeAdd() { picker.closeAdd(); }

    function removeAt(i) {
        if (i < 0 || i >= root.entries.length)
            return;
        Spaces.removeApp(Spaces.editing, root.entries[i]);
    }

    /**
     * Keyboard focus over the list view: the routed-app rows then the dashed
     * add bar. The add view owns its own focus through the picker's search
     * field, so these are no-ops while addOpen.
     */
    property int focusIndex: -1
    readonly property int focusCount: root.entries.length + (picker.addOpen ? 0 : 1)

    function move(dir) {
        if (picker.addOpen || focusCount <= 1)
            return;
        if (focusIndex < 0 || focusIndex >= focusCount)
            focusIndex = 0;
        focusIndex = (focusIndex + dir + focusCount) % focusCount;
        if (root.entries.length > 0)
            list.positionViewAtIndex(Math.min(focusIndex, root.entries.length - 1), ListView.Contain);
    }

    /**
     * Enter on the focused row removes that app (its only action); on the add
     * bar it opens the picker.
     */
    function activate() {
        if (picker.addOpen)
            return;
        if (focusIndex < 0)
            focusIndex = root.entries.length;
        if (focusIndex === root.entries.length)
            picker.openAdd();
        else if (focusIndex >= 0 && focusIndex < root.entries.length)
            root.removeAt(focusIndex);
    }

    function addClass(cls) {
        if (cls && cls.length > 0)
            Spaces.addApp(Spaces.editing, cls);
        picker.closeAdd();
    }

    onActiveChanged: {
        if (!active)
            focusIndex = -1;
        picker.closeAdd();
    }

    Connections {
        target: picker
        function onAddOpenChanged() {
            if (!picker.addOpen)
                root.focusIndex = -1;
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SurfaceHeader {
            s: root.s
            kanji: "場"
            label: root.spaceName
            showBack: true
        }

        Item { width: 1; height: 9 * root.s }


        Item {
            width: parent.width
            height: visible ? 26 * root.s : 0
            visible: !picker.addOpen && root.entries.length === 0

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: "No apps routed here yet"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }
        }

        ListView {
            id: list
            width: parent.width
            height: visible ? Math.min(contentHeight, 230 * root.s) : 0
            visible: !picker.addOpen && root.entries.length > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries

            delegate: Item {
                id: erow
                required property int index
                required property string modelData

                readonly property var resolved: {
                    void picker.allApps;
                    return picker.resolveEntry(modelData);
                }
                readonly property string title: resolved && resolved.name ? resolved.name : modelData
                readonly property bool named: resolved && resolved.name && resolved.name !== modelData
                readonly property bool focused: root.focusIndex === index

                width: ListView.view.width
                height: 46 * root.s

                HoverTile {
                    anchors.fill: parent
                    anchors.topMargin: 3 * root.s
                    anchors.bottomMargin: 3 * root.s
                    radius: 10 * root.s
                    hovered: rowHover.hovered
                    focused: erow.focused
                    edge: Theme.frameBorder
                }

                HoverHandler { id: rowHover }

                Rectangle {
                    id: tile
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28 * root.s
                    height: 28 * root.s
                    radius: 7 * root.s
                    color: Theme.tileBg
                    border.width: 1
                    border.color: Theme.hairSoft

                    Text {
                        anchors.centerIn: parent
                        visible: !(icon.status === Image.Ready && icon.source != "")
                        text: erow.title.length > 0 ? erow.title.charAt(0).toUpperCase() : "?"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                    }

                    Image {
                        id: icon
                        anchors.fill: parent
                        anchors.margins: 4 * root.s
                        sourceSize.width: Math.round(40 * root.s)
                        sourceSize.height: Math.round(40 * root.s)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready && source != ""
                        source: erow.resolved && erow.resolved.icon ? Quickshell.iconPath(erow.resolved.icon, true) : ""
                    }
                }

                Column {
                    anchors.left: tile.right
                    anchors.leftMargin: 12 * root.s
                    anchors.right: removeBtn.left
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s

                    Text {
                        width: parent.width
                        text: erow.title
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: erow.named
                        text: erow.modelData
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: removeBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: 7 * root.s
                    color: removeArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "close"
                        color: removeArea.containsMouse ? Theme.vermLit : Theme.iconDim
                        stroke: 2
                    }

                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeAt(erow.index)
                    }
                }
            }
        }

        Item { width: 1; height: visible ? 6 * root.s : 0; visible: !picker.addOpen }

        AppPickerList {
            id: picker
            width: parent.width
            s: root.s
            barFocused: !picker.addOpen && root.focusIndex === root.entries.length
            onPicked: (entry) => root.addClass(entry.startupClass || entry.id)
        }

        Item { width: 1; height: 4 * root.s }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.components.icons

/**
 * One application row: the app icon, its name, and a secondary line (generic
 * name or category). AppImage entries support rename and a two-tap delete via
 * right-click editing. Extracted from Launcher.qml's app list delegate.
 */
Item {
    id: appRow

    property var surface: null
    required property int index
    required property var modelData

    readonly property real s: surface ? surface.s : 1
    readonly property var entry: modelData
    readonly property bool selected: surface ? surface.selectedIndex === appRow.index : false
    readonly property bool isAppImage: entry && entry.id && entry.id.indexOf("ricelin-") === 0
    readonly property bool editing: surface && isAppImage ? surface.editIndex === appRow.index : false
    property bool armed: false
    onEditingChanged: if (!editing) armed = false

    readonly property string secondary: {
        if (!entry) return "";
        if (entry.genericName && entry.genericName.length > 0) return entry.genericName;
        if (entry.categories && entry.categories.length > 0 && surface) return surface.mapCategory(entry.categories);
        return "";
    }

    width: parent ? parent.width : 0
    height: 38 * s

    Rectangle {
        anchors.fill: parent
        radius: 9 * s
        visible: appRow.selected || rowArea.containsMouse
        color: appRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
        border.width: appRow.selected ? 1 : 0
        border.color: Theme.frameBorder
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(m) {
            if (!surface) return;
            var g = rowArea.mapToItem(null, m.x, m.y);
            if (g.x !== surface.lastPointer.x || g.y !== surface.lastPointer.y) {
                surface.lastPointer = Qt.point(g.x, g.y);
                surface.selectedIndex = appRow.index;
            }
        }
        onClicked: function(m) {
            if (!surface) return;
            if (m.button === Qt.RightButton) {
                if (appRow.isAppImage)
                    surface.editIndex = appRow.editing ? -1 : appRow.index;
                return;
            }
            if (appRow.editing) return;
            surface.selectedIndex = appRow.index;
            surface.activate();
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11 * s
        anchors.rightMargin: 11 * s

        Rectangle {
            id: iconBg
            anchors.verticalCenter: parent.verticalCenter
            width: 22 * s
            height: 22 * s
            radius: 5 * s
            color: Qt.rgba(1, 1, 1, 0.05)
            visible: !(icon.status === Image.Ready && icon.source != "")
        }
        Image {
            id: icon
            anchors.fill: iconBg
            sourceSize.width: Math.round(40 * s)
            sourceSize.height: Math.round(40 * s)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            visible: status === Image.Ready && source != ""
            source: {
                if (!appRow.entry || !appRow.entry.icon) return "";
                var ic = appRow.entry.icon;
                if (appRow.isAppImage && ic.indexOf("/") === 0) return "file://" + ic;
                return Quickshell.iconPath(ic, true);
            }
        }

        TextMetrics {
            id: retMetrics
            font.family: Theme.font
            font.pixelSize: 12 * s
            text: "↵"
        }
        Text {
            id: ret
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: retMetrics.text
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 12 * s
            visible: appRow.selected && !appRow.editing
            width: visible ? retMetrics.advanceWidth + 6 * s : 0
            horizontalAlignment: Text.AlignRight
        }

        GlyphIcon {
            id: trashGlyph
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            width: appRow.editing ? 16 * s : 0
            height: 16 * s
            visible: appRow.editing
            stroke: 2
            name: "trash"
            color: appRow.armed ? "#e0533f" : Theme.dim

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6 * s
                enabled: appRow.editing
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!appRow.armed) {
                        appRow.armed = true;
                        return;
                    }
                    if (surface) {
                        var slug = surface.appimageSlug(appRow.entry);
                        if (slug) {
                            surface.appimageProc.command = ["bash", surface.appimageScript, "remove", slug];
                            surface.appimageProc.running = true;
                        }
                        surface.editIndex = -1;
                    }
                }
            }
        }

        /** Name over description, centred on the icon row. */
        Column {
            anchors.left: iconBg.right
            anchors.leftMargin: 10 * s
            anchors.right: appRow.editing ? trashGlyph.left : ret.left
            anchors.rightMargin: 8 * s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * s

            Item {
                width: parent.width
                height: nameText.implicitHeight

                Text {
                    id: nameText
                    anchors.fill: parent
                    visible: !appRow.editing
                    text: appRow.entry ? appRow.entry.name : ""
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * s
                    font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                TextInput {
                    id: nameEdit
                    anchors.fill: parent
                    visible: appRow.editing
                    text: appRow.entry ? appRow.entry.name : ""
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13 * s
                    selectByMouse: true
                    clip: true
                    onVisibleChanged: if (visible) {
                        selectAll();
                        forceActiveFocus();
                    }
                    onEditingFinished: {
                        if (!surface) return;
                        var slug = surface.appimageSlug(appRow.entry);
                        var nm = nameEdit.text.trim();
                        if (slug && nm.length > 0 && nm !== appRow.entry.name) {
                            surface.appimageProc.command = ["bash", surface.appimageScript, "rename", slug, nm];
                            surface.appimageProc.running = true;
                        }
                        surface.editIndex = -1;
                    }
                }
            }
            Text {
                id: sec
                width: parent.width
                visible: appRow.secondary.length > 0
                text: appRow.secondary
                color: appRow.selected ? Theme.dim : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * s
                elide: Text.ElideRight
            }
        }
    }
}

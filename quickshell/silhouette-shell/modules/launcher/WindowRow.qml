pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * One window-switcher row: the app icon (or a generic window glyph), window
 * title, class name, and a workspace pill. Clicking activates the window.
 * Extracted from Launcher.qml's window list delegate.
 */
Item {
    id: winRow

    property var surface: null
    required property int index

    readonly property real s: surface ? surface.s : 1
    readonly property var win: surface && winRow.index < surface.windowResults.length ? surface.windowResults[winRow.index] : null
    readonly property bool selected: surface ? surface.selectedIndex === winRow.index : false
    readonly property string resolvedIcon: surface ? surface.iconForWindow(winRow.win.cls) : ""

    width: parent ? parent.width : 0
    height: 38 * s

    Rectangle {
        anchors.fill: parent
        radius: 9 * s
        visible: winRow.selected || winArea.containsMouse
        color: winRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
        border.width: winRow.selected ? 1 : 0
        border.color: Theme.frameBorder
    }

    MouseArea {
        id: winArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (surface) surface.selectedIndex = winRow.index
        onClicked: {
            if (surface) {
                surface.selectedIndex = winRow.index;
                surface.focusWindow();
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11 * s
        anchors.rightMargin: 11 * s

        Rectangle {
            id: winIconBg
            anchors.verticalCenter: parent.verticalCenter
            width: 22 * s
            height: 22 * s
            radius: 5 * s
            color: Qt.rgba(1, 1, 1, 0.05)
            visible: !(winIcon.status === Image.Ready && winIcon.source != "")
        }
        Image {
            id: winIcon
            anchors.fill: winIconBg
            sourceSize.width: Math.round(40 * s)
            sourceSize.height: Math.round(40 * s)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            visible: status === Image.Ready && source != ""
            source: winRow.resolvedIcon
        }
        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: winIconBg.horizontalCenter
            width: 14 * s
            height: 14 * s
            name: "window"
            color: winRow.selected ? Theme.dim : Theme.faint
            stroke: 1.7
            visible: winRow.resolvedIcon.length === 0 || (winIcon.status !== Image.Ready)
        }

        Column {
            anchors.left: winIconBg.right
            anchors.leftMargin: 10 * s
            anchors.right: wsPill.left
            anchors.rightMargin: 8 * s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * s

            Text {
                width: parent.width
                text: winRow.win.title
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * s
                font.weight: winRow.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: winRow.win.cls.length > 0
                text: winRow.win.cls
                color: winRow.selected ? Theme.dim : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * s
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: wsPill
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: winRet.left
            anchors.rightMargin: winRow.selected ? 6 * s : 0
            width: visible ? wsLabel.implicitWidth + 10 * s : 0
            height: 18 * s
            radius: 4 * s
            color: winRow.selected ? Qt.rgba(0.94, 0.88, 0.84, 0.08) : Qt.rgba(1, 1, 1, 0.04)
            visible: winRow.win.workspace.length > 0 && winRow.win.workspace !== "special:minimized"

            Text {
                id: wsLabel
                anchors.centerIn: parent
                text: winRow.win.workspace
                color: winRow.selected ? Theme.dim : Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * s
                font.weight: Font.Medium
            }
        }

        Text {
            id: winRet
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: "↵"
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 12 * s
            visible: winRow.selected
        }
    }
}

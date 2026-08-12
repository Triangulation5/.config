pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The Recorder's save-location row: a tracked "SAVE TO" label, the output
 * directory collapsed to `~` and elided to fit, and Change / Open affordances
 * that drive the native picker and file manager. Extracted from Recorder.qml.
 */
Item {
    id: row

    property real s: 1

    width: parent.width
    height: 18 * s

    readonly property string shownDir: {
        var d = ScreenRec.outDir;
        var h = ScreenRec.home;
        return h.length > 0 && d.indexOf(h) === 0 ? "~" + d.slice(h.length) : d;
    }

    Text {
        id: pathLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "SAVE TO"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 9 * s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * s
    }

    Item {
        id: pathActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        width: changeTxt.width + 9 * s + openTxt.width

        Text {
            id: changeTxt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "CHANGE"
            color: changeArea.containsMouse ? Theme.flameGlow : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * s

            MouseArea {
                id: changeArea
                anchors.fill: parent
                anchors.margins: -5 * s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.pickDir()
            }
        }
        Text {
            id: openTxt
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "OPEN"
            color: openArea.containsMouse ? Theme.flameGlow : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * s

            MouseArea {
                id: openArea
                anchors.fill: parent
                anchors.margins: -5 * s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.openDir()
            }
        }
    }

    Text {
        id: pathText
        anchors.left: pathLabel.right
        anchors.leftMargin: 10 * s
        anchors.right: pathActions.left
        anchors.rightMargin: 12 * s
        anchors.verticalCenter: parent.verticalCenter
        text: row.shownDir
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 10 * s
        font.weight: Font.DemiBold
        elide: Text.ElideMiddle
        maximumLineCount: 1
    }
}

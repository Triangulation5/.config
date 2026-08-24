pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls

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

        TextHoverLabel {
            id: changeTxt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            s: row.s
            text: "CHANGE"
            hoverColor: Theme.flameGlow
            idleColor: Theme.subtle
            hitMargins: -5 * row.s
            font.family: Theme.font
            font.pixelSize: 9 * row.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * row.s
            onClicked: ScreenRec.pickDir()
        }
        TextHoverLabel {
            id: openTxt
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            s: row.s
            text: "OPEN"
            hoverColor: Theme.flameGlow
            idleColor: Theme.subtle
            hitMargins: -5 * row.s
            font.family: Theme.font
            font.pixelSize: 9 * row.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * row.s
            onClicked: ScreenRec.openDir()
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services

/**
 * The keybinds search row: a kanji glyph, a borderless field that filters the
 * bind list, and the focus underline. Up/Down/Return/Backspace route into the
 * host's move/activate/requestSurface handlers.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    width: parent ? parent.width : 0
    height: 28 * root.s
    visible: !root.host.formOpen

    Text {
        id: searchGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: Flags.showGlyphs
        width: Flags.showGlyphs ? implicitWidth : 0
        text: "探"
        color: Theme.dim
        font.family: Theme.fontJp
        font.weight: Font.Medium
        font.pixelSize: 15 * root.s
    }

    TextField {
        id: searchField
        anchors.left: searchGlyph.right
        anchors.leftMargin: Flags.showGlyphs ? 9 * root.s : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        background: null
        padding: 0
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 13 * root.s
        placeholderText: "search binds"
        placeholderTextColor: Theme.faint
        selectByMouse: true
        selectionColor: Theme.verm
        onTextChanged: {
            root.host.query = text;
            root.host.focusIndex = 0;
        }
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Down) {
                root.host.move(1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up) {
                root.host.move(-1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.host.activate();
                e.accepted = true;
            } else if (e.key === Qt.Key_Backspace && text.length === 0 && selectedText.length === 0) {
                root.host.requestSurface("settings");
                e.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.left: searchField.left
        anchors.right: searchField.right
        anchors.top: searchField.bottom
        anchors.topMargin: 3 * root.s
        height: 1
        color: Theme.faint
        opacity: searchField.activeFocus ? 0.7 : 0.18
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }
}

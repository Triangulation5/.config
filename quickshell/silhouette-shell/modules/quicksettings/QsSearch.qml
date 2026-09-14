pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons
import qs.modules.quicksettings

/**
 * The standalone settings panel's search bar: 探 glyph (per the shell's glyph
 * flag), a borderless field filtering the registry, a focus underline, and a
 * clear button once text is entered. Arrow/Return/Backspace route into the
 * host so keyboard users never need the mouse; the host's focusSearch()
 * lands here for a forward-slash keypress.
 */
Item {
    id: root

    required property var host
    property real s: host ? host.s : 1.1

    width: parent ? parent.width : 0
    height: 28 * root.s

    function focusField() {
        searchField.forceActiveFocus();
    }

    /** Empty the query (used by the host's reset on open). */
    function clear() {
        searchField.text = "";
    }

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

    GlyphIcon {
        id: searchIcon
        anchors.left: searchGlyph.visible ? searchGlyph.right : parent.left
        anchors.leftMargin: searchGlyph.visible ? 9 * root.s : 0
        anchors.verticalCenter: parent.verticalCenter
        width: 15 * root.s
        height: 15 * root.s
        name: "search"
        color: searchField.activeFocus ? Theme.cream : Theme.dim
        stroke: 1.8
    }

    TextField {
        id: searchField
        anchors.left: searchIcon.right
        anchors.leftMargin: 9 * root.s
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.rightMargin: clearBtn.visible ? 6 * root.s : 0
        anchors.verticalCenter: parent.verticalCenter
        background: null
        padding: 0
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 13 * root.s
        placeholderText: "search every setting"
        placeholderTextColor: Theme.faint
        selectByMouse: true
        selectionColor: Theme.verm

        onTextChanged: {
            root.host.query = text;
            root.host.kbIndex = 0;
        }

        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Down) {
                root.host.kbMove(1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up) {
                root.host.kbMove(-1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.host.kbActivate();
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape) {
                if (text.length > 0) {
                    text = "";
                    e.accepted = true;
                } else if (root.host.requestClose !== undefined) {
                    root.host.requestClose();
                    e.accepted = true;
                }
            }
        }
    }

    Item {
        id: clearBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 18 * root.s
        height: 18 * root.s
        visible: searchField.text.length > 0

        GlyphIcon {
            anchors.centerIn: parent
            width: 12 * root.s
            height: 12 * root.s
            name: "close-circle"
            color: clearArea.containsMouse ? Theme.cream : Theme.dim
            stroke: 1.9
        }

        MouseArea {
            id: clearArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: searchField.text = ""
        }
    }

    Rectangle {
        anchors.left: searchField.left
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.top: searchField.bottom
        anchors.topMargin: 3 * root.s
        height: 1
        color: Theme.faint
        opacity: searchField.activeFocus ? 0.7 : 0.18
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * The "New Workspace" create form: back chevron + title, name/description
 * fields, a tap-to-capture keybind row, conflict line and Cancel/Create
 * buttons. All state lives on the host surface; this view only edits it.
 */
Column {
    id: root

    property real s: 1.1
    property var host: null

    width: parent ? parent.width : 0
    visible: root.host.formOpen
    spacing: 10 * root.s

    Item {
        width: parent.width
        height: 22 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 * root.s

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s

                HoverIcon {
                    anchors.fill: parent
                    name: "chevron-left"
                    color: Theme.iconDim
                    hoverColor: Theme.cream
                    stroke: 1.8
                    hitPad: 6 * root.s
                    onClicked: root.host.closeForm()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "NEW WORKSPACE"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.4 * root.s
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * root.s

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: "NAME"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * root.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * root.s
            radius: 8 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: nameField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

            TextField {
                id: nameField
                anchors.left: parent.left
                anchors.leftMargin: 11 * root.s
                anchors.right: parent.right
                anchors.rightMargin: 11 * root.s
                anchors.verticalCenter: parent.verticalCenter
                background: null
                padding: 0
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                placeholderText: "Discord"
                placeholderTextColor: Theme.faint
                selectByMouse: true
                selectionColor: Theme.verm
                text: root.host.formName
                onTextEdited: root.host.formName = text
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.host.closeForm(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.host.create(); e.accepted = true; }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * root.s

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: "DESCRIPTION"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * root.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * root.s
            radius: 8 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: descField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

            TextField {
                id: descField
                anchors.left: parent.left
                anchors.leftMargin: 11 * root.s
                anchors.right: parent.right
                anchors.rightMargin: 11 * root.s
                anchors.verticalCenter: parent.verticalCenter
                background: null
                padding: 0
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                placeholderText: "Chat (optional)"
                placeholderTextColor: Theme.faint
                selectByMouse: true
                selectionColor: Theme.verm
                text: root.host.formDesc
                onTextEdited: root.host.formDesc = text
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.host.closeForm(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.host.create(); e.accepted = true; }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * root.s

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: "KEYBIND"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * root.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * root.s
            radius: 8 * root.s
            color: root.host.listening ? Qt.alpha(Theme.vermLit, 0.12) : Theme.frameBg
            border.width: 1
            border.color: root.host.listening ? Qt.alpha(Theme.vermLit, 0.55) : Theme.hairSoft
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 11 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: root.host.listening ? "press a letter…  esc cancels"
                    : (root.host.formKey.length ? "Super + " + root.host.formKey : "tap to set a key")
                color: root.host.listening ? Theme.flameGlow
                    : (root.host.formKey.length ? Theme.cream : Theme.faint)
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                font.weight: root.host.formKey.length ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.host.conflict = "";
                    root.host.listening = true;
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.host.conflict.length > 0
        text: root.host.conflict
        color: Theme.vermLit
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Item {
        width: parent.width
        height: 30 * root.s

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: cancelLabel.implicitWidth + 24 * root.s
            height: 28 * root.s
            radius: 8 * root.s
            color: cancelArea.containsMouse ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: Theme.hairSoft

            Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.3 * root.s
            }

            MouseArea {
                id: cancelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.host.closeForm()
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: createLabel.implicitWidth + 30 * root.s
            height: 28 * root.s
            radius: 8 * root.s
            color: createArea.containsMouse ? Theme.vermLit : Theme.verm

            Text {
                id: createLabel
                anchors.centerIn: parent
                text: "Create"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 0.4 * root.s
            }

            MouseArea {
                id: createArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.host.create()
            }
        }
    }
}

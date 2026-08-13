import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons

/**
 * Add/edit form for the keybinds surface: the captured-combo readout, name
 * and command/dispatch fields, the conflict note, and the delete/save row.
 * The host (Keybinds.qml) owns the form state machine (formOpen/formAdd/
 * listening, the chord capture) and the Binds file edits; this panel only
 * reads and adjusts those properties.
 */
Column {
    id: form

    /** The keybinds surface this form belongs to: its form state and scale. */
    property var surface: null

    /** Focus the name field; the host calls this when the form opens. */
    function focusName() { nameField.forceActiveFocus(); }

    spacing: 10 * surface.s

    Item {
        width: parent.width
        height: 22 * surface.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 * surface.s

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * surface.s
                height: 16 * surface.s

                GlyphIcon {
                    anchors.fill: parent
                    name: "chevron-left"
                    color: formBackArea.containsMouse ? Theme.cream : Theme.iconDim
                    stroke: 1.8
                }

                MouseArea {
                    id: formBackArea
                    anchors.fill: parent
                    anchors.margins: -6 * surface.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: surface.closeForm()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: surface.formAdd ? "NEW BIND" : "EDIT BIND"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * surface.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.4 * surface.s
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * surface.s

        Text {
            id: keyLabel
            anchors.left: parent.left
            anchors.top: parent.top
            text: "KEY"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * surface.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * surface.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * surface.s
            radius: 8 * surface.s
            color: surface.listening ? Qt.alpha(Theme.vermLit, 0.12) : Theme.frameBg
            border.width: 1
            border.color: surface.listening ? Qt.alpha(Theme.vermLit, 0.55) : Theme.hairSoft
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 11 * surface.s
                anchors.verticalCenter: parent.verticalCenter
                text: surface.listening ? "press keys… esc cancels"
                    : (surface.formCombo.length ? surface.formCombo : "tap to set a key")
                color: surface.listening ? Theme.flameGlow
                    : (surface.formCombo.length ? Theme.cream : Theme.faint)
                font.family: Theme.font
                font.pixelSize: 11.5 * surface.s
                font.weight: surface.formCombo.length ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    surface.conflict = "";
                    surface.listening = true;
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * surface.s

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: "NAME"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * surface.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * surface.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * surface.s
            radius: 8 * surface.s
            color: Theme.frameBg
            border.width: 1
            border.color: nameField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

            TextField {
                id: nameField
                anchors.left: parent.left
                anchors.leftMargin: 11 * surface.s
                anchors.right: parent.right
                anchors.rightMargin: 11 * surface.s
                anchors.verticalCenter: parent.verticalCenter
                background: null
                padding: 0
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * surface.s
                placeholderText: "label (optional)"
                placeholderTextColor: Theme.faint
                selectByMouse: true
                selectionColor: Theme.verm
                text: surface.formName
                onTextEdited: surface.formName = text
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { surface.closeForm(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { surface.save(); e.accepted = true; }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 40 * surface.s

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: surface.formCmdEditable ? "COMMAND" : "ACTION"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * surface.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * surface.s
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26 * surface.s
            radius: 8 * surface.s
            color: Theme.frameBg
            border.width: 1
            border.color: (cmdField.activeFocus || actionField.activeFocus) ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft

            TextField {
                id: cmdField
                visible: surface.formCmdEditable
                anchors.left: parent.left
                anchors.leftMargin: 11 * surface.s
                anchors.right: parent.right
                anchors.rightMargin: 11 * surface.s
                anchors.verticalCenter: parent.verticalCenter
                background: null
                padding: 0
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * surface.s
                placeholderText: "shell command"
                placeholderTextColor: Theme.faint
                selectByMouse: true
                selectionColor: Theme.verm
                text: surface.formCmd
                onTextEdited: surface.formCmd = text
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { surface.closeForm(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { surface.save(); e.accepted = true; }
                }
            }

            TextField {
                id: actionField
                visible: !surface.formCmdEditable
                anchors.left: parent.left
                anchors.leftMargin: 11 * surface.s
                anchors.right: parent.right
                anchors.rightMargin: 11 * surface.s
                anchors.verticalCenter: parent.verticalCenter
                background: null
                padding: 0
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * surface.s
                placeholderText: "lua dispatch"
                placeholderTextColor: Theme.faint
                selectByMouse: true
                selectionColor: Theme.verm
                text: surface.formAction
                onTextEdited: surface.formAction = text
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { surface.closeForm(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { surface.save(); e.accepted = true; }
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: surface.conflict.length > 0
        text: surface.conflict
        color: Theme.vermLit
        font.family: Theme.font
        font.pixelSize: 10 * surface.s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Item {
        width: parent.width
        height: 30 * surface.s

        Rectangle {
            id: deleteBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: !surface.formAdd
            width: deleteLabel.implicitWidth + 24 * surface.s
            height: 28 * surface.s
            radius: 8 * surface.s
            color: deleteArea.containsMouse ? Qt.alpha(Theme.verm, 0.2) : Qt.alpha(Theme.verm, 0.1)
            border.width: 1
            border.color: Qt.alpha(Theme.vermLit, 0.45)

            Text {
                id: deleteLabel
                anchors.centerIn: parent
                text: "Delete"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 10.5 * surface.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.3 * surface.s
            }

            MouseArea {
                id: deleteArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: surface.removeBind()
            }
        }

        Rectangle {
            id: saveBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: saveLabel.implicitWidth + 30 * surface.s
            height: 28 * surface.s
            radius: 8 * surface.s
            color: saveArea.containsMouse ? Theme.vermLit : Theme.verm

            Text {
                id: saveLabel
                anchors.centerIn: parent
                text: "Save"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * surface.s
                font.weight: Font.Bold
                font.letterSpacing: 0.4 * surface.s
            }

            MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: surface.save()
            }
        }
    }
}

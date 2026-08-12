pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Hotspot block for the wifi drill-in: the toggle row plus the network and
 * password credential rows, with keyboard focus highlights driven by the
 * host's kbIndex. Pure view — state comes in as props and actions go back out
 * as signals. The host owns the anchors, visibility and height.
 */
Item {
    id: block

    property real s: 1.1
    property bool active: false
    property bool busy: false
    property string name: ""
    property string pw: ""
    property string edit: ""
    property string draft: ""
    property int kbIndex: -1
    property int toggleIndex: -1

    implicitHeight: hsCol.implicitHeight

    signal toggle()
    signal commitEdit()
    signal editRequested(string field, string value)
    signal draftEdited(string text)
    signal focusRequested(int index)

    /**
     * Begin editing one of the credential rows by keyboard, same path as a
     * click (requests the edit and focuses the field once it is visible).
     */
    function startEdit(field) {
        if (field === "name")
            hsNameRow.startEdit();
        else if (field === "pw")
            hsPwRow.startEdit();
    }

    Rectangle {
        id: hsDivider
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    Column {
        id: hsCol
        anchors.top: hsDivider.bottom
        anchors.topMargin: 9 * block.s
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6 * block.s

        Rectangle {
            width: parent.width
            height: 34 * block.s
            radius: 10 * block.s
            color: (block.active || block.kbIndex === block.toggleIndex) ? Theme.frameBg : "transparent"

            HoverHandler {
                onHoveredChanged: if (hovered) block.focusRequested(block.toggleIndex)
            }

            GlyphIcon {
                id: hsGlyph
                anchors.left: parent.left
                anchors.leftMargin: 8 * block.s
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * block.s
                height: 17 * block.s
                name: "hotspot"
                color: block.active ? Theme.flameGlow : Theme.iconDim
                stroke: 1.7
            }

            Column {
                anchors.left: hsGlyph.right
                anchors.leftMargin: 11 * block.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * block.s

                Text {
                    text: "Hotspot"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12.5 * block.s
                    font.weight: Font.DemiBold
                }
                Text {
                    text: block.busy ? "…" : (block.active ? "Active" : "Off")
                    color: block.active ? Theme.flameGlow : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * block.s
                    font.weight: Font.Medium
                }
            }

            LinkToggle {
                s: block.s
                anchors.right: parent.right
                anchors.rightMargin: 8 * block.s
                anchors.verticalCenter: parent.verticalCenter
                on: block.active
                onToggled: block.toggle()
            }
        }

        Item {
            width: parent.width
            height: 24 * block.s
            HoverHandler {
                onHoveredChanged: if (hovered) block.focusRequested(block.toggleIndex + 1)
            }

            Rectangle {
                anchors.fill: parent
                radius: 8 * block.s
                color: block.kbIndex === block.toggleIndex + 1 ? Theme.frameBg : "transparent"
            }

            CredRow {
                id: hsNameRow
                anchors.verticalCenter: parent.verticalCenter
                field: "name"
                label: "Network"
                value: block.name
                editing: block.edit === "name"
                scale: block.s
                draft: block.edit === "name" ? block.draft : ""
                onEditRequested: function(f, v) { block.editRequested(f, v) }
                onDraftEdited: function(t) { block.draftEdited(t) }
                onCommitted: block.commitEdit()
            }
        }

        Item {
            width: parent.width
            height: 24 * block.s
            HoverHandler {
                onHoveredChanged: if (hovered) block.focusRequested(block.toggleIndex + 2)
            }

            Rectangle {
                anchors.fill: parent
                radius: 8 * block.s
                color: block.kbIndex === block.toggleIndex + 2 ? Theme.frameBg : "transparent"
            }

            CredRow {
                id: hsPwRow
                anchors.verticalCenter: parent.verticalCenter
                field: "pw"
                label: "Password"
                value: block.pw
                secret: true
                editing: block.edit === "pw"
                scale: block.s
                draft: block.edit === "pw" ? block.draft : ""
                onEditRequested: function(f, v) { block.editRequested(f, v) }
                onDraftEdited: function(t) { block.draftEdited(t) }
                onCommitted: block.commitEdit()
            }
        }
    }
}

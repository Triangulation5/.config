pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.settings

/**
 * Updates conflict rows: every locally-edited file that the incoming update
 * would touch, each with a Keep-mine / Take-new BinarySeg. Choices land in
 * Updates.takePaths so the apply step knows what to do.
 */
Column {
    id: root

    property real s: 1.1
    property var host: null

    spacing: 9 * root.s
    visible: Updates.conflicts.length > 0

    Text {
        width: parent.width
        text: "Your edits clash with " + Updates.conflicts.length + " file" + (Updates.conflicts.length === 1 ? "" : "s")
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: Updates.conflicts

        Item {
            id: confRow
            required property var modelData
            readonly property string rel: modelData
            readonly property bool takeNew: Updates.takePaths[rel] === true

            width: parent.width
            height: 30 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.host.labelFor(confRow.rel)
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                font.weight: Font.DemiBold
            }

            Row {
                id: choice
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                BinarySeg {
                    label: "Keep mine"
                    on: !confRow.takeNew
                    corner: -1
                    onClicked: Updates.takePaths = Object.assign({}, Updates.takePaths, { [confRow.rel]: false })
                }

                BinarySeg {
                    label: "Take new"
                    on: confRow.takeNew
                    corner: 1
                    onClicked: Updates.takePaths = Object.assign({}, Updates.takePaths, { [confRow.rel]: true })
                }
            }
        }
    }
}

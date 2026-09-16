import QtQuick
import QtQuick.Layouts
import qs.config
import qs.pages
import qs.components.rows

/**
 * One card of settings: the group's `card` name as a heading over a rounded
 * card holding one row per entry in `group.rows`. The row's `type` picks its
 * editor (see SettingRowEditor), so a group is pure data and a page file never
 * touches a control.
 *
 * The card sizes to its rows: `implicitHeight` is the row column plus the
 * padding, which is what lets the content column's scroll view measure the
 * page before it is laid out.
 *
 * Each row sits in a slot item rather than directly in the column, because a
 * row the search asked for has to be ringed — and the ring cannot be drawn by
 * the row itself: a child of a QtQuick Layout is positioned by that layout, so a
 * background Rectangle inside one is a layout participant, not a backdrop. The
 * slot also carries the row's identity, which is what `itemFor` matches on and
 * what the content area scrolls to.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 10

    property var group: null

    /** The flag key or config field the search opened this page for, or "". */
    property string targetKey: ""

    /** Rows of the group, or none while `group` is unset. */
    readonly property var rows: root.group ? root.group.rows : []
    readonly property string card: root.group && root.group.card ? root.group.card : ""

    /**
     * The slot showing the row `key` names, or null. The content area maps it
     * into the page to scroll the ringed row into view.
     */
    function itemFor(key) {
        for (var i = 0; i < rowRepeater.count; i++) {
            var slot = rowRepeater.itemAt(i);
            if (slot && Pages.isRow(slot.row, key))
                return slot;
        }
        return null;
    }

    SectionLabel {
        visible: root.card.length > 0
        text: root.card
        Layout.fillWidth: true
    }

    Rectangle {
        Layout.fillWidth: true
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: rowColumn.implicitHeight + 36

        ColumnLayout {
            id: rowColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            Repeater {
                id: rowRepeater

                model: root.rows

                delegate: Item {
                    id: slot

                    required property var modelData

                    readonly property var row: modelData
                    readonly property bool highlighted: Pages.isRow(slot.row, root.targetKey)

                    Layout.fillWidth: true
                    implicitWidth: editor.implicitWidth
                    // Sized by its editor, which is a layout: the editor is
                    // given the width explicitly instead of being anchored, so
                    // this implicit height has something to resolve against.
                    implicitHeight: editor.implicitHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -10
                        visible: slot.highlighted
                        radius: Theme.radiusRow
                        color: Qt.alpha(Theme.accent, 0.10)
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.40)
                    }

                    SettingRowEditor {
                        id: editor
                        width: slot.width
                        row: slot.row
                    }
                }
            }
        }
    }
}

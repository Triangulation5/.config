import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * The skeleton every row editor is built on: the name on the left, a control
 * slot on the right, and a full-width slot underneath for a control that needs a
 * line of its own (the slider's groove). An editor fills those slots and owns
 * nothing else — the shell's `SettingsRow` plays the same role for the pill,
 * minus the glyph column and the soul seam.
 *
 * The caption is a *hint*, not a line: it is shown by the window's one shared
 * bubble while this row is hovered (see Hint), so a page of options reads as a
 * list of names with their controls instead of names over a paragraph each. The
 * row still owns the caption — it is the text the rail searches a row by — it
 * just hands it over on hover rather than printing it. Hover is reported through
 * the same `HoverHandler` the row would need for any other hover state, and a
 * row with an empty caption reports nothing at all.
 *
 * Neither slot is a container: they size to their contents, and an empty
 * `below` collapses to nothing so it does not leave a gap in the column.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 8

    property string label: ""
    /** Shown as a hover hint, never as a line of its own. */
    property string caption: ""

    /**
     * Hover, reported for the whole row. It is written into `data` rather than
     * declared as a bare child because this file redirects its default property
     * to the control slot (`default property alias control:`) — an unnamed
     * `HoverHandler {}` here would be parented to the control and would only see
     * the pointer while it sat on the switch or the chips, never on the row.
     */
    data: HoverHandler {
        id: rowHover

        /**
         * The pointer in scene coordinates: the bubble centres on the cursor,
         * and a row knows nothing of the hint layer that draws it.
         */
        function spot() {
            return root.mapToItem(null, rowHover.point.position.x, rowHover.point.position.y);
        }

        onHoveredChanged: hovered ? Hint.enter(root, root.caption, spot()) : Hint.leave(root)
        /** Reported on every move, so the bubble follows the cursor across the row. */
        onPointChanged: if (hovered) Hint.move(root, spot())
    }

    /** The control beside the text block: a switch, chips, a value, a field. */
    default property alias control: controlSlot.data

    /** Full-width area under the text block, for a groove or a preview. */
    property alias below: belowSlot.data

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            id: labelText
            text: root.label
            color: Theme.text
            font.pixelSize: Theme.fontSizeNormal
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            /** Centred against the control now that it is one line, not a block
              * that stretched to the row's height (which pinned the label to the
              * top of any row whose control was taller than its text). */
            Layout.alignment: Qt.AlignVCenter
        }

        RowLayout {
            id: controlSlot
            spacing: 4
        }
    }

    /**
     * A layout rather than a bare Item: a child of a plain Item keeps its own
     * zero size, so a slot declared that way would give the groove inside it a
     * zero-width parent and the slider would draw nothing.
     */
    ColumnLayout {
        id: belowSlot
        Layout.fillWidth: true
        spacing: 0
    }
}

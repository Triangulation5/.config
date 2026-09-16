import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * The skeleton every row editor is built on: the name and its caption on the
 * left, a control slot on the right, and a full-width slot underneath for a
 * control that needs a line of its own (the slider's groove). An editor fills
 * those slots and owns nothing else — the shell's `SettingsRow` plays the same
 * role for the pill, minus the glyph column and the soul seam.
 *
 * The text block is the shell's row hierarchy: the cream name, the faint
 * caption it uses for the same job, and the leftover width so a long caption
 * wraps instead of pushing the control off the card.
 *
 * Neither slot is a container: they size to their contents, and an empty
 * `below` collapses to nothing so it does not leave a gap in the column.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 8

    property string label: ""
    property string caption: ""

    /** The control beside the text block: a switch, chips, a value, a field. */
    default property alias control: controlSlot.data

    /** Full-width area under the text block, for a groove or a preview. */
    property alias below: belowSlot.data

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: root.label
                color: Theme.text
                font.pixelSize: Theme.fontSizeNormal
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Text {
                visible: root.caption.length > 0
                text: root.caption
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
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

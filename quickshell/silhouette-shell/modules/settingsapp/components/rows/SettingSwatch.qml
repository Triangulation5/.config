import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Swatch editor for `type: "swatch"` rows: a strip of colour chips on the
 * right, where exactly one is ringed in the live accent. The chips are named in
 * the row as `swatches` and painted by this app's own `Theme`, which mirrors
 * the shell's palette — so a chip is the colour it promises rather than a word
 * standing in for one.
 *
 * `Auto` comes first and is not a colour: it is the source's own tone, and it
 * paints that tone so the row shows what the choice will produce. A row that
 * only said "Auto" would make the user pick once to find out what they already
 * had.
 *
 * The chip sizes match the segmented editor's 24px strip so the two read as
 * one control family, and the ring is drawn outside the chip rather than
 * replacing its edge, so selecting one does not resize the row.
 */
SettingRow {
    id: root

    property var row: null

    /** Chip keys in order. `auto` is always available, whatever the row lists. */
    readonly property var keys: ["auto"].concat(root.row && root.row.swatches ? root.row.swatches : [])

    /** The key of the source this row colours — which default Auto resolves to. */
    readonly property string source: root.row && root.row.source ? root.row.source : ""

    readonly property var value: Sources.read(root.row)

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** The row's one write path: a chip's only job is to call it. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    control: RowLayout {
        spacing: 6

        Repeater {
            model: root.keys

            delegate: Rectangle {
                id: chip

                required property int index
                required property var modelData

                readonly property bool on: root.value === chip.modelData
                readonly property color swatch: Theme.privacySwatchColor(chip.modelData, root.source)

                width: 22
                height: 22
                radius: 11
                color: chip.swatch
                opacity: chipMouse.containsMouse ? 1 : 0.92

                /** The ring sits outside the chip, so picking does not resize it. */
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.accent
                    visible: chip.on
                }

                Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.commit(chip.modelData)
                }
            }
        }
    }
}

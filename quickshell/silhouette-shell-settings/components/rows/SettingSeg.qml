import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config

/**
 * Segmented editor for `type: "segmented"` rows: a strip of chips on the right
 * where exactly one is lit in the live accent. The row carries the choice as a
 * pair of lists — `options` are the values the shell's flag accepts, `names`
 * their labels, equal lengths in the same order. (The shell's `SettingsSeg`
 * takes the same pairing as `{ label, value }` objects; two lists keep a row
 * definition one line of data.)
 *
 * Selection keys off the value, never a child's visibility, and a pick only
 * writes through Sources — `value` stays a binding, so a mode changed from the
 * shell side lights the right chip here.
 */
SettingRow {
    id: root

    property var row: null

    readonly property var options: root.row && root.row.options ? root.row.options : []
    readonly property var names: root.row && root.row.names ? root.row.names : []
    readonly property var value: Sources.read(root.row)

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** The row's one write path: a chip's only job is to call it. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    control: RowLayout {
        spacing: 4

        Repeater {
            model: root.names

            delegate: Rectangle {
                required property int index
                required property var modelData

                readonly property bool on: root.value === root.options[index]

                implicitWidth: chipText.implicitWidth + 20
                implicitHeight: 24
                radius: 7
                color: on ? Theme.accent : (chipMouse.containsMouse ? Theme.selected : Theme.navButton)
                border.width: 1
                border.color: Theme.border
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.on ? Theme.knob : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSection
                    font.bold: true
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commit(root.options[parent.index])
                }
            }
        }
    }
}

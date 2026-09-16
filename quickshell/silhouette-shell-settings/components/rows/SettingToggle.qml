import QtQuick
import qs.components
import qs.config

/**
 * Switch editor for `type: "toggle"` rows. The track takes the live accent when
 * it is on and the knob flips to the on-accent ink — the pairing the shell's own
 * `LinkToggle` uses, where "on" is a solid accent fill rather than a tint.
 *
 * The editor reads its row through Sources and writes it back the same way, so
 * whatever holds the value — a shell flag, a Hyprland config field — stays in
 * sync with the switch, Reset and the source itself. Nothing here ever assigns
 * to `value`: that is a binding, and assigning would destroy it.
 */
SettingRow {
    id: root

    property var row: null

    readonly property bool value: Sources.read(root.row) === true

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** The row's one write path: the switch's only job is to call it. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    control: Rectangle {
        width: 42
        height: 22
        radius: 11
        color: root.value ? Theme.accent : Theme.sliderTrack
        border.width: root.value ? 0 : 1
        border.color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.value ? parent.width - width - 2 : 2
            color: root.value ? Theme.knob : Theme.text
            Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.commit(!root.value)
        }
    }
}

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Free-text editor for `type: "text"` rows: a field for the flags that hold a
 * path, a font name or a city, with the row's `placeholder` standing in for the
 * default the shell falls back to when the flag is empty. Editing commits when
 * the field is finished with (Return, or focus moving away), so a row never
 * writes on every keystroke — these are paths and font names, not search boxes.
 *
 * Typing drops the `text:` binding to the store — a Qt Quick field replaces its
 * text binding the moment the user produces input — so `onValueChanged` re-seeds
 * it by hand. Without that, Reset to Defaults and any change made in the shell
 * would leave stale text sitting in the field.
 */
SettingRow {
    id: root

    property var row: null

    readonly property string value: Sources.read(root.row) !== undefined ? String(Sources.read(root.row)) : ""

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** The row's one write path: the field's only job is to call it. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    control: TextField {
        id: field
        Layout.preferredWidth: 220
        text: root.value
        placeholderText: root.row && root.row.placeholder ? root.row.placeholder : ""
        placeholderTextColor: Theme.textSecondary
        color: Theme.text
        font.pixelSize: Theme.fontSizeSmall
        selectByMouse: true

        background: Rectangle {
            radius: 8
            color: Theme.searchField
            border.width: 1
            border.color: field.activeFocus ? Qt.alpha(Theme.accent, 0.45) : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }
        }

        onEditingFinished: root.commit(text)
    }

    onValueChanged: field.text = value
}

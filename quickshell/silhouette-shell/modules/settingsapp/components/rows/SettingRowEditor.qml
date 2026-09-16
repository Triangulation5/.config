import QtQuick
import qs.modules.settingsapp.components.rows
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Row dispatcher: one Loader per model row, showing the editor that `row.type`
 * asks for. A group of settings is data (`{ key, type, label, ... }`) and this
 * is where the data becomes a control, so a page file never names a widget.
 *
 * Adding an editor is a new file in this directory, an entry in the `editors`
 * map below and a line in qmldir — the pages then just use the new `type`. A
 * row whose `type` has no editor is loud rather than silent: the fallback names
 * the type and logs it, because a silently missing row is the hardest kind of
 * model bug to spot.
 *
 * The editor is handed the whole descriptor and reads what its type needs, so
 * the wiring lives with the control that understands it.
 */
Loader {
    id: root

    /** The row descriptor from the page model. */
    property var row: null

    readonly property string type: root.row ? root.row.type : ""

    /** type → editor. */
    readonly property var editors: ({
        toggle: toggleEditor,
        slider: sliderEditor,
        segmented: segmentedEditor,
        text: textEditor
    })

    sourceComponent: root.row === null ? null
        : (root.editors[root.type] !== undefined ? root.editors[root.type] : unknownEditor)

    Component {
        id: toggleEditor

        SettingToggle { row: root.row }
    }

    Component {
        id: sliderEditor

        SettingSlider { row: root.row }
    }

    Component {
        id: segmentedEditor

        SettingSeg { row: root.row }
    }

    Component {
        id: textEditor

        SettingText { row: root.row }
    }

    /** Unknown `type`: keep the row's name visible and say what is missing. */
    Component {
        id: unknownEditor

        SettingRow {
            label: root.row ? root.row.label : ""
            caption: "No editor for row type \u201C" + root.type + "\u201D"

            Component.onCompleted: console.warn("Settings: no editor for row type \"" + root.type + "\" (key " + (root.row ? root.row.key : "?") + ")")
        }
    }
}

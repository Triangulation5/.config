import QtQuick
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Button editor for `type: "action"` rows: a name and a caption like every other
 * row, but the control slot holds a button that runs a command instead of a value
 * to edit. `row.button` is its text, `row.done` the word it flips to afterwards,
 * and `row.action` is the function it runs.
 *
 * This is the one editor that never touches Sources, deliberately: a row that
 * edits nothing has no value to read or write, and giving it a write path would
 * imply the button stores something. It is also the only row whose subject is the
 * running shell rather than a file — the page owns what the command is, exactly
 * as DisplaysView's rows own their get/set closures, so the descriptor carries
 * the function and this file stays a button.
 *
 * A press flips the label to `done` for a moment. The commands worth a row like
 * this are quiet — unloading a closed surface has nothing on screen to watch —
 * so without the flash a working button and a dead one look identical.
 */
SettingRow {
    id: root

    property var row: null

    readonly property string buttonText: root.row && root.row.button ? root.row.button : "Run"
    readonly property string doneText: root.row && root.row.done ? root.row.done : "Done"

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** True for the short while after a press, while the button reports its run. */
    property bool justDone: false

    function run() {
        if (root.row && root.row.action)
            root.row.action();
        root.justDone = true;
        doneTimer.restart();
    }

    Timer {
        id: doneTimer
        interval: 1400
        onTriggered: root.justDone = false
    }

    control: Rectangle {
        implicitWidth: buttonLabel.implicitWidth + 26
        implicitHeight: 30
        radius: 9
        color: mouse.containsMouse ? Theme.selected : Theme.navButton
        border.width: 1
        border.color: root.justDone ? Qt.alpha(Theme.accent, 0.55) : Theme.border
        scale: mouse.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: root.justDone ? root.doneText : root.buttonText
            color: root.justDone ? Theme.text : Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.run()
        }
    }
}

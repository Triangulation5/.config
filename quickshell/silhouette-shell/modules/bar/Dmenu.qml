pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services

/**
 * The launcher, drawn inside the strip: a dmenu in the bar's own colours.
 *
 * It lays itself over the whole strip while the launcher is open and is built
 * fresh each time (Bar.qml loads it only on the output that carries the
 * launcher), so the query and the selection reset by construction. The shape is
 * dmenu's: a prompt block, an input, then the matches in one horizontal run with
 * the selected one inverted, a `<` or `>` at either end when the run does not
 * fit, and the match count at the far right. Everything is drawn from BarStyle,
 * so the launcher follows the palette and the chosen bar style like the readouts
 * it replaces, and the selected match is the same flat accent block as the lit
 * workspace tag.
 *
 * Keys, kept to dmenu's own where it has one:
 *   Enter           launch the selected match
 *   Shift+Enter     run what was typed as a shell command (so does Enter on no match)
 *   Tab             copy the selected match into the input
 *   Right/Down      next match         Ctrl+N
 *   Left/Up         previous match     Ctrl+P
 *   PageDown/Up     five matches at a time
 *   Ctrl+U / Ctrl+W clear the input / delete a word
 *   Esc / Ctrl+C    close
 *
 * Like the rest of the bar this has no MouseArea: it is driven from the keyboard,
 * which the strip takes exclusively for as long as the launcher is open.
 *
 * The state and the launching live in services/BarLauncher.qml; this is only the
 * view and the key map.
 */
Rectangle {
    id: root

    /** Type scale, as the blocks get it; `g` is the geometry scale the strip's margins use. */
    property real s: 1.1
    property real g: 1

    readonly property color tile: BarStyle.flat(Theme.tileBg)

    /**
     * The strip's own backdrop. The plain style has none, which is right for a
     * row of readouts but leaves a prompt to be read over whatever is behind the
     * bar, so the launcher gives itself the tile colour, near opaque, there.
     */
    color: BarStyle.mode === "plain" ? Qt.rgba(tile.r, tile.g, tile.b, 0.94) : BarStyle.bg

    function focusInput() {
        input.forceActiveFocus();
    }

    /** Tab: take the selected match's name into the input, as dmenu does. */
    function complete() {
        var entry = BarLauncher.current();
        if (!entry)
            return;
        input.text = entry.name;
        input.cursorPosition = input.text.length;
    }

    Component.onCompleted: root.focusInput()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12 * root.g
        anchors.rightMargin: 12 * root.g
        spacing: 12 * root.g

        /** The prompt: the lit workspace tag's flat block, so the strip keeps one accent shape. */
        Chip {
            s: root.s
            radius: 0
            fill: BarStyle.accent
            edge: "transparent"
            Layout.alignment: Qt.AlignVCenter

            Text {
                text: "run"
                color: BarStyle.accentInk
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.min(root.width * 0.3, 280 * root.s)
            Layout.preferredHeight: input.implicitHeight
            clip: true

            TextInput {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                color: BarStyle.fg
                selectionColor: BarStyle.accent
                selectedTextColor: BarStyle.accentInk
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s

                onTextChanged: {
                    BarLauncher.query = input.text;
                    BarLauncher.selected = 0;
                }

                Keys.onPressed: (event) => {
                    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    var shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                    switch (event.key) {
                    case Qt.Key_Escape:
                        BarLauncher.hide();
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (shift || BarLauncher.results.length === 0)
                            BarLauncher.runTyped();
                        else
                            BarLauncher.accept();
                        break;
                    case Qt.Key_Tab:
                        root.complete();
                        break;
                    case Qt.Key_Right:
                    case Qt.Key_Down:
                        BarLauncher.move(1);
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_Up:
                        BarLauncher.move(-1);
                        break;
                    case Qt.Key_PageDown:
                        BarLauncher.move(5);
                        break;
                    case Qt.Key_PageUp:
                        BarLauncher.move(-5);
                        break;
                    case Qt.Key_N:
                        if (!ctrl)
                            return;
                        BarLauncher.move(1);
                        break;
                    case Qt.Key_P:
                        if (!ctrl)
                            return;
                        BarLauncher.move(-1);
                        break;
                    case Qt.Key_C:
                        if (!ctrl)
                            return;
                        BarLauncher.hide();
                        break;
                    case Qt.Key_U:
                        if (!ctrl)
                            return;
                        input.text = "";
                        break;
                    case Qt.Key_W:
                        if (!ctrl)
                            return;
                        input.text = input.text.replace(/\s*\S*\s*$/, "");
                        break;
                    default:
                        /** Not ours: left unaccepted so the field types it. */
                        return;
                    }
                    event.accepted = true;
                }
            }
        }

        /** dmenu keeps the marker's width reserved, so the run does not jump as it scrolls. */
        Text {
            text: "<"
            color: list.atXBeginning ? "transparent" : BarStyle.dim
            font.family: Theme.font
            font.pixelSize: 12.5 * root.s
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                orientation: ListView.Horizontal
                clip: true
                interactive: false
                spacing: 2 * root.s
                model: BarLauncher.results

                /** A new query is a new list: back to the first match, not wherever the last one left off. */
                onModelChanged: list.positionViewAtBeginning()

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    readonly property bool sel: cell.index === BarLauncher.selected

                    width: label.implicitWidth + 2 * 7 * root.s
                    height: list.height

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: label.implicitHeight + 2 * 2 * root.s
                        color: cell.sel ? BarStyle.accent : "transparent"

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: cell.modelData.name
                            color: cell.sel ? BarStyle.accentInk : BarStyle.fg
                            font.family: Theme.font
                            font.pixelSize: 12.5 * root.s
                            font.weight: cell.sel ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }

            /** A query nothing matches still has an answer: it can be run as typed. */
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: BarLauncher.results.length === 0 && BarLauncher.query.length > 0
                text: "no match \u00b7 enter runs it as a command"
                color: BarStyle.dim
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
            }
        }

        Text {
            text: ">"
            color: list.atXEnd ? "transparent" : BarStyle.dim
            font.family: Theme.font
            font.pixelSize: 12.5 * root.s
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: BarLauncher.results.length + "/" + BarLauncher.total
            color: BarStyle.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.features: ({ "tnum": 1 })
            Layout.alignment: Qt.AlignVCenter
        }
    }

    /** Keep the selected match on screen as it moves; Contain scrolls the least it can. */
    Connections {
        target: BarLauncher
        function onSelectedChanged() {
            list.positionViewAtIndex(BarLauncher.selected, ListView.Contain);
        }
    }
}

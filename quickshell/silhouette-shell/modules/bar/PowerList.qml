pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services

/**
 * The power menu in the minimal bar: the launcher shape, pointed at the five
 * session actions. The bar's answer to the pill's power surface, which is a
 * PillSurface and so has nowhere to live while the bar is the shell.
 *
 * Drawn from the same tokens as everything else on the strip, so it reads as the
 * in-strip dmenu it sits beside rather than as a pill surface that lost its
 * pill: the prompt block is the launcher's `run` block, the selected action is
 * the same flat accent block as the lit workspace tag, and the backdrop is the
 * strip's own, taking the tile colour in the plain style for the same reason the
 * launcher does — a row of readouts needs no backdrop, a row of things you can
 * pick from needs something to read them against.
 *
 * Searchable, and the field is deliberately the *same size as the launcher's* —
 * the same `Math.min(width * 0.3, 280 * s)` box, the same 12px gaps, the same
 * right-hand count. Two pickers that open on the same key of muscle memory
 * should not disagree about where the cursor is, and matching the geometry
 * rather than approximately matching it is what buys that; the alternative was a
 * power list whose search box jumped to a different place from the launcher's.
 *
 * Keys are the launcher's, since this is the same kind of thing: Left/Right (or
 * Ctrl+N/P) to move, Enter to choose, Esc to close, and the dmenu input keys
 * (Ctrl+U clear, Ctrl+W delete a word). A destructive action takes two Enters
 * inside the arm window — the bar's version of the pill surface's hold, for the
 * same reason: a reboot should not be one keypress away. The right-hand count
 * states which of the two it is on, so the next Enter is never a guess.
 *
 * The run is a `Row`, not a scroller: the launcher's needs one because its
 * matches are unbounded, and five items fit in a strip.
 *
 * No MouseArea, like the rest of the bar: the strip takes the keyboard
 * exclusively while this is open, and the bar is a glance, not a control surface.
 */
Rectangle {
    id: root

    /** Type scale, as the blocks get it; `g` is the geometry scale the strip's margins use. */
    property real s: 1.1
    property real g: 1

    readonly property color tile: BarStyle.flat(Theme.tileBg)

    /**
     * The strip's own backdrop, with the launcher's reason for the plain style:
     * the tile colour near opaque, so the actions read against the wallpaper.
     */
    color: BarStyle.mode === "plain" ? Qt.rgba(tile.r, tile.g, tile.b, 0.94) : BarStyle.bg

    /** The strip calls this on load, as it does the launcher's input. */
    function focusInput() {
        input.forceActiveFocus();
    }

    Component.onCompleted: root.focusInput()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12 * root.g
        anchors.rightMargin: 12 * root.g
        spacing: 12 * root.g

        /** The prompt: the launcher's `run` block, so the strip keeps one accent shape. */
        Chip {
            s: root.s
            radius: 0
            fill: BarStyle.accent
            edge: "transparent"
            Layout.alignment: Qt.AlignVCenter

            Text {
                text: "power"
                color: BarStyle.accentInk
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }
        }

        /** The launcher's own field box, to the pixel. See the header. */
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

                onTextChanged: BarPower.setQuery(text)

                Keys.onPressed: (event) => {
                    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                    switch (event.key) {
                    case Qt.Key_Escape:
                        BarPower.hide();
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        BarPower.armOrAccept();
                        break;
                    case Qt.Key_Right:
                    case Qt.Key_Down:
                        BarPower.move(1);
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_Up:
                        BarPower.move(-1);
                        break;
                    case Qt.Key_PageDown:
                        BarPower.move(3);
                        break;
                    case Qt.Key_PageUp:
                        BarPower.move(-3);
                        break;
                    case Qt.Key_N:
                        if (!ctrl)
                            return;
                        BarPower.move(1);
                        break;
                    case Qt.Key_P:
                        if (!ctrl)
                            return;
                        BarPower.move(-1);
                        break;
                    case Qt.Key_C:
                        if (!ctrl)
                            return;
                        BarPower.hide();
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

        /**
         * The run of matching actions. Empty-state handled below rather than by
         * hiding the run, so the field and the count stay put and the strip does
         * not reflow under someone who is still typing.
         */
        Row {
            id: run
            spacing: 2 * root.s
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: BarPower.results

                delegate: Rectangle {
                    id: cell

                    required property int index
                    required property var modelData

                    readonly property bool sel: cell.index === BarPower.selected
                    /** Armed by a first Enter, waiting on its second. Keyed, not indexed. */
                    readonly property bool armed: BarPower.armed
                        && cell.modelData.key === BarPower.armedKey

                    width: label.implicitWidth + 2 * 7 * root.s
                    height: label.implicitHeight + 2 * 3 * root.s
                    radius: 0
                    color: cell.sel ? BarStyle.accent : "transparent"
                    border.width: cell.armed && !cell.sel ? 1 : 0
                    border.color: BarStyle.warn

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: cell.modelData.label
                        color: cell.sel ? BarStyle.accentInk
                            : (cell.armed ? BarStyle.warn : BarStyle.fg)
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: cell.sel ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }

        Item { Layout.fillWidth: true; Layout.fillHeight: true }

        /**
         * The launcher's count, carrying the confirm instruction: `5/5`, then the
         * count of what the query matched beside what the next Enter does. A
         * destructive action never takes a second press the user did not know they
         * were making, and this is where that is said.
         */
        Text {
            readonly property var act: BarPower.focused
            text: {
                if (BarPower.results.length === 0)
                    return "no match";
                var count = (BarPower.results.length + "/" + BarPower.actions.length)
                    + "   ";
                if (!act)
                    return count.trim();
                if (!act.confirm)
                    return count + "↵ " + act.label.toLowerCase();
                return count + (BarPower.armed
                    ? "↵ again to " + act.label.toLowerCase()
                    : "↵ twice to " + act.label.toLowerCase());
            }
            color: act && act.confirm ? BarStyle.warn : BarStyle.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.features: ({ "tnum": 1 })
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
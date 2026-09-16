import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * The rail's search field. `text` is the live query, aliased straight off the
 * input so the rail can bind its filtering to it without a second copy of the
 * string, and the placeholder is drawn as a sibling Text rather than through
 * `TextInput`'s own placeholder so it inherits the row's ink.
 *
 * The magnifier is drawn rather than typed: no font in the panel's stack carries
 * a glass at a size that matches the rest of the rail, and a glyph would change
 * shape with the installed family. Two strokes on a Canvas are the same icon
 * everywhere — and it warms to the accent while the field is focused, which is
 * the only thing in the rail that says where the typing goes.
 */
Rectangle {
    id: root

    property alias text: input.text

    implicitHeight: 34
    radius: 10
    color: Theme.searchField
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(Theme.accent, 0.35) : Theme.border

    Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 8
        spacing: 8

        /** The glass: a ring and a 45° handle, drawn on one canvas. */
        Canvas {
            id: glass

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 14
            implicitHeight: 14

            /** Repainted whenever the ink or the focus changes. */
            property color stroke: input.activeFocus ? Theme.accent : Theme.textSecondary

            onStrokeChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = 1.5;
                ctx.lineCap = "round";
                ctx.strokeStyle = glass.stroke;
                // Ring, centred a touch up-left so the handle has room.
                ctx.beginPath();
                ctx.arc(6.1, 6.1, 4.3, 0, Math.PI * 2);
                ctx.stroke();
                // Handle, out of the ring's lower-right at 45°.
                ctx.beginPath();
                ctx.moveTo(9.5, 9.5);
                ctx.lineTo(13.1, 13.1);
                ctx.stroke();
            }
        }

        TextInput {
            id: input

            Layout.fillWidth: true
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            clip: true
            selectByMouse: true

            Text {
                text: "Search Settings"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                visible: input.text.length === 0
            }

            Keys.onEscapePressed: input.text = ""
        }

        /**
         * Clear, shown only while there is something to clear. Forgetting a
         * query used to mean selecting the text and deleting it with the mouse
         * held down, which is a silly amount of care for one keystroke.
         */
        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: input.text.length > 0
            text: "\u00D7"
            color: clearArea.containsMouse ? Theme.text : Theme.textSecondary
            font.pixelSize: 15

            MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: input.text = ""
            }
        }
    }
}

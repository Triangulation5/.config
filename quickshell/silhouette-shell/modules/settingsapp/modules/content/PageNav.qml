import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * The content column's header: back/forward chevrons and the open page's name.
 * It reports a step rather than moving anything itself — `index` and `count` say
 * where it is, and the click goes out through `step` — because the host owns the
 * selection. A chevron that assigned to the page index would destroy the
 * binding that keeps the rail and the content in sync, and the rail would never
 * drive the page again.
 *
 * At either end the chevron dims and stops responding, rather than clamping
 * silently against a wall with no feedback.
 *
 * The name is the whole header. Every page used to print a one-liner beside it
 * saying what the page was for, which the rail's own rows then repeated row by
 * row: by the time you had opened a page you had already read what it holds, so
 * the line was a second summary of the thing already on screen, taking the width
 * the title could have used. The row now ends after the name.
 */
RowLayout {
    id: root

    property int index: 0
    property int count: 0
    property string title: ""

    signal step(int dir)

    Layout.fillWidth: true
    spacing: 8

    Repeater {
        model: [{ glyph: "\u2039", dir: -1 }, { glyph: "\u203A", dir: 1 }]

        delegate: Item {
            id: chevron

            required property var modelData

            readonly property bool atEnd: (chevron.modelData.dir < 0 && root.index <= 0)
                || (chevron.modelData.dir > 0 && root.index >= root.count - 1)

            /**
             * Ink only. Both chevrons used to be 28px cards like every other
             * button in the window, which put two grey tiles in the header of a
             * page whose body is cards and read as two more things to click
             * rather than as the way out of the page — and the card was drawn
             * whether or not the step existed, so an enabled chevron and a dead
             * one looked identical. The glyph itself carries the affordance now:
             * dim at the ends of the list, brighter under the pointer.
             */
            readonly property color ink: chevron.atEnd ? Theme.faint
                : (mouse.containsMouse ? Theme.text : Theme.textSecondary)

            width: 28
            height: 28

            Text {
                anchors.centerIn: parent
                text: chevron.modelData.glyph
                color: chevron.ink
                font.pixelSize: 15
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: chevron.atEnd ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!chevron.atEnd) root.step(chevron.modelData.dir)
            }
        }
    }

    Text {
        text: root.title
        color: Theme.text
        font.pixelSize: Theme.fontSizeTitle
        font.bold: true
        Layout.leftMargin: 10
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
}

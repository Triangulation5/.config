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
 * `caption` is the page's own one-liner, printed beside the name. It takes what
 * is left of the row and elides there instead of wrapping, so a long one cannot
 * make the header taller and shift every card below it — and the filler item
 * steps aside when there is one, so it gets the whole remainder.
 */
RowLayout {
    id: root

    property int index: 0
    property int count: 0
    property string title: ""
    property string caption: ""

    signal step(int dir)

    Layout.fillWidth: true
    spacing: 8

    Repeater {
        model: [{ glyph: "\u2039", dir: -1 }, { glyph: "\u203A", dir: 1 }]

        delegate: Rectangle {
            id: chevron

            required property var modelData

            readonly property bool atEnd: (chevron.modelData.dir < 0 && root.index <= 0)
                || (chevron.modelData.dir > 0 && root.index >= root.count - 1)

            width: 28
            height: 28
            radius: 8
            color: mouse.containsMouse && !chevron.atEnd ? Theme.hover : Theme.navButton
            border.width: 1
            border.color: chevron.atEnd ? Theme.border : Theme.border

            Behavior on color { ColorAnimation { duration: Theme.animNormal } }

            Text {
                anchors.centerIn: parent
                text: chevron.modelData.glyph
                color: chevron.atEnd ? Theme.textSecondary : Theme.textSecondary
                font.pixelSize: 15
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
    }

    Text {
        visible: root.caption.length > 0
        text: root.caption
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSection
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.leftMargin: 12
    }

    Item { Layout.fillWidth: root.caption.length === 0 }
}

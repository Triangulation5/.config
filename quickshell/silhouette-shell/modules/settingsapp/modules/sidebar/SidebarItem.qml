import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * One nav row of the rail: the page's icon glyph in a tinted circle beside its
 * name, over a highlight that fills when the page is the open one and lifts on
 * hover. It is a dumb row — the rail owns the selection and the page index, this
 * only reports a click.
 *
 * The circle is a tint of the live accent rather than a fixed green, so the rail
 * follows the palette the way every other surface does.
 */
Item {
    id: root

    property string label: ""
    property string icon: "\u25CF"
    property bool selected: false

    signal clicked()

    implicitHeight: 45

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        radius: Theme.radiusRow
        color: root.selected
            ? Theme.selected
            : (mouse.containsMouse ? Theme.hover : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: root.selected ? Qt.alpha(Theme.accent, 0.32)
                                     : Qt.alpha(Theme.accent, 0.14)
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: Theme.accent
                    font.pixelSize: 13
                }
            }

            Text {
                text: root.label
                color: root.selected ? Theme.text : Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

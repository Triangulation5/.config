import QtQuick
import QtQuick.Controls
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Dropdown editor for `type: "select"` rows: the current choice on a button,
 * and the full list in a popup. The segmented editor is the wrong shape for a
 * list this long — nine Material scheme variants would either squeeze the row
 * or wrap — so a select exists for the rows where the options are a menu, not a
 * switch.
 *
 * The row carries the same `options`/`names` pair every choice editor reads
 * (see SettingSeg), and a pick goes through Sources like any other write. The
 * popup opens upward when the row is near the bottom of the window, because the
 * last row on a page should not put its menu off-screen.
 */
SettingRow {
    id: root

    property var row: null

    readonly property var options: root.row && root.row.options ? root.row.options : []
    readonly property var names: root.row && root.row.names ? root.row.names : []
    readonly property var value: Sources.read(root.row)
    readonly property int selectedIndex: Math.max(0, root.options.indexOf(root.value))

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /** The row's one write path. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    control: Rectangle {
        id: button

        implicitWidth: 240
        implicitHeight: 26
        radius: 7
        color: mouse.containsMouse || menu.visible ? Theme.selected : Theme.navButton
        border.width: 1
        border.color: Theme.border

        Text {
            id: valueText

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: chevron.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.names[root.selectedIndex] !== undefined ? root.names[root.selectedIndex] : ""
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: "\u25BE"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menu.visible ? menu.close() : root.openMenu()
        }

        Popup {
            id: menu

            parent: button
            width: button.width
            height: Math.min(menuColumn.implicitHeight + 8, 300)
            x: parent.width - width
            padding: 4
            modal: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: Rectangle {
                color: Theme.card
                radius: 10
                border.width: 1
                border.color: Theme.border
            }

            contentItem: Column {
                id: menuColumn

                width: menu.width - 8
                spacing: 2

                Repeater {
                    model: root.names

                    delegate: Rectangle {
                        required property int index
                        required property var modelData

                        readonly property bool on: index === root.selectedIndex

                        width: menuColumn.width
                        height: 26
                        radius: 6
                        color: itemMouse.containsMouse ? Theme.selected : (on ? Theme.hover : "transparent")

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData
                            color: parent.on ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSection
                            font.bold: parent.on
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: itemMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.commit(root.options[parent.index]);
                                menu.close();
                            }
                        }
                    }
                }
            }
        }
    }

    /** Open above the button when it sits in the lower half of the window. */
    function openMenu() {
        var point = button.mapToItem(null, 0, 0);
        menu.y = point.y > 300 ? -(menu.height + 6) : button.height + 6;
        menu.open();
    }
}

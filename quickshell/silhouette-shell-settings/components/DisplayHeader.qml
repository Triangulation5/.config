import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.components

/**
 * A monitor's portrait, sitting above its settings: the shape on the left, and on
 * the right the output name, the Main marker, the model the backend reports and
 * the live mode and position. The settings card below carries the controls only,
 * so the name appears here and the card needs no heading of its own.
 *
 * Everything on the right is read from the live monitor object, so a mode applied
 * a moment ago is already on this line — the header is the receipt for what the
 * rows below just did, which is why it must never cache the values it shows.
 *
 * Clicking the shape selects the monitor, the same gesture the arrangement map
 * offers: the two pieces of the page point at each other instead of each having
 * its own idea of what is selected.
 */
Rectangle {
    id: root

    /** The live monitor. */
    property var mon: null

    /** The config declares this the main output. */
    property bool main: false

    /** This monitor is the selected one, from the map or from its own shape. */
    property bool sel: false

    signal picked()

    implicitHeight: head.implicitHeight + 32
    color: Theme.card
    radius: Theme.radiusCard
    border.width: 1
    border.color: root.sel ? Qt.alpha(Theme.accent, 0.45) : Theme.border
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    /** `1920×1080 @ 60Hz · scale 1× · at 0×0` from the live monitor. */
    readonly property string specLine: {
        if (root.mon === null)
            return "";
        return root.mon.width + "\u00D7" + root.mon.height + " @ " + root.mon.refresh + "Hz"
            + "   \u00B7   scale " + root.mon.scale + "\u00D7"
            + "   \u00B7   at " + root.mon.x + "\u00D7" + root.mon.y;
    }

    RowLayout {
        id: head
        anchors.fill: parent
        anchors.margins: 16
        spacing: 18

        // The shape carries the click, not the whole card: the card is a heading,
        // and a heading that swallows clicks would eat the pointer everywhere the
        // user might expect to select text or just aim.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: shape.implicitWidth
            implicitHeight: shape.implicitHeight

            DisplayShape {
                id: shape
                anchors.fill: parent
                mon: root.mon
                main: root.main
                sel: root.sel
                hovered: shapeArea.containsMouse
                maxWidth: 176
                maxHeight: 104
            }

            MouseArea {
                id: shapeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.mon ? root.mon.name : ""
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeTitle - 4
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.main
                    width: mainLabel.implicitWidth + 16
                    height: 19
                    radius: 9.5
                    color: Qt.alpha(Theme.accent, 0.13)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, 0.40)

                    Text {
                        id: mainLabel
                        anchors.centerIn: parent
                        text: "Main"
                        color: Theme.accent
                        font.pixelSize: Theme.fontSizeSection
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: Monitors.identity(root.mon)
                color: Theme.text
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.specLine
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }
    }
}

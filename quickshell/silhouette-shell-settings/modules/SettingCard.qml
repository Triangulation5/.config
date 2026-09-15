import QtQuick
import QtQuick.Layouts
import "../config"

Rectangle {
    id: root
    color: Theme.card
    radius: Theme.radiusCard
    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + 36

    default property alias content: contentColumn.children

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 18
        spacing: 18
    }
}

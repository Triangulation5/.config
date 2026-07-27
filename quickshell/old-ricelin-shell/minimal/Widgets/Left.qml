import QtQuick
import QtQuick.Layouts

Row {
    Layout.alignment: Qt.AlignVCenter
    spacing: 8

    Workspaces {}

    Rectangle {
        width: 1
        height: 14
        color: "#606079F2"
        Layout.alignment: Qt.AlignVCenter
    }

    TilingLayout {}

    WindowTitle {}
}

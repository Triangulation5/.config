import QtQuick
import QtQuick.Layouts

Row {
    Layout.alignment: Qt.AlignVCenter
    spacing: 12

    Cpu {}
    Memory {}
    Volume {}

    Rectangle {
        width: 1
        height: 14
        color: "#606079F2"
        Layout.alignment: Qt.AlignVCenter
    }

    Clock {}
}

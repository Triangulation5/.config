import Quickshell
import QtQuick
import QtQuick.Layouts

import "Widgets" as Widgets

PanelWindow {
    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 27
    color: "#141415"

    Rectangle {
        anchors.fill: parent
        color: "#141415"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8

            Widgets.Left {}

            Item {
                Layout.fillWidth: true
            }

            Widgets.Right {}
        }
    }
}

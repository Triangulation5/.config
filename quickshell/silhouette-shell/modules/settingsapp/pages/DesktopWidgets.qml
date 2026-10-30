pragma Singleton

import QtQuick

QtObject {
    readonly property string name: "Desktop widgets"
    readonly property string icon: "\u25A6"
    readonly property string keywords: "desktop widgets clock system load moon calendar weather music arrange move drag resize"
    readonly property var view: Qt.resolvedUrl("DesktopWidgetsView.qml")
    readonly property var groups: []
}

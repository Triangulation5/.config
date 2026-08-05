pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared flags & settings adapter reading/writing to flags.json.
 */

Singleton {
    property alias paletteMode: adapter.paletteMode
    property alias time12h: adapter.time12h
    property alias topGap: adapter.topGap
    property alias gameMode: adapter.gameMode
    property alias notchStyle: adapter.notchStyle

    property alias visualizerEnabled: adapter.visualizerEnabled
    property alias showSeconds: adapter.showSeconds
    property alias dateFormat: adapter.dateFormat
    property alias brightness: adapter.brightness
    property alias nightLight: adapter.nightLight
    property alias wifiEnabled: adapter.wifiEnabled
    property alias currentNetwork: adapter.currentNetwork
    property alias bluetoothActive: adapter.bluetoothActive

    function save(): void {
        fileView.setText(JSON.stringify(adapter.json, null, 4));
    }

    FileView {
        id: fileView

        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        JsonAdapter {
            id: adapter

            property string paletteMode: "static"
            property bool time12h: true
            property bool notchStyle: false
            property real topGap: notchStyle ? 0 : 0.7
            property bool gameMode: false

            property bool visualizerEnabled: true
            property bool showSeconds: false
            property string dateFormat: "Monday, July 30"
            property real brightness: 0.85
            property bool nightLight: false
            property bool wifiEnabled: true
            property string currentNetwork: "Home_WiFi_5G"
            property bool bluetoothActive: true
        }
    }
}

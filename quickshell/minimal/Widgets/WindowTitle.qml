import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: root

    color: "#cdcdcd"
    font.pixelSize: 14

    property string windowTitle: ""

    text: windowTitle

    Process {
        id: hyprctl

        command: ["hyprctl", "activewindow", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(text)
                    root.windowTitle = data.title || ""
                } catch (e) {
                    root.windowTitle = ""
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: {
            hyprctl.running = false
            hyprctl.running = true
        }
    }

    visible: windowTitle.length > 0
}

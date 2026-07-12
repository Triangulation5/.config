import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: root

    color: "#cdcdcd"

    property string layout: "[]="

    text: layout

    Process {
        id: layoutReader

        command: [
            "bash",
            "-c",
            "hyprctl activeworkspace -j | jq -r .tiledLayout"
        ]

        stdout: SplitParser {
            onRead: data => {
                const symbols = {
                    "master": "[]=",
                    "dwindle": "><>",
                    "scrolling": "[S]"
                }

                root.layout = symbols[data.trim()] ?? "?"
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: {
            layoutReader.running = false
            layoutReader.running = true
        }
    }

    Component.onCompleted: {
        layoutReader.running = true
    }
}

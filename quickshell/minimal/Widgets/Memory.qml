import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: root

    property int usedMemory: 0

    color: "#cdcdcd"
    text: "Mem " + usedMemory + "%"

    Process {
        id: memReader

        command: [
            "bash",
            "-c",
            "free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'"
        ]

        stdout: SplitParser {
            onRead: data => {
                let value = Number(data.trim())
                if (!isNaN(value))
                    root.usedMemory = value
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true

        onTriggered: {
            memReader.running = false
            memReader.running = true
        }
    }
}

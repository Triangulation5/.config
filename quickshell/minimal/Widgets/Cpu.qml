import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: root

    property int usage: 0

    color: "#cdcdcd"
    text: "CPU " + usage + "%"

    Process {
        id: cpuReader

        command: [
            "bash",
            "-c",
            "top -bn1 | grep 'Cpu(s)' | awk '{print 100-$8}'"
        ]

        stdout: SplitParser {
            onRead: data => {
                let value = Number(data.trim())
                if (!isNaN(value))
                    root.usage = Math.round(value)
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true

        onTriggered: {
            cpuReader.running = false
            cpuReader.running = true
        }
    }
}

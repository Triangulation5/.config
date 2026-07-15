import QtQuick

Text {
    color: "#cdcdcd"

    function update() {
        text = Qt.formatDateTime(
            new Date(),
            "ddd MMM dd hh:mm AP"
        )
    }

    Component.onCompleted: update()

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: update()
    }
}

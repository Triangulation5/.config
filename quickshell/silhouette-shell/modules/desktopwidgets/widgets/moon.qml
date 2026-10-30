import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.services

Item {
    id: root

    readonly property real s: Math.max(0.78, Math.min(1.7, Math.min(width / 258, height / 166)))
    property var now: new Date()
    readonly property real age: Weather.moonAgeFor(now)
    readonly property int illumination: Math.round((1 - Math.cos(2 * Math.PI * age)) * 50)
    readonly property string phase: Weather.moonPhaseFor(now)
    readonly property var fullDate: new Date(now.getTime() + ((0.5 - age + 1) % 1) * 29.53058867 * 86400000)
    readonly property var newDate: new Date(now.getTime() + ((1 - age) % 1) * 29.53058867 * 86400000)
    readonly property var days: {
        var firstOffset = (new Date(now.getFullYear(), now.getMonth(), 1).getDay() + 6) % 7;
        var out = [];
        for (var i = 0; i < 42; i++) {
            var date = new Date(now.getFullYear(), now.getMonth(), i - firstOffset + 1);
            out.push({
                day: date.getDate(),
                inMonth: date.getMonth() === now.getMonth(),
                today: date.getFullYear() === now.getFullYear()
                    && date.getMonth() === now.getMonth()
                    && date.getDate() === now.getDate(),
                full: date.getMonth() === fullDate.getMonth()
                    && date.getFullYear() === fullDate.getFullYear()
                    && date.getDate() === fullDate.getDate(),
                fresh: date.getMonth() === newDate.getMonth()
                    && date.getFullYear() === newDate.getFullYear()
                    && date.getDate() === newDate.getDate()
            });
        }
        return out;
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Rectangle {
        anchors.fill: parent
        radius: 22 * root.s
        color: Theme.surfaceContainerLowest
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.25)
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12 * root.s
        spacing: 10 * root.s

        Column {
            width: 88 * root.s
            height: parent.height
            spacing: 3 * root.s

            Item {
                width: 66 * root.s
                height: 66 * root.s
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: 58 * root.s
                    height: width
                    radius: width / 2
                    color: Theme.surfaceContainerHigh
                }

                Rectangle {
                    id: moonLight
                    anchors.centerIn: parent
                    width: 58 * root.s
                    height: width
                    radius: width / 2
                    color: Theme.primary
                }

                Rectangle {
                    width: moonLight.width * (1 - root.illumination / 100)
                    height: moonLight.height
                    x: root.age < 0.5
                        ? moonLight.x
                        : moonLight.x + moonLight.width - width
                    y: moonLight.y
                    radius: width / 2
                    color: Theme.surfaceContainerHigh
                }

                Repeater {
                    model: [
                        { x: 16, y: 17, r: 3.2 },
                        { x: 35, y: 37, r: 2.4 },
                        { x: 20, y: 42, r: 2.8 }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        x: (modelData.x - modelData.r) * root.s
                        y: (modelData.y - modelData.r) * root.s
                        width: modelData.r * 2 * root.s
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Theme.onPrimary, 0.15)
                        visible: root.illumination > 45
                    }
                }
            }

            Item { width: 1; height: 1; anchors.horizontalCenter: parent.horizontalCenter }

            Text {
                width: parent.width
                text: root.phase
                color: Theme.onSurface
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: root.illumination + "% lit"
                color: Theme.onSurfaceVariant
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.features: ({ "tnum": 1 })
            }

            Text {
                width: parent.width
                text: "new " + Qt.formatDate(root.newDate, "ddd d")
                color: Theme.onSurfaceVariant
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                elide: Text.ElideRight
            }
        }

        Column {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width - 98 * root.s
            spacing: 4 * root.s

            Row {
                width: parent.width

                Text {
                    id: monthText
                    width: parent.width - eventsText.implicitWidth
                    text: Qt.formatDate(root.now, "MMMM")
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.weight: Font.Bold
                }

                Text {
                    id: eventsText
                    text: "new " + root.newDate.getDate() + " · ○ " + root.fullDate.getDate()
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            Row {
                id: weekHeader
                width: parent.width
                height: 12 * root.s

                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    delegate: Text {
                        required property string modelData
                        width: weekHeader.width / 7
                        text: modelData
                        color: Theme.onSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Grid {
                id: calendar
                width: parent.width
                height: parent.height - 20 * root.s
                columns: 7
                rows: 6
                rowSpacing: 0
                columnSpacing: 0

                Repeater {
                    model: root.days

                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: calendar.width / 7
                        height: calendar.height / 6
                        opacity: modelData.inMonth ? 1 : 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * 0.86
                            height: width
                            radius: width / 2
                            color: cell.modelData.today ? Theme.primary
                                : cell.modelData.fresh ? Theme.surfaceContainerHigh : "transparent"
                            border.width: cell.modelData.full && !cell.modelData.today ? 1.4 * root.s : 0
                            border.color: Theme.primary
                        }

                        Text {
                            anchors.centerIn: parent
                            text: cell.modelData.day
                            color: cell.modelData.today ? Theme.onPrimary
                                : cell.modelData.inMonth ? Theme.onSurface : "transparent"
                            font.family: Theme.font
                            font.pixelSize: 9 * root.s
                            font.weight: cell.modelData.today || cell.modelData.full
                                ? Font.Bold : Font.Medium
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}

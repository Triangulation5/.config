import QtQuick
import qs.services
import qs.components.icons

Item {
    id: root

    readonly property real s: Math.max(0.78, Math.min(1.7, Math.min(width / 260, height / 166)))
    readonly property var hours: Weather.hourly.slice(0, 7)
    readonly property int low: {
        if (hours.length === 0)
            return Weather.tempNow - 3;
        var value = hours[0].temp;
        for (var i = 1; i < hours.length; i++)
            value = Math.min(value, hours[i].temp);
        return value;
    }
    readonly property int high: {
        if (hours.length === 0)
            return Weather.tempNow + 3;
        var value = hours[0].temp;
        for (var i = 1; i < hours.length; i++)
            value = Math.max(value, hours[i].temp);
        return value;
    }
    readonly property int range: Math.max(4, high - low)

    function hourLabel(entry, index) {
        if (index === 0)
            return "Now";
        var hour = parseInt(entry.hour, 10);
        if (Flags.time12h) {
            var suffix = hour >= 12 ? "P" : "A";
            var shortHour = hour % 12;
            if (shortHour === 0)
                shortHour = 12;
            return shortHour + suffix;
        }
        return entry.hour;
    }

    Rectangle {
        anchors.fill: parent
        radius: 22 * root.s
        color: Theme.surfaceContainerLowest
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.25)
    }

    Row {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 15 * root.s
        anchors.rightMargin: 15 * root.s
        anchors.topMargin: 14 * root.s
        spacing: 6 * root.s

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: width
            name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
            color: Theme.primary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.tempNow + "°" : "--°"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 14 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.labelFor(Weather.codeNow) : "Weather"
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            elide: Text.ElideRight
        }

        Item { width: Math.max(0, header.width - 157 * root.s); height: 1 }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 12 * root.s
            height: width
            name: "droplet"
            color: Theme.primary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.humidity + "%" : ""
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.features: ({ "tnum": 1 })
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 15 * root.s
        anchors.rightMargin: 15 * root.s
        anchors.topMargin: 10 * root.s
        anchors.bottomMargin: 11 * root.s

        Repeater {
            model: root.hours.length > 0 ? root.hours : [
                { hour: "00", temp: root.low },
                { hour: "03", temp: root.low + 1 },
                { hour: "06", temp: root.low + 2 },
                { hour: "09", temp: root.high },
                { hour: "12", temp: root.high - 1 },
                { hour: "15", temp: root.low + 1 },
                { hour: "18", temp: root.low + 2 }
            ]

            delegate: Item {
                id: hourColumn
                required property var modelData
                required property int index

                width: parent ? parent.width / 7 : 0
                height: parent ? parent.height : 0

                readonly property real fraction: (hourColumn.modelData.temp - root.low) / root.range
                readonly property real barHeight: Math.max(22 * root.s,
                    (height - 24 * root.s) * (0.32 + fraction * 0.68))

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: labels.top
                    width: parent.width * 0.82
                    height: hourColumn.barHeight
                    radius: Math.min(width / 2, 5 * root.s)
                    color: index === 0 ? Theme.primary : Qt.alpha(Theme.primary, 0.8)
                }

                Text {
                    id: labels
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 13 * root.s
                    text: root.hourLabel(hourColumn.modelData, hourColumn.index)
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.rightMargin: 15 * root.s
        anchors.topMargin: 2 * root.s
        text: root.high + "° / " + root.low + "°"
        color: Theme.onSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 8 * root.s
        font.features: ({ "tnum": 1 })
    }
}

import QtQuick
import qs.services
import qs.components.icons

Item {
    id: root

    readonly property real s: Math.max(0.78, Math.min(1.7, Math.min(width / 260, height / 166)))
    readonly property int slotCount: Math.max(2, Math.min(12, Math.floor((width - 30 * s) / (30 * s))))
    readonly property var hours: Weather.hourly.slice(0, slotCount)
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
    readonly property int peakRain: {
        var value = 0;
        for (var i = 0; i < hours.length; i++)
            value = Math.max(value, Number(hours[i].rain) || 0);
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
        border.color: Qt.alpha(Theme.outlineVariant, 0.3)
    }

    Row {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 15 * root.s
        anchors.rightMargin: 15 * root.s
        anchors.topMargin: 12 * root.s
        spacing: 6 * root.s

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 18 * root.s
            height: width
            name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
            color: Theme.primary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.tempNow + "°" : "--°"
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 15 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(30 * root.s, header.width - 170 * root.s)
            text: (Weather.ready ? Weather.labelFor(Weather.codeNow) : "Weather")
                + (Weather.city.length > 0 ? " · " + Weather.city : "")
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 12 * root.s
            height: width
            name: "droplet"
            color: Theme.primary
            visible: root.peakRain > 0
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.peakRain > 0 ? root.peakRain + "%" : ""
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.high + "° / " + root.low + "°"
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.features: ({ "tnum": 1 })
        }
    }

    Canvas {
        id: chart
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: labels.top
        anchors.leftMargin: 12 * root.s
        anchors.rightMargin: 12 * root.s
        anchors.topMargin: 5 * root.s
        anchors.bottomMargin: 3 * root.s
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (root.hours.length < 2 || width <= 0 || height <= 0)
                return;

            var plotBottom = height - 2;
            var plotTop = 5;
            var span = root.range;
            var unit = width / (root.hours.length - 1);
            function yAt(temp) {
                return plotBottom - ((temp - root.low) / span) * (plotBottom - plotTop);
            }

            ctx.strokeStyle = Qt.alpha(Theme.outlineVariant, 0.4);
            ctx.lineWidth = 1;
            for (var g = 1; g <= 2; g++) {
                var gy = plotTop + (plotBottom - plotTop) * g / 3;
                ctx.beginPath();
                ctx.moveTo(0, Math.round(gy) + 0.5);
                ctx.lineTo(width, Math.round(gy) + 0.5);
                ctx.stroke();
            }

            var gradient = ctx.createLinearGradient(0, plotTop, 0, plotBottom);
            gradient.addColorStop(0, Qt.alpha(Theme.primary, 0.78));
            gradient.addColorStop(1, Qt.alpha(Theme.primary, 0.16));
            ctx.fillStyle = gradient;
            for (var i = 0; i < root.hours.length - 1; i++) {
                var left = i * unit + 1;
                var right = (i + 1) * unit - 1;
                ctx.beginPath();
                ctx.moveTo(left, yAt(root.hours[i].temp));
                ctx.lineTo(right, yAt(root.hours[i + 1].temp));
                ctx.lineTo(right, plotBottom);
                ctx.lineTo(left, plotBottom);
                ctx.closePath();
                ctx.fill();
            }

            ctx.beginPath();
            for (var j = 0; j < root.hours.length; j++) {
                var x = j * unit;
                if (j === 0)
                    ctx.moveTo(x, yAt(root.hours[j].temp));
                else
                    ctx.lineTo(x, yAt(root.hours[j].temp));
            }
            ctx.strokeStyle = Theme.primary;
            ctx.lineWidth = 2 * root.s;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onHoursChanged() { chart.requestPaint(); }
            function onLowChanged() { chart.requestPaint(); }
            function onHighChanged() { chart.requestPaint(); }
        }
    }

    Row {
        id: labels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10 * root.s
        anchors.rightMargin: 10 * root.s
        anchors.bottomMargin: 8 * root.s
        height: 13 * root.s

        Repeater {
            model: root.hours
            delegate: Text {
                required property var modelData
                required property int index
                width: labels.width / Math.max(1, root.hours.length)
                height: labels.height
                text: root.hourLabel(modelData, index)
                color: index === 0 ? Theme.primary : Theme.onSurfaceVariant
                font.family: Theme.font
                font.pixelSize: 8 * root.s
                font.weight: index === 0 ? Font.DemiBold : Font.Normal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}

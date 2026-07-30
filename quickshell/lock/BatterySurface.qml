pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Item {
    id: battery

    property real s: 1.1

    readonly property string icon: {
        if (Battery.full)
            return "battery-full";

        if (Battery.charging)
            return "battery-charging";

        if (Battery.pct >= 90)
            return "battery-full";

        if (Battery.pct >= 70)
            return "battery-high";

        if (Battery.pct >= 50)
            return "battery-medium";

        if (Battery.pct >= 30)
            return "battery-low";

        if (Battery.low)
            return "battery-warning";

        return "battery-empty";
    }

    width: batteryRow.width
    height: batteryRow.height

    visible: Battery.dev !== null

    Row {
        id: batteryRow

        spacing: 7 * battery.s

        GlyphIcon {
            name: battery.icon

            color: Theme.cream

            width: 17 * battery.s
            height: 17 * battery.s

            stroke: 1.8
            opacity: 0.9

            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: Battery.pct + "%"

            color: Theme.cream
            opacity: 0.85

            font.family: Theme.font
            font.pixelSize: 12 * battery.s
            font.weight: 600
            font.letterSpacing: 1.3 * battery.s

            anchors.verticalCenter: parent.verticalCenter
        }
    }
}

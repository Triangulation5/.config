import QtQuick
import qs.services

/**
 * CPU load, from the bar's shared sampler (services/BarStatus.qml). Tabular
 * figures so the block does not jitter as the number changes width.
 *
 * The number carries its own weight: cream while the machine is idling along,
 * the accent once it is worth noticing, the warning tone once it is pinned.
 */
Text {
    id: root

    property real s: 1.1

    text: "CPU " + BarStatus.cpu + "%"
    color: BarStyle.level(BarStatus.cpu / 100, 0.55, 0.85)
    font.family: Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

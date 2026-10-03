import QtQuick
import qs.services

/**
 * CPU load, from the bar's shared sampler (services/BarStatus.qml). Tabular
 * figures so the block does not jitter as the number changes width.
 *
 * The strip's reading colour, like every other readout on it: the status group
 * is one voice, so a busy cpu is not a differently coloured cpu — the number
 * says what the load is.
 */
Text {
    id: root

    property real s: 1.1

    text: "CPU " + BarStatus.cpu + "%"
    color: BarStyle.fg
    font.family: Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

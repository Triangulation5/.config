import QtQuick
import qs.services

/**
 * Memory used, from the bar's shared sampler (services/BarStatus.qml). Tabular
 * figures so the block does not jitter as the number changes width.
 *
 * The strip's reading colour, like every other readout on it, and for the same
 * reason as the CPU block: one voice across the status group.
 */
Text {
    id: root

    property real s: 1.1

    text: "MEM " + BarStatus.memPct + "%"
    color: BarStyle.fg
    font.family: Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

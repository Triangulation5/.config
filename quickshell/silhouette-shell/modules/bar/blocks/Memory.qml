import QtQuick
import qs.services

/**
 * Memory used, from the bar's shared sampler (services/BarStatus.qml). Tabular
 * figures so the block does not jitter as the number changes width.
 *
 * Same ladder as the CPU block, with the rungs set where memory actually gets
 * tight rather than where the percentage looks round.
 */
Text {
    id: root

    property real s: 1.1

    text: "MEM " + BarStatus.memPct + "%"
    color: BarStyle.level(BarStatus.memPct / 100, 0.70, 0.90)
    font.family: Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

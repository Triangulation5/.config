import QtQuick
import qs.services as Services

/**
 * Laptop battery: charge, with the state read as colour rather than a glyph so
 * the block stays a single Text. Hidden entirely on a machine with no battery.
 *
 * `Battery.present` gates it, `Battery.low` is the same warning threshold the
 * shell's own battery surfaces use, and being on the AC line (not necessarily
 * charging — a pack held at a threshold is still plugged in) tints it warm.
 *
 * The service is imported aliased because this component is itself named
 * `Battery`: an unqualified `Battery` in this file would be ambiguous between
 * the type being defined and the singleton it reads.
 */
Text {
    id: root

    property real s: 1.1

    visible: Services.Battery.present

    text: "BAT " + Services.Battery.pct + "%"
    color: Services.Battery.low ? Services.BarStyle.warn
        : (Services.Battery.plugged ? Services.BarStyle.accent : Services.BarStyle.fg)
    font.family: Services.Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

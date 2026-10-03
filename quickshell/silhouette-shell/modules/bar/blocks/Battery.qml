import QtQuick
import qs.services as Services

/**
 * Laptop battery: charge, kept as a single Text. Hidden entirely on a machine
 * with no battery.
 *
 * The strip's reading colour, like every other readout on it. It used to tint
 * itself warm on the AC line and red at `Battery.low`, which made this the one
 * block in the status group speaking in a second voice about a thing the digits
 * already say — the pill's own battery surfaces still carry that signal, so
 * nothing is lost by the strip staying one colour.
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
    color: Services.BarStyle.fg
    font.family: Services.Theme.font
    font.pixelSize: 12 * s
    font.features: ({ "tnum": 1 })
}

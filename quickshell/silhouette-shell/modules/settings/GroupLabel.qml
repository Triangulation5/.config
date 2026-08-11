import QtQuick
import qs.services

/**
 * Section heading for a settings tab: an uppercase faint label with letter
 * spacing. `s` carries the surface scale; leftPadding stays a plain Text
 * property so a tab that needs an indent (e.g. Animation) can pass its own.
 */
Text {
    id: glabel

    property real s: 1

    topPadding: 16 * glabel.s
    bottomPadding: 6 * glabel.s
    color: Theme.faint
    font.family: Theme.font
    font.pixelSize: 8.5 * glabel.s
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.2 * glabel.s
}

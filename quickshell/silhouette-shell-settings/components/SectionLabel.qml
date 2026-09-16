import QtQuick
import qs.config

/**
 * Faint heading above a card, and the rail's section heading — the shell's
 * `GroupLabel` without the surface scale the pill needs. It stays a plain Text
 * so a caller can indent or re-case it without a wrapper.
 */
Text {
    color: Theme.textSecondary
    font.pixelSize: Theme.fontSizeSection
    leftPadding: 4
}

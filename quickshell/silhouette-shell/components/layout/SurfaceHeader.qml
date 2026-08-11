pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Shared pill-surface header: a kanji glyph paired with an ALL-CAPS label on
 * the left and an optional status badge on the right. Used by Battery, System,
 * Timer, Localsend, Mixer, Recorder and SpaceApps so every surface reads the
 * same way.
 */
Item {
    id: root

    property real s: 1.1
    property string kanji: ""
    property string label: ""
    property string badge: ""
    property color badgeColor: Theme.dim

    width: parent ? parent.width : 0
    height: 22 * s

    /**
     * Ame soul anchor mapped into the caller's coordinate space.
     * When glyphs are on the ember rests above the kanji; otherwise
     * it sits beside the label. Caller should pass its own root item.
     */
    function soulPoint(caller) {
        if (Flags.showGlyphs && root.kanji.length > 0)
            return kanjiText.mapToItem(caller, kanjiText.width / 2, -3 * root.s);
        return labelText.mapToItem(caller, -8 * root.s, labelText.height / 2);
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * root.s

        Text {
            id: kanjiText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.kanji.length > 0 && Flags.showGlyphs
            text: root.kanji
            color: Theme.cream
            font.family: Theme.fontJp
            font.weight: Font.Medium
            font.pixelSize: 16 * root.s
        }
        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * root.s
        }
    }

    Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.badge.length > 0
        text: root.badge
        color: root.badgeColor
        font.family: Theme.font
        font.pixelSize: 9.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.1 * root.s
    }
}

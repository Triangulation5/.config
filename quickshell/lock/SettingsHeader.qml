pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

Item {
    id: head

    property real s: 1
    property string glyph: ""
    property string title: "Settings"

    width: parent ? parent.width : 0
    height: 24 * s


    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        spacing: 8 * s


        Text {
            anchors.verticalCenter: parent.verticalCenter

            visible: Flags.showGlyphs && head.glyph.length > 0

            text: head.glyph

            color: Theme.cream

            font.family: Theme.fontJp
            font.pixelSize: 15 * s
            font.weight: Font.Medium
        }


        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter

            visible: !head.glyph.length

            width: 16 * s
            height: 16 * s

            name: "cog"

            color: Theme.iconDim
            stroke: 1.7
        }


        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: head.title

            color: Theme.subtle

            font.family: Theme.font

            font.pixelSize: 10 * s
            font.weight: Font.DemiBold

            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.5 * s
        }
    }
}

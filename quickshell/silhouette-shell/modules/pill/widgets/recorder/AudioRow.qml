pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.animation
import qs.components.icons

/**
 * Compact audio row: a glyph, a label, a flat-tick fader and a percent
 * readout. The fader dims and stops accepting input when its audio is off.
 */
Item {
    id: arow

    property real s: 1.1
    property string glyph: ""
    property string name: ""
    property bool on: false
    property int faderIndex: -1
    property real level: 0.5

    /** Index of the currently focused fader (-1 = none), driven by the host. */
    property int faderFocus: -1

    signal toggled()
    signal faderMoved(real v)
    /** Emitted when the host should step the focused fader by deltaPct. */
    signal stepFocused(int deltaPct)

    width: parent ? parent.width : 0
    height: 27 * s

    GlyphIcon {
        id: rowGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * s
        height: 16 * s
        name: arow.glyph
        color: arow.on ? Theme.vermLit : Theme.iconDim
        stroke: 1.7
    }

    Text {
        id: rowName
        anchors.left: rowGlyph.right
        anchors.leftMargin: 11 * s
        anchors.verticalCenter: parent.verticalCenter
        width: 76 * s
        text: arow.name
        color: arow.on ? Theme.cream : Theme.subtle
        font.family: Theme.font
        font.pixelSize: 11.5 * s
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    HFader {
        id: fader
        anchors.left: rowName.right
        anchors.leftMargin: 4 * s
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        s: arow.s
        on: arow.on
        value: arow.level
        focused: arow.on && arow.faderFocus === arow.faderIndex
        onMoved: (v) => arow.faderMoved(v)
        onFocusRequested: arow.faderFocus = arow.faderIndex

        HoverHandler {
            onHoveredChanged: if (hovered && arow.on) arow.faderFocus = arow.faderIndex
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            enabled: arow.on
            property real acc: 0
            onWheel: (event) => {
                arow.faderFocus = arow.faderIndex;
                acc += event.angleDelta.y / 120;
                const notches = Math.trunc(acc);
                if (notches !== 0) {
                    arow.stepFocused(notches * 5);
                    acc -= notches;
                }
                event.accepted = true;
            }
        }
    }
}

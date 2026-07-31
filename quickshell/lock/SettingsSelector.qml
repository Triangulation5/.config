pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Option picker component for choosing from a discrete list of options.
 * Cycles through options on click.
 */
Rectangle {
    id: sel

    property real s: 1.1
    property var options: []
    property var value: ""
    signal selected(var value)

    width: optText.implicitWidth + 24 * sel.s
    height: optText.implicitHeight + 8 * sel.s
    radius: 7 * sel.s

    color: selMouse.containsMouse ? Qt.alpha(Theme.cream, 0.16) : Theme.fieldBg
    border.width: 1
    border.color: selMouse.containsMouse ? Theme.cream : Theme.fieldBorder

    scale: selMouse.containsPress ? 0.94 : (selMouse.containsMouse ? 1.03 : 1.0)

    Behavior on color { ColorAnimation { duration: 180 } }
    Behavior on border.color { ColorAnimation { duration: 180 } }
    Behavior on scale {
        SpringAnimation {
            spring: 4.8
            damping: 0.36
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 6 * sel.s

        Text {
            id: optText
            text: sel.value !== undefined && sel.value !== null ? sel.value.toString() : ""
            color: selMouse.containsMouse ? Theme.bright : Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * sel.s
            font.weight: Font.Medium
            font.letterSpacing: 0.4 * sel.s

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 10 * sel.s
            height: 10 * sel.s
            name: "chevron-right"
            color: selMouse.containsMouse ? Theme.cream : Theme.iconDim
            stroke: 2.0

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    MouseArea {
        id: selMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (!sel.options || sel.options.length === 0)
                return;
            var idx = sel.options.indexOf(sel.value);
            var nextIdx = (idx + 1) % sel.options.length;
            var nextVal = sel.options[nextIdx];
            sel.value = nextVal;
            sel.selected(nextVal);
        }
    }
}

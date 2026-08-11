pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Single stat row: faint ALL-CAPS label on the left, cream value on the right,
 * with an optional warm (flame) tint. Baseline-aligned so multi-line surfaces
 * keep their labels optically level.
 */
Item {
    id: root

    property real s: 1.1
    property string label: ""
    property string value: ""
    property bool warm: false

    width: parent ? parent.width : 0
    height: vText.implicitHeight

    Text {
        anchors.left: parent.left
        anchors.baseline: vText.baseline
        text: root.label
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: Font.Medium
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8 * root.s
    }

    Text {
        id: vText
        anchors.right: parent.right
        text: root.value
        color: root.warm ? Theme.flameGlow : Theme.cream
        font.family: Theme.font
        font.pixelSize: 12.5 * root.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
}

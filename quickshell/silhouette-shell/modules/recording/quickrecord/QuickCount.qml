pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Standalone pre-roll countdown toast. Shown at the pill top on the focused
 * monitor when the central countdown runs and the recorder surface is closed
 * (mode "quickCount"): a big flame-glow numeral over a small "GET READY" label.
 * Tapping cancels. The surface's own in-bar countdown covers the surface case.
 */
Item {
    id: root

    property real s: 1.1

    /** True while the quick-count mode owns the pill. */
    property bool active: false

    /** How settled the pill is into its target geometry; drives the fade-in. */
    property real morph: 0

    enabled: root.active
    opacity: root.active ? Math.pow(root.morph, 1.3) : 0
    visible: opacity > 0.01
    Behavior on opacity {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Column {
        anchors.centerIn: parent
        spacing: 1 * root.s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ScreenRec.countdown
            color: Theme.flameGlow
            font.family: Theme.font
            font.pixelSize: 28 * root.s
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "GET READY"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * root.s
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: ScreenRec.cancel()
    }
}

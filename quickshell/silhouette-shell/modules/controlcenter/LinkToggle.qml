import QtQuick
import qs.services

/**
 * Toggle switch: tile bg off, terracotta fill on, cream knob slides on the
 * fast motion token. Shared by the link surface and its WLAN/Bluetooth
 * drill-ins.
 *
 * Everything a flip changes is animated: the fill, the hairline and the knob.
 * The fill used to snap between tile bg and terracotta while the knob was still
 * travelling, which read as the switch flickering on and then catching up — the
 * two halves of one gesture on two different clocks. The border keeps its width
 * on both states (only its colour fades out under the fill): dropping it to 0
 * while on moved the inner edge by a pixel, which is visible at this size.
 */
Rectangle {
    id: toggle

    property real s: 1.1
    property bool on: false
    signal toggled()

    /** Knob inset, the same at both ends of its travel. */
    readonly property real inset: 3 * s

    width: (Theme.material ? 34 : 28) * s
    height: (Theme.material ? 20 : 16) * s
    radius: 999
    color: Theme.material
        ? (on ? Theme.primary : Theme.surfaceContainerHighest)
        : (on ? Theme.verm : Theme.tileBg)
    border.width: Theme.material ? 0 : 1
    border.color: on ? "transparent" : Theme.border

    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: (Theme.material ? 14 : 10) * toggle.s
        height: (Theme.material ? 14 : 10) * toggle.s
        radius: width / 2
        color: Theme.material
            ? (toggle.on ? Theme.onPrimary : Theme.onSurfaceVariant)
            : Theme.cream
        x: toggle.on ? toggle.width - width - toggle.inset : toggle.inset
        Behavior on x {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}

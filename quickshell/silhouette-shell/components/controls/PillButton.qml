pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Small pill button for the link drill-ins' confirm rows (and any other
 * compact action): `primary` is a ghost fill that lights tileBg/vermDim on
 * hover or keyboard focus, `danger` is a verm-tinted Forget-style button.
 * `focused` drives the keyboard focus ring, `lit` forces the primary border
 * highlight (the wifi reveal button's shown state). Emits `clicked`; the
 * caller positions it (anchors inside a Row) and owns the action.
 */
Rectangle {
    id: btn

    property real s: 1.1
    property string text: ""
    property string kind: "primary" // "primary" | "danger"
    property bool focused: false
    property bool lit: false

    signal clicked()

    readonly property bool hot: btnArea.containsMouse || btn.focused

    width: label.implicitWidth + 20 * btn.s
    height: 22 * btn.s
    radius: 7 * btn.s
    color: btn.kind === "danger"
        ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, btn.hot ? 0.2 : 0.12)
        : (btn.hot ? Theme.tileBg : "transparent")
    border.width: 1
    border.color: btn.kind === "danger"
        ? Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.45)
        : ((btn.hot || btn.lit) ? Theme.vermDim : Theme.border)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.kind === "danger" ? Theme.vermLit : Theme.cream
        font.family: Theme.font
        font.pixelSize: 10 * btn.s
        font.weight: Font.DemiBold
        font.letterSpacing: 0.3 * btn.s
    }

    MouseArea {
        id: btnArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}

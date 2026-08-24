import QtQuick
import QtQuick.Effects
import qs.services
import qs.components.layout

/**
 * Washi hint bubble for pill controls. Anchored to its parent control and
 * centred on it; `placement` decides whether the bubble floats above (pointer
 * down) or below (pointer up) so chips near the pill edge never clip off-screen.
 * The host sets `show` from the control's own HoverHandler; the bubble arms
 * after a hover delay, fades in slowly and out fast.
 *
 * Non-interactive by design: no MouseArea or HoverHandler lives here, so it
 * never steals pointer events from the controls or the mixer's hover tracker.
 * It is `visible: false` whenever fully faded, for the same reason.
 */
Item {
    id: root

    property real s: 1.1
    property string title: ""
    property string desc: ""
    property bool show: false
    property string placement: "above"

    readonly property bool below: placement === "below"
    /** One em-unit: the title's font size, so every dimension scales with the text. */
    readonly property real em: titleText.font.pixelSize
    readonly property real pointerH: 0.5 * em
    readonly property real gap: 0.5 * em

    property bool armed: false

    width: bubble.width
    height: bubble.height + pointerH
    z: 20

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: below ? undefined : parent.top
    anchors.bottomMargin: below ? 0 : gap
    anchors.top: below ? parent.bottom : undefined
    anchors.topMargin: below ? gap : 0

    visible: armed || opacity > 0.01
    opacity: armed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.armed ? Motion.standard : Motion.fast } }

    Timer {
        id: delay
        interval: 470
        onTriggered: root.armed = true
    }
    onShowChanged: {
        if (show) {
            delay.restart();
        } else {
            delay.stop();
            armed = false;
        }
    }

    CardFill {
        id: bubble
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.below ? undefined : parent.top
        anchors.bottom: root.below ? parent.bottom : undefined
        width: Math.max(titleText.implicitWidth, descText.implicitWidth) + 2.3 * root.em
        height: column.implicitHeight + 1.5 * root.em
        radius: 1.15 * root.em
        border.width: 1
        border.color: Theme.frameBorder

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.45
            shadowVerticalOffset: 0.3 * root.em
        }
    }

    Column {
        id: column
        anchors.centerIn: bubble
        spacing: 0.3 * root.em

        Text {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.title
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
        }
        Text {
            id: descText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.desc.length > 0
            text: root.desc
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
        }
    }

    Canvas {
        width: 0.95 * root.em
        height: root.pointerH
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.below ? parent.top : undefined
        anchors.bottom: root.below ? undefined : parent.bottom
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Theme.cardBot;
            ctx.beginPath();
            if (root.below) {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.lineTo(width / 2, 0);
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
            }
            ctx.closePath();
            ctx.fill();
        }
    }
}

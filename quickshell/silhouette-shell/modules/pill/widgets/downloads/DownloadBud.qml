pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.animation

/**
 * Compact Firefox download chip for the hover face: a progress ring with the
 * percent inside, the file name scrolling beneath, and a live size/speed line.
 * Reads [[Downloads]] (Firefox's downloads.json); a pure indicator — Firefox
 * offers no way to pause or cancel from outside, so the chip just watches.
 */
Item {
    id: bud

    property real s: 1.1

    implicitWidth: 180 * s
    implicitHeight: 54 * s

    Rectangle {
        anchors.fill: parent
        radius: 16 * s
        color: Qt.alpha(Theme.cardTop, 0.6)
        border.width: 1
        border.color: Theme.hair
    }

    /** Progress ring: hairline track, flame arc with round caps, redraw on every state change. */
    Canvas {
        id: ring
        anchors.left: parent.left
        anchors.leftMargin: 11 * s
        anchors.verticalCenter: parent.verticalCenter
        width: 32 * s
        height: 32 * s

        property real p: Downloads.progress
        onPChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var cx = width / 2;
            var cy = height / 2;
            var r = Math.min(width, height) / 2 - 3 * bud.s;
            ctx.lineWidth = 3 * bud.s;
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.14);
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();
            if (ring.p > 0) {
                ctx.strokeStyle = Theme.flameGlow;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + ring.p * Math.PI * 2);
                ctx.stroke();
            }
        }
    }

    Text {
        anchors.centerIn: ring
        text: Downloads.pctText.length > 0 ? Downloads.pctText : "…"
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 9.5 * s
        font.weight: Font.DemiBold
    }

    Column {
        anchors.left: ring.right
        anchors.leftMargin: 9 * s
        anchors.right: parent.right
        anchors.rightMargin: 12 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * s

        Marquee {
            width: parent.width
            text: Downloads.fileName
            color: Theme.cream
            pixelSize: 12.5 * s
            weight: Font.DemiBold
            active: Downloads.active
        }

        Text {
            text: Downloads.bytesTotal > 0
                ? (Downloads.speedText + " · " + Downloads.sizeText)
                : Downloads.speedText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * s
            font.weight: Font.Medium
        }
    }
}
pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.animation
import qs.components.icons
import qs.modules.pill.widgets.osd

/**
 * Download OSD face: the iPhone-style flash the pill morphs open to when a
 * Firefox download starts. A flame progress ring (percent inside, the download
 * glyph while the total size is unknown) with the file name scrolling beside
 * it and a live speed/size line. Reads [[Downloads]] directly; the face only
 * exists while the download flash kind is active, so no extra props to wire.
 */
OsdFace {
    id: face

    /** Progress ring: hairline track, flame arc with round caps, redraw on every state change. */
    Canvas {
        id: ring
        anchors.left: parent.left
        anchors.leftMargin: 16 * face.s
        anchors.verticalCenter: parent.verticalCenter
        width: 36 * face.s
        height: 36 * face.s

        property real p: Downloads.progress
        onPChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var cx = width / 2;
            var cy = height / 2;
            var r = Math.min(width, height) / 2 - 3 * face.s;
            ctx.lineWidth = 3 * face.s;
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
        font.pixelSize: 10 * face.s
        font.weight: Font.DemiBold
    }

    Column {
        anchors.left: ring.right
        anchors.leftMargin: 13 * face.s
        anchors.right: parent.right
        anchors.rightMargin: 16 * face.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * face.s

        Marquee {
            width: parent.width
            text: Downloads.fileName
            color: Theme.cream
            pixelSize: 12.5 * face.s
            weight: Font.DemiBold
            active: face.active
        }

        Text {
            text: Downloads.bytesTotal > 0
                ? (Downloads.speedText + " · " + Downloads.sizeText)
                : Downloads.speedText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * face.s
            font.weight: Font.Medium
        }
    }
}

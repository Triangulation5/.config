import QtQuick

Item {
    id: root

    enum CornerEnum {
        TopLeft,
        TopRight,
        BottomLeft,
        BottomRight
    }

    property int corner: RoundCorner.CornerEnum.TopLeft
    property real size: 40
    property color color: "white"

    implicitWidth: size
    implicitHeight: size

    Canvas {
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            const r = root.size

            ctx.clearRect(0, 0, width, height)
            ctx.beginPath()

            switch (root.corner) {

            case RoundCorner.CornerEnum.TopLeft:
                ctx.arc(r, r, r, Math.PI, 1.5 * Math.PI)
                ctx.lineTo(0, 0)
                break

            case RoundCorner.CornerEnum.TopRight:
                ctx.arc(0, r, r, 1.5 * Math.PI, 2 * Math.PI)
                ctx.lineTo(r, 0)
                break

            case RoundCorner.CornerEnum.BottomLeft:
                ctx.arc(r, 0, r, 0.5 * Math.PI, Math.PI)
                ctx.lineTo(0, r)
                break

            case RoundCorner.CornerEnum.BottomRight:
                ctx.arc(0, 0, r, 0, 0.5 * Math.PI)
                ctx.lineTo(r, r)
                break
            }

            ctx.closePath()
            ctx.fillStyle = root.color
            ctx.fill()
        }
    }
}

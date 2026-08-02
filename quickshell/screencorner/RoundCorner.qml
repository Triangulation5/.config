import QtQuick

Item {
    id: root

    enum CornerEnum {
        TopLeft,
        TopRight,
        BottomLeft,
        BottomRight
    }

    property var corner: RoundCorner.CornerEnum.TopLeft
    property int size: 25
    property color color: "#000000"

    // Animation controls from ScreenCorners.qml
    property bool evaporating: false
    property string edgeDirection: "topLeft"
    property int morphDuration: 700

    // Inner shadow controls
    property bool innerShadow: false
    property color innerShadowColor: Qt.rgba(0, 0, 0, 0.28)
    property real innerShadowSize: 8

    implicitWidth: size
    implicitHeight: size

    opacity: evaporating ? 0 : 1

    x: {
        if (!evaporating)
            return 0

        switch (edgeDirection) {
        case "topLeft":
        case "bottomLeft":
            return -size * 0.8

        case "topRight":
        case "bottomRight":
            return size * 0.8
        }

        return 0
    }

    y: {
        if (!evaporating)
            return 0

        switch (edgeDirection) {
        case "topLeft":
        case "topRight":
            return -size * 0.8

        case "bottomLeft":
        case "bottomRight":
            return size * 0.8
        }

        return 0
    }

    rotation: evaporating ? (
        edgeDirection === "topLeft" ? -8 :
        edgeDirection === "topRight" ? 8 :
        edgeDirection === "bottomLeft" ? -8 :
        8
    ) : 0

    transform: Scale {
        id: edgeMorph

        origin.x: {
            switch (root.edgeDirection) {
            case "topLeft":
            case "bottomLeft":
                return 0

            case "topRight":
            case "bottomRight":
                return root.width

            default:
                return root.width / 2
            }
        }

        origin.y: {
            switch (root.edgeDirection) {
            case "topLeft":
            case "topRight":
                return 0

            case "bottomLeft":
            case "bottomRight":
                return root.height

            default:
                return root.height / 2
            }
        }

        xScale: root.evaporating ? 0.05 : 1
        yScale: root.evaporating ? 0.05 : 1

        Behavior on xScale {
            NumberAnimation {
                duration: root.morphDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on yScale {
            NumberAnimation {
                duration: root.morphDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    Behavior on x {
        NumberAnimation {
            duration: root.morphDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on y {
        NumberAnimation {
            duration: root.morphDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on rotation {
        NumberAnimation {
            duration: root.morphDuration
            easing.type: Easing.OutCubic
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true

        Connections {
            target: root

            function onColorChanged() {
                canvas.requestPaint()
            }

            function onCornerChanged() {
                canvas.requestPaint()
            }

            function onSizeChanged() {
                canvas.requestPaint()
            }

            function onInnerShadowChanged() {
                canvas.requestPaint()
            }

            function onInnerShadowColorChanged() {
                canvas.requestPaint()
            }

            function onInnerShadowSizeChanged() {
                canvas.requestPaint()
            }

            function onVisibleChanged() {
                if (root.visible)
                    canvas.requestPaint()
            }
        }

        onPaint: {
            const ctx = getContext("2d")
            const r = root.size

            ctx.clearRect(0, 0, width, height)

            // Build the corner shape
            ctx.beginPath()

            switch (root.corner) {

            case RoundCorner.CornerEnum.TopLeft:
                ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2)
                ctx.lineTo(0, 0)
                break

            case RoundCorner.CornerEnum.TopRight:
                ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI)
                ctx.lineTo(r, 0)
                break

            case RoundCorner.CornerEnum.BottomLeft:
                ctx.arc(r, 0, r, Math.PI / 2, Math.PI)
                ctx.lineTo(0, r)
                break

            case RoundCorner.CornerEnum.BottomRight:
                ctx.arc(0, 0, r, 0, Math.PI / 2)
                ctx.lineTo(r, r)
                break
            }

            ctx.closePath()

            // Fill main corner
            ctx.fillStyle = root.color
            ctx.fill()

            // Inner bezel shadow only
            if (root.innerShadow) {
                ctx.save()
                ctx.clip()

                let gradient

                switch (root.edgeDirection) {

                case "topLeft":
                    gradient = ctx.createLinearGradient(
                        0, 0,
                        0, root.innerShadowSize
                    )
                    break

                case "topRight":
                    gradient = ctx.createLinearGradient(
                        0, 0,
                        0, root.innerShadowSize
                    )
                    break

                case "bottomLeft":
                    gradient = ctx.createLinearGradient(
                        0, height,
                        0, height - root.innerShadowSize
                    )
                    break

                case "bottomRight":
                    gradient = ctx.createLinearGradient(
                        0, height,
                        0, height - root.innerShadowSize
                    )
                    break
                }

                gradient.addColorStop(0, root.innerShadowColor)
                gradient.addColorStop(1, "transparent")

                ctx.fillStyle = gradient
                ctx.fillRect(0, 0, width, height)

                ctx.restore()
            }
        }
    }
}

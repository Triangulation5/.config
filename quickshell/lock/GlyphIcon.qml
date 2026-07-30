import QtQuick
import QtQuick.Shapes
import "Singletons"

/**
 * Self-contained vector glyph renderer.
 *
 * Uses inline SVG path data instead of icon themes/assets.
 * Glyphs are defined in a 24x24 coordinate space and scaled
 * into the item while keeping optical centering.
 */
Item {
    id: root

    property string name: ""
    property color color: Theme.iconDim
    property real stroke: 1.8

    readonly property real u: Math.min(width, height) / 24

    readonly property var glyphs: ({

        "battery-full": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4 M7 10h8v4H7z", fill: false },
        "battery-high": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4 M7 10h6v4H7z", fill: false },
        "battery-medium": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4 M7 10h4v4H7z", fill: false },
        "battery-low": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4 M7 10h2v4H7z", fill: false },
        "battery-empty": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4", fill: false },
        "battery-charging": { d: "M5 7h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M21 10v4 M12 8l-3 6h4l-1 4 5-7h-4z", fill: false },

        "lock": { d: "M6 10h12a2 2 0 0 1 2 2v7H4v-7a2 2 0 0 1 2-2z M8 10V7a4 4 0 0 1 8 0v3", fill: false },

        "clock": { d: "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M12 7v5l3 2", fill: false },

        "wifi": { d: "M4 9.5c5-4.5 11-4.5 16 0 M7 13c3-3 7-3 10 0 M10.5 16.5a2 2 0 1 0 3 0", fill: false },

        "user": { d: "M12 12a4 4 0 1 0 0-8a4 4 0 1 0 0 8z M4 21a8 8 0 0 1 16 0", fill: false }
    })


    readonly property var g:
        glyphs[name] !== undefined
        ? glyphs[name]
        : ({ d: "", fill: false })

    Shape {
        id: glyph

        width: 24
        height: 24

        scale: root.u
        transformOrigin: Item.TopLeft

        x: root.width / 2 - 12 * root.u
        y: root.height / 2 - 12 * root.u

        antialiasing: true
        preferredRendererType: Shape.CurveRenderer


        ShapePath {

            strokeColor: root.g.fill
                ? "transparent"
                : root.color

            fillColor: root.g.fill
                ? root.color
                : "transparent"

            strokeWidth: root.stroke

            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.g.d
            }
        }
    }
}

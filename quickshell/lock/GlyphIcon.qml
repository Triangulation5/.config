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
        "lock": { d: "M6 10h12a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H6a1.5 1.5 0 0 1-1.5-1.5v-6A1.5 1.5 0 0 1 6 10z M8.5 10V7a3.5 3.5 0 0 1 7 0v3", fill: false },
        "clock": { d: "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M12 7v5l3 2", fill: false },
        "wifi": { d: "M4 9.5c5-4.5 11-4.5 16 0 M7 13c3-3 7-3 10 0 M10.5 16.5a2 2 0 1 0 3 0", fill: false },
        "user": { d: "M12 12a4 4 0 1 0 0-8a4 4 0 1 0 0 8z M4 21a8 8 0 0 1 16 0", fill: false },
        "cog": { d: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z", fill: false }
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

        x: glyph.boundingRect.width > 0
            ? root.width / 2 - (glyph.boundingRect.x + glyph.boundingRect.width / 2) * root.u
            : (root.width - 24 * root.u) / 2

        y: glyph.boundingRect.height > 0
            ? root.height / 2 - (glyph.boundingRect.y + glyph.boundingRect.height / 2) * root.u
            : (root.height - 24 * root.u) / 2

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

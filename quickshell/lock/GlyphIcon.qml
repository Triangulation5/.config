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
        "cog": { d: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z", fill: false },
        "eye": { d: "M2 12s3.5-6 10-6s10 6 10 6s-3.5 6-10 6S2 12 2 12z M12 15a3 3 0 1 0 0-6a3 3 0 0 0 0 6z", fill: false },
        "eye-off": { d: "M3 3l18 18 M10.6 10.6a2 2 0 0 0 2.8 2.8 M9.9 5.2A10.5 10.5 0 0 1 12 5c6.5 0 10 7 10 7a18 18 0 0 1-4 4.8 M6.2 6.2C3.6 8 2 12 2 12s3.5 7 10 7a9.8 9.8 0 0 0 3.2-.5", fill: false },
        "waves": { d: "M2 8c2.5-3 5-3 7.5 0s5 3 7.5 0 M2 16c2.5-3 5-3 7.5 0s5 3 7.5 0", fill: false },
        "monitor": { d: "M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M8 21h8 M12 17v4", fill: false },
        "shutdown": { d: "M12 3v9 M7.8 6.3a8 8 0 1 0 8.4 0", fill: false },
        "chevron-left": { d: "M14 6l-6 6 6 6", fill: false },
        "chevron-right": { d: "M10 6l6 6-6 6", fill: false },
        "chevron-down": { d: "M6 10l6 6 6-6", fill: false },
        "chevron-up": { d: "M6 14l6-6 6 6", fill: false },
        "music": { d: "M9 18V5l12-2v13 M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0z M21 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z", fill: false },
        "play": { d: "M7 5l12 7-12 7z", fill: true },
        "pause": { d: "M8 5h3v14H8z M13 5h3v14h-3z", fill: true },
        "next": { d: "M6 5l9 7-9 7z M16 5h2v14h-2z", fill: true },
        "prev": { d: "M18 5l-9 7 9 7z M6 5h2v14H6z", fill: true },
        "return": { d: "M20 6v6a3 3 0 0 1-3 3H5 M9 11l-4 4 4 4", fill: false },
        "close": { d: "M6 6l12 12 M18 6l-12 12", fill: false }
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

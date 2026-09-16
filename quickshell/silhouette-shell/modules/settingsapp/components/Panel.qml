import QtQuick
import qs.modules.settingsapp.config

/**
 * The window's chrome, and nothing else: the flat surface every part of the
 * window sits on, and the open tween. The host declares the two halves of the
 * window as children (the default slot) exactly as the shell's `SettingsSurface`
 * lets a page declare its rows; this file never learns what they are.
 *
 * The surface is deliberately **square and opaque out to the window's edges**.
 * This is a compositor-managed window (a toplevel), so the corner radius and the
 * 1px edge belong to Hyprland, not here: `decoration.rounding` cuts the corners
 * (12 on this config) and `col.active_border` draws the border. Rounding the
 * surface as well cannot line up with that cut — a 24px arc against a 12px cut
 * leaves a crescent of *unpainted* surface inside the window, and the compositor
 * blurs the wallpaper behind an unpainted pixel. That was the smear that sat in
 * the top-right and bottom-right corners: the rail's own opaque rectangle covered
 * the same crescent on the left, which is why only the right side showed it.
 *
 * The tween moves the content rather than the surface for the same reason: a
 * surface caught mid-scale is smaller than the window, and the margin around it is
 * another unpainted region — a blur flash for the length of the animation.
 */
Item {
    id: panel

    property bool open: false

    /** The window's contents: the rail and the content area. */
    default property alias content: stage.data

    Rectangle {
        id: body
        // Floor the size: a fractional width would leave a hairline of background
        // showing along the right and bottom edges.
        width: Math.floor(panel.width)
        height: Math.floor(panel.height)
        color: Theme.window
    }

    Item {
        id: stage

        anchors.fill: parent
        scale: panel.open ? 1 : 0.98
        opacity: panel.open ? 1 : 0

        Behavior on scale { NumberAnimation { duration: Theme.animWindow; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animWindow } }
    }
}

import QtQuick
import Quickshell.Hyprland
import qs.services

/**
 * The focused window's title, or nothing when no window is focused. Read from
 * the compositor's live toplevel rather than polled with hyprctl: the
 * compositor already pushes title changes, so a string that changes often costs
 * nothing per second here.
 *
 * Elided when the strip is too narrow for it, so an enormous title cannot push
 * the status blocks off the bar. The cap itself is the layout's business, not
 * this block's — Bar.qml sets Layout.maximumWidth.
 */
Text {
    id: root

    property real s: 1.1

    readonly property string title: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""

    text: title
    visible: title.length > 0
    color: BarStyle.fg
    font.family: Theme.font
    font.pixelSize: 12.5 * s
    elide: Text.ElideRight
}

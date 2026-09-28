import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

/**
 * The focused window's title, or nothing when no window is focused.
 *
 * Read from the compositor's own foreign-toplevel list (the same source the
 * pill's fullscreen check uses) rather than from `Hyprland.activeToplevel`: that
 * model holds the last window it was told about, so a switch to a workspace with
 * nothing on it left the bar captioned with the window from the workspace you
 * left — the title of a window that is not on screen any more. The protocol
 * clears a toplevel's `activated` on the switch (checked against a live session,
 * see services/Fullscreen.qml), so a monitor whose active workspace holds no
 * focused window has no title to show, which is exactly right for dwm's bar.
 *
 * `Hyprland.activeToplevel` remains the fallback for a compositor without the
 * protocol: a list that stays empty while the session has windows is the signal
 * that it is not there.
 *
 * Elided when the strip is too narrow for it, so an enormous title cannot push
 * the status blocks off the bar. The cap itself is the layout's business, not
 * this block's — Bar.qml sets Layout.maximumWidth.
 */
Text {
    id: root

    property real s: 1.1
    property string screenName: ""

    /** True while the protocol is handing us a window list. */
    readonly property bool tmUsable: ToplevelManager.toplevels.values.length > 0

    readonly property string title: {
        if (root.tmUsable) {
            var list = ToplevelManager.toplevels.values;
            for (var i = 0; i < list.length; i++) {
                var t = list[i];
                if (!t || !t.activated || !t.screens)
                    continue;
                for (var j = 0; j < t.screens.length; j++)
                    if (t.screens[j] && t.screens[j].name === root.screenName)
                        return t.title || "";
            }
            return "";
        }
        return Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : "";
    }

    text: title
    visible: title.length > 0
    color: BarStyle.fg
    font.family: Theme.font
    font.pixelSize: 12.5 * s
    elide: Text.ElideRight
}

import QtQuick
import Quickshell.Hyprland
import qs.services

/**
 * dwm's layout symbol: the `[]=` between the tags and the title that says how the
 * active workspace on this monitor is tiled — `[]=` master, `[\]` dwindle (the
 * bspwm-style split), `|||` scrolling, `[M]` or `[3]` monocle. The mapping, and
 * why each layout gets the symbol it does, is BarLayout.glyph.
 *
 * Display only, like every block: no click handler, so it does not cycle the
 * layout the way dwm's does on a click. That stays on the keybind.
 *
 * It follows the active workspace of *this* monitor, found the way the tags find
 * it (the monitor model's activeWorkspace name), so on a two-output setup each
 * strip shows its own output's layout. The symbol is set in the shell's
 * monospaced face rather than the UI font: the symbols are all the same number of
 * characters, and a fixed advance keeps the strip from shifting when the layout
 * changes.
 *
 * Empty until the first read of the layouts lands, and then the block hides
 * instead of leaving a blank tag-sized gap.
 */
Text {
    id: root

    property real s: 1.1
    property string screenName: ""

    readonly property string activeName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }

    readonly property string layoutName: BarLayout.layoutOf(activeName)

    text: BarLayout.glyph(layoutName, BarLayout.windowsOf(activeName))
    visible: text.length > 0
    color: BarStyle.accent
    font.family: Theme.fontJp
    font.pixelSize: 12 * s
    font.weight: Font.DemiBold
}

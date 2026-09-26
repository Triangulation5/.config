pragma Singleton

import QtQuick

/**
 * Keybinds: the shortcut reference — every `hl.bind(...)` in `binds.lua` as a
 * chord and a name, to glance at rather than to change. It is a `view` page
 * because its body is a list that comes from a file at runtime and none of it is
 * a setting: there is no row descriptor in this app for "read and display", and
 * there should not be — the rows here edit nothing, so the row editors, the
 * sources and Reset have nothing to do here.
 *
 * The read is `Binds`', which owns no writer; the one keybind this app has any
 * business writing (a special workspace's toggle) is the Workspaces page's, and
 * it writes to the same file through its own service.
 */
QtObject {
    readonly property string name: "Keybinds"
    /** An alternative-key mark, beside the Input page's keyboard: a shortcut, not the keyboard itself. */
    readonly property string icon: "\u2387"

    /** Search words: a view page has no row labels for the rail to find. */
    readonly property string keywords: "keybind keybinds keybinding keybindings shortcut shortcuts hotkey hotkeys cheat sheet cheatsheet binds binding keyboard keys volume brightness media window workspace launch"

    /** A component, resolved relative to this file. */
    readonly property var view: Qt.resolvedUrl("KeybindsView.qml")

    /** No data groups: the loaded view owns the whole body. */
    readonly property var groups: []
}

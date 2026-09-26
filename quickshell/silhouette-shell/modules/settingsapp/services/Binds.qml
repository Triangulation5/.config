pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.services
import "../utils/keybinds/cheatsheet.js" as Cheatsheet

/**
 * `binds.lua` as reference material: every `hl.bind(...)` it holds, parsed for
 * the Keybinds page. This service holds no writer, which is what makes the page
 * a cheat sheet rather than a second editor — and what keeps it from clobbering
 * the writes the Workspaces service makes to this same file for a space's
 * toggle pair (see Spaces). Two readers of one file cannot fight; two writers
 * can, which is the rule this app already keeps for the files it edits.
 *
 * The file is watched, so a bind added by hand or by the shell's own keybinds
 * surface lands here on its own. The list is replaced on every read, never
 * patched in place: a `var` property notifies on assignment, and mutating the
 * array would leave the page showing the binds it was opened with.
 */
Singleton {
    id: root

    readonly property string path: Paths.binds

    /** The file as last read, and the binds parsed out of it. */
    property string text: ""
    property var binds: []

    readonly property int count: root.binds.length

    FileView {
        id: file
        path: root.path
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.text = file.text();
            root.binds = Cheatsheet.parse(root.text);
        }
        onFileChanged: reload()
    }
}

pragma Singleton

import QtQuick

/**
 * Backups: the shell's own config — the tree in `~/.config/quickshell/silhouette-shell`
 * and the state it keeps beside the flags — as something you can snapshot, list,
 * put back and delete. The body is a `view` rather than data groups because there
 * is nothing here a row descriptor could hold: a list that grows, a status, and
 * two per-archive actions.
 */
QtObject {
    readonly property string name: "Backups"
    readonly property string icon: "\u2913"
    readonly property string caption: "Snapshot the shell's own config"

    /** Search words: a view page has no row labels for the rail to find. */
    readonly property string keywords: "backup backups restore snapshot save archive rollback recover copy state flags"

    /** A component, resolved relative to this file. */
    readonly property var view: Qt.resolvedUrl("BackupsView.qml")

    /** No data groups: the loaded view owns the whole body. */
    readonly property var groups: []
}

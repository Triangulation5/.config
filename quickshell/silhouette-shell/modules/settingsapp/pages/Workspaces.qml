pragma Singleton

import QtQuick

/**
 * Workspaces: the special workspaces — the ones a key drops you into over the
 * windows you were using. The rows cannot be written as data, because the list is
 * whatever the user created and each row carries its own create/remove/apps
 * state, so this page carries a `view` instead of `groups`.
 *
 * The set is read from two places (the shell's spaces.lua store and the binds
 * that actually toggle them); see the Spaces service for what each one is for and
 * why this config needs both.
 */
QtObject {
    readonly property string name: "Workspaces"
    readonly property string icon: "\u2B1A"

    /** Search words: the rows are runtime data, so there are no labels to find. */
    readonly property string keywords: "special scratchpad stash private minimized workspace space apps routing"

    /** A component, resolved relative to this file. */
    readonly property var view: Qt.resolvedUrl("WorkspacesView.qml")

    /** No data groups: the loaded view owns the whole body. */
    readonly property var groups: []
}

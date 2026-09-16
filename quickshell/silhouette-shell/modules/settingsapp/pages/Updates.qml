pragma Singleton

import QtQuick

/**
 * Updates: the distribution's packages, as the config's own updater reports them.
 * The body is a `view` rather than data groups because the rows are a status, a
 * pending list and the results of a run — nothing a row descriptor can hold.
 */
QtObject {
    readonly property string name: "Updates"
    readonly property string icon: "\u21BB"

    /** Search words: a view page has no row labels for the rail to find. */
    readonly property string caption: "Package upgrades for the machine"
    readonly property string keywords: "update upgrade package packages dnf system security reboot"

    /** A component, resolved relative to this file. */
    readonly property var view: Qt.resolvedUrl("UpdatesView.qml")

    /** No data groups: the loaded view owns the whole body. */
    readonly property var groups: []
}

pragma Singleton

import QtQuick

/**
 * Displays: one card per connected monitor, with the resolution, refresh rate,
 * scale and position that Hyprland reports as available. The rows cannot be
 * written as data — the options depend on the hardware — so this page carries a
 * `view` instead of `groups`, and the content area loads it.
 */
QtObject {
    readonly property string name: "Displays"
    readonly property string icon: "\u25A1"

    /**
     * Search words for this page. Its rows are built at runtime, so there are no
     * row labels for the rail to find — without these, searching for the
     * settings this page exists for would come up empty.
     */
    readonly property string keywords: "resolution refresh rate scale scaling monitor position output mode hz"

    /** A component, resolved relative to this file. */
    readonly property var view: Qt.resolvedUrl("DisplaysView.qml")

    /** No data groups: the loaded view owns the whole body. */
    readonly property var groups: []
}

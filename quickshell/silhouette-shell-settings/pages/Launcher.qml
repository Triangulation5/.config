pragma Singleton

import QtQuick

/**
 * Launcher: how the pill's menus are driven from the keyboard.
 */
QtObject {
    readonly property string name: "Launcher"
    readonly property string icon: "\u25A4"

    readonly property var groups: [
        { card: "Navigation", rows: [
            { key: "vimKeys", type: "toggle", label: "Vim keys",
              caption: "hjkl navigation instead of arrow keys in the pill menus", reset: true }
        ]}
    ]
}

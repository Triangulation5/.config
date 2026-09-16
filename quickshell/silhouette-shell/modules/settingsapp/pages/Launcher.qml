pragma Singleton

import QtQuick

/**
 * Launcher: how the pill's menus are driven from the keyboard.
 */
QtObject {
    readonly property string name: "Launcher"
    readonly property string icon: "\u25A4"
    readonly property string caption: "Keyboard navigation in the pill's menus"
    readonly property string keywords: "vim keys hjkl navigation launcher menus arrows keyboard"

    readonly property var groups: [
        { card: "Navigation", rows: [
            { key: "vimKeys", type: "toggle", label: "Vim keys",
              caption: "hjkl navigation instead of arrow keys in the pill menus", reset: true }
        ]}
    ]
}

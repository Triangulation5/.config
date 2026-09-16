import QtQuick
import qs.modules.settingsapp.config

/**
 * One output drawn as the piece of hardware it is: a desk panel gets a screen on
 * a neck and a base, a laptop's built-in panel gets a lid sitting on a deck.
 * The screen keeps the output's own proportions — `width / height`, the same
 * figure the compositor lays windows out in — so a 16:10 and a 32:9 do not come
 * out the same shape here, and a monitor reads in the map the way it looks on
 * the desk.
 *
 * The shape is a view and nothing else: it reads a live monitor object and never
 * writes. That is what lets one component be both the tile inside the arrangement
 * map and the portrait at the top of that monitor's card — the only difference
 * between the two is how much room it is given.
 *
 * `builtin` is decided from the output name because that is the one thing every
 * backend reports the same way: eDP/LVDS/DSI is the laptop's own panel, and
 * anything else is assumed to be a desk panel on a stand. A monitor with no
 * make/model still draws; the labels just say less.
 */
Item {
    id: root

    /** The live monitor, as `hyprctl` reports it. */
    property var mon: null

    /** Whether this is the laptop's own panel, which changes the stand. */
    readonly property bool builtin: root.mon !== null && /^(eDP|LVDS|DSI|DPI)/i.test(root.mon.name)

    /** The config declares this the main output: marked with a dot. */
    property bool main: false

    /** This output is the one the page is showing: accent fill and border. */
    property bool sel: false

    /** The pointer is on this output's tile. */
    property bool hovered: false

    /**
     * Draw the stand under the screen. The arrangement map turns it off for a
     * monitor that has another one directly beneath it, where a stand would be
     * painted over its neighbour's screen.
     */
    property bool stand: true

    /** Draw the name and mode inside the screen (off for tiles too small to hold them). */
    property bool labels: true

    /** Label size, so a tile can shrink its text with its box. */
    property real labelSize: 11

    /** The box the whole piece of hardware has to fit into. */
    property real maxWidth: 190
    property real maxHeight: 120

    readonly property real aspect: root.mon && root.mon.height > 0 ? root.mon.width / root.mon.height : 16 / 9
    /** Gap between screen and stand, and the stand's own height. */
    readonly property real gap: root.builtin ? 2 : 1
    readonly property real standH: root.builtin ? 5 : 10
    /**
     * What the stand takes below the screen. Zero without one, which is what
     * keeps the screen itself the size the caller asked for: the fit below
     * subtracts this, so a caller that passes its own rect as `maxHeight` gets a
     * screen exactly that size and a stand hanging past it — not a shrunken
     * screen. An arrangement map that let this shrink its tiles would draw gaps
     * between monitors that do not have any.
     */
    readonly property real chrome: root.stand ? root.gap + root.standH : 0
    readonly property real roomH: Math.max(12, root.maxHeight - root.chrome)
    // Fitted, never forced: the floors are there so a screen stays drawable, but
    // they are still clamped to the box, because a shape that ignored its caller's
    // rect would overlap its neighbour in the map.
    readonly property real screenW: Math.min(root.maxWidth, Math.max(16, root.roomH * root.aspect))
    readonly property real screenH: Math.min(root.roomH, Math.max(9, root.screenW / root.aspect))

    /** `1920×1080 60Hz`, with the scale appended when it is not 1. */
    readonly property string modeLine: {
        if (root.mon === null)
            return "";
        var line = root.mon.width + "\u00D7" + root.mon.height + "  " + root.mon.refresh + "Hz";
        if (Math.abs(root.mon.scale - 1) > 0.001)
            line += "  " + root.mon.scale + "\u00D7";
        return line;
    }

    implicitWidth: root.screenW
    implicitHeight: root.screenH + root.chrome

    Rectangle {
        id: screen

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.screenW
        height: root.screenH
        radius: Math.min(7, root.screenH / 5)
        color: root.sel ? Qt.alpha(Theme.accent, 0.10) : Theme.hover
        border.width: 1
        border.color: root.sel ? Qt.alpha(Theme.accent, 0.55)
            : (root.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Column {
            anchors.centerIn: parent
            width: Math.max(0, screen.width - 10)
            spacing: 1
            visible: root.labels

            Text {
                width: parent.width
                text: root.mon ? root.mon.name : ""
                color: root.sel ? Theme.accent : Theme.text
                font.pixelSize: root.labelSize
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                // A screen too short to hold two lines says the name alone rather
                // than clipping the mode in half.
                visible: screen.height > 46 && text.length > 0
                width: parent.width
                text: root.modeLine
                color: Theme.textSecondary
                font.pixelSize: Math.max(8, root.labelSize - 2)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        // A dot rather than a star glyph: the marker has to draw in whatever font
        // stack this config has installed.
        Rectangle {
            visible: root.main
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5
            width: 5
            height: 5
            radius: 2.5
            color: Theme.accent
        }
    }

    // Desk panel: a neck and a foot.
    Rectangle {
        visible: root.stand && !root.builtin
        anchors.top: screen.bottom
        anchors.topMargin: root.gap
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(5, Math.min(20, root.screenW * 0.11))
        height: 5
        color: Qt.rgba(1, 1, 1, 0.13)
    }

    Rectangle {
        visible: root.stand && !root.builtin
        anchors.top: screen.bottom
        anchors.topMargin: root.gap + 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.screenW, Math.max(22, Math.min(78, root.screenW * 0.40)))
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.09)
    }

    // Laptop: the lid's deck, with the opening notch in the middle.
    Rectangle {
        visible: root.stand && root.builtin
        anchors.top: screen.bottom
        anchors.topMargin: root.gap
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.screenW
        height: 5
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.13)

        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(8, root.screenW * 0.14)
            height: 2
            radius: 1
            color: Theme.window
        }
    }
}

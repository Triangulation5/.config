pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.modules.pill.surfaces
import qs.components.animation
import qs.components.icons

/**
 * Power surface: a row of hand-drawn session glyphs split by a hairline into a
 * safe group (lock, logout, sleep; fire on tap) and a destructive group
 * (restart, shutdown; press-and-hold). Holding a destructive tile ramps a
 * bottom-up heat fill, releasing early drains it, so a stray click can never
 * reboot the machine. Only the hovered, focused or held action shows its label.
 *
 * Arrow keys move a keyboard focus across the tiles; the focused tile lights and
 * docks the soul bead exactly like a hovered one. Enter fires a safe tile at
 * once; on a destructive tile a held Enter drives the same heat fill as a
 * pointer hold (release before it completes drains), so the keyboard path can
 * never reboot on a single keystroke either.
 *
 * The minimal bar swaps the hold for a double tap (`doubleTap`). A hold is the
 * right gesture when there is a pill to press into and a heat fill to watch
 * climb; the bar has neither, so a hold there is a 1.5s wait on a surface the
 * user summoned precisely because they wanted it now. Tapping a destructive tile
 * once arms it and says so, and a second tap inside `armWindow` fires it — the
 * same two-step guarantee, expressed as two taps rather than one long one, and
 * the same for the keyboard (Enter, then Enter). Arming expires on its own, so
 * a tile left armed by an earlier tap cannot fire from a much later one.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    property string hovered: ""
    property int focusIndex: -1
    property bool keyHeld: false

    property int holdingIndex: -1
    property real holdProgress: 0

    /**
     * The minimal bar's confirmation gesture: tap twice rather than hold. See the
     * header. Everything the hold drives below is gated on this, so the heat fill
     * and the hold timers simply never run there.
     */
    readonly property bool doubleTap: Flags.barEnabled

    /** The destructive tile armed by a first tap, waiting for its second. -1 is none. */
    property int armedIndex: -1

    /** How long an armed tile stays armed. Long enough to be deliberate, short
     *  enough that arming is never a decision the user made minutes ago. */
    readonly property int armWindow: 2500

    Timer {
        id: armTimer
        interval: root.armWindow
        repeat: false
        onTriggered: root.armedIndex = -1
    }

    Timer {
        id: lockDelay
        interval: Math.floor(Math.random() * (500 - 475 + 1)) + 475
        repeat: false
        onTriggered: {
            Quickshell.execDetached([
                "sh",
                Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"
            ]);
            root.requestClose();
        }
    }

    readonly property real anchorX: tiles.x + tiles.width / 2
    readonly property real anchorY: tiles.y - 10 * root.s
    property real tileHeatX: 0
    property real tileHeatY: 0
    property string soulKey: ""
    property real hoverX: 0
    property real hoverY: 0
    readonly property real heatX: holdingIndex >= 0 ? tileHeatX : (soulKey.length ? hoverX : anchorX)
    readonly property real heatY: holdingIndex >= 0 ? tileHeatY : (soulKey.length ? hoverY : anchorY)

    ameForm: holdingIndex >= 0 ? "dock" : (soulKey.length ? "soul" : "off")
    amePoint: Qt.point(heatX, heatY)

    readonly property var actions: [
        { key: "lock",     glyph: "lock",     label: "Lock",     confirm: false, dispatch: "",             argv: [Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"] },
        { key: "logout",   glyph: "logout",   label: "Logout",   confirm: true,  dispatch: "hl.dsp.exit()", argv: [] },
        { key: "suspend",  glyph: "suspend",  label: "Sleep",    confirm: false, dispatch: "",             argv: ["systemctl", "suspend"] },
        { key: "reboot",   glyph: "reboot",   label: "Restart",  confirm: true,  dispatch: "",             argv: ["systemctl", "reboot"] },
        { key: "shutdown", glyph: "shutdown", label: "Shutdown", confirm: true,  dispatch: "",             argv: ["systemctl", "poweroff"] }
    ]

    readonly property int splitAfter: 2

    function run(a) {
        if (a.key === "lock") {
            root.requestClose();
            lockDelay.start();
            return;
        }

        if (a.dispatch && a.dispatch.length)
            Hyprland.dispatch(a.dispatch);
        else
            Quickshell.execDetached(a.argv);

        root.requestClose();
    }

    /**
     * Slide keyboard focus across the tiles; `dir` is +1 (right) or -1 (left).
     * Releases any held heat so focus never drags a half-filled tile with it.
     */
    function move(dir) {
        keyHeld = false;
        if (focusIndex < 0)
            focusIndex = dir > 0 ? 0 : actions.length - 1;
        else
            focusIndex = Math.max(0, Math.min(actions.length - 1, focusIndex + dir));
    }

    /**
     * Enter pressed on the focused tile. A safe tile fires at once; a destructive
     * tile arms or fires under the double tap, and otherwise latches keyHeld so
     * its delegate ramps the heat fill, mirroring a pointer hold. Returns true
     * when a tile consumed the key.
     */
    function pressFocused() {
        if (focusIndex < 0 || focusIndex >= actions.length)
            return false;
        if (actions[focusIndex].confirm) {
            if (doubleTap) {
                armOrRun(focusIndex);
                return true;
            }
            keyHeld = true;
            return true;
        }
        run(actions[focusIndex]);
        return true;
    }

    /**
     * Enter released: drop the destructive hold so an early release drains the
     * heat instead of confirming. Nothing to undo under the double tap — there is
     * no hold to drain, and the armed state is deliberately kept until it fires or
     * expires, so releasing Enter does not silently disarm what the first tap set.
     */
    function releaseFocused() {
        keyHeld = false;
    }

    /**
     * The double tap, shared by the pointer and the keyboard so both are the same
     * two steps in the same order. A safe tile fires outright; a destructive one
     * arms on the first call and fires on the second, disarming first so the
     * window cannot reopen between `run` and the surface closing.
     */
    function armOrRun(index) {
        if (index < 0 || index >= actions.length)
            return false;
        var a = actions[index];
        if (!a.confirm) {
            run(a);
            return true;
        }
        if (armedIndex === index) {
            armedIndex = -1;
            armTimer.stop();
            run(a);
        } else {
            armedIndex = index;
            armTimer.restart();
        }
        return true;
    }

    onActiveChanged: if (!active) {
        hovered = "";
        soulKey = "";
        focusIndex = -1;
        keyHeld = false;
        holdingIndex = -1;
        holdProgress = 0;
        armedIndex = -1;
        armTimer.stop();
    }

    /**
     * Content reveal latch: the header, tiles and action label stay hidden
     * until the shared 100ms delay after the surface opens, so the glyphs
     * don't pop in while the pill is still settling into the power surface.
     */
    RevealLatch {
        id: reveal
        shown: root.open
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 22 * root.s
        opacity: (root.open && reveal.ready) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "電"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "POWER"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }
    }

    Row {
        id: tiles
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        spacing: 12 * root.s
        opacity: (root.open && reveal.ready) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.actions

            delegate: Row {
                id: cell
                required property int index
                required property var modelData
                spacing: 12 * root.s

                Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.index === root.splitAfter
                        width: 1
                        height: 26 * root.s
                        color: Theme.hair
                    }

                Item {
                    id: tile
                    width: 50 * root.s
                    height: 50 * root.s

                    readonly property real hold: heat.hold
                    readonly property bool kbFocus: root.focusIndex === cell.index
                    readonly property bool isHover: root.hovered === cell.modelData.key || tile.kbFocus
                    readonly property bool holding: heat.holding
                    /** Armed by a first tap, waiting on its second. */
                    readonly property bool armed: cell.modelData.confirm && root.armedIndex === cell.index
                    readonly property bool lit: isHover || tile.holding || tile.armed
                    readonly property color accent: cell.modelData.confirm ? Theme.vermLit : Theme.cream

                    onKbFocusChanged: {
                        if (!tile.kbFocus)
                            return;
                        root.hovered = cell.modelData.key;
                        root.soulKey = cell.modelData.key;
                        const c = tile.mapToItem(root, tile.width / 2, 0);
                        root.hoverX = c.x;
                        root.hoverY = c.y - 9 * root.s;
                    }

                    /**
                     * A held Enter on the focused destructive tile drives the same
                     * heat fill as a pointer hold; dropping the key drains it.
                     * Off under the double tap, where there is no hold at all.
                     */
                    readonly property bool keyDriving: tile.kbFocus && root.keyHeld
                        && cell.modelData.confirm && !root.doubleTap
                    onKeyDrivingChanged: {
                        if (tile.keyDriving)
                            heat.press();
                        else
                            heat.release();
                    }

                    onHoldChanged: {
                        if (cell.modelData.confirm && tile.hold > 0.001) {
                            root.holdingIndex = cell.index;
                            root.holdProgress = tile.hold;
                            const c = tile.mapToItem(root, tile.width / 2, tile.height / 2);
                            root.tileHeatX = c.x;
                            root.tileHeatY = c.y;
                        } else if (root.holdingIndex === cell.index) {
                            root.holdingIndex = -1;
                            root.holdProgress = 0;
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Motion.rTile * root.s
                        color: tile.isHover ? Theme.frameBg : "transparent"
                        border.width: tile.armed ? 2 : 1
                        border.color: tile.armed ? Theme.vermLit
                            : (tile.isHover ? Theme.frameBorder : Theme.border)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.width { NumberAnimation { duration: Motion.fast } }
                    }

                    /**
                     * Heat fill lives in a ClippingRectangle that carries the
                     * tile's corner radius. A plain Rectangle with its own radius
                     * gets it clamped to height/2 while the fill is still flat,
                     * so corners poked outside the tile outline on the first beat
                     * of every hold.
                     */
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: (Motion.rTile - 1) * root.s
                        color: "transparent"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: tile.height * tile.hold
                            visible: tile.holding
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.alpha(Theme.verm, 0.7) }
                                GradientStop { position: 1.0; color: Qt.alpha(Theme.vermLit, 0.15) }
                            }
                        }
                    }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 22 * root.s
                        height: 22 * root.s
                        name: cell.modelData.glyph
                        /** Armed reads as hot, the same word the hold's fill used. */
                        color: (tile.holding || tile.armed) ? Theme.flameCore
                            : (tile.lit ? tile.accent : Theme.iconDim)
                        stroke: 1.9
                    }

                    HeatHold {
                        id: heat
                        onConfirmed: root.run(cell.modelData)
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.hovered = cell.modelData.key;
                            root.soulKey = cell.modelData.key;
                            const c = tile.mapToItem(root, tile.width / 2, 0);
                            root.hoverX = c.x;
                            root.hoverY = c.y - 9 * root.s;
                        }
                        onExited: {
                            if (root.hovered === cell.modelData.key)
                                root.hovered = "";
                            if (cell.modelData.confirm)
                                heat.cancel();
                        }
                        /** The heat fill is the hold's; the double tap never starts one. */
                        onPressed: if (cell.modelData.confirm && !root.doubleTap) heat.press()
                        onReleased: if (cell.modelData.confirm && !root.doubleTap) heat.release()
                        onClicked: {
                            if (cell.modelData.confirm)
                                root.armOrRun(cell.index);
                            else
                                root.run(cell.modelData);
                        }
                    }
                }
            }
        }
    }

    Text {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tiles.bottom
        anchors.topMargin: 12 * root.s
        /**
         * What the label is describing: the held tile if there is one, else the
         * armed one, else whatever is hovered or focused. Arming outranks the
         * hover because a tile the pointer has since left is still the tile the
         * next tap would fire.
         */
        readonly property int focusIdx: root.holdingIndex >= 0
            ? root.holdingIndex : root.armedIndex
        readonly property string focusKey: root.focusIdx >= 0
            ? root.actions[root.focusIdx].key : root.hovered
        readonly property var act: {
            for (var i = 0; i < root.actions.length; i++)
                if (root.actions[i].key === label.focusKey)
                    return root.actions[i];
            return null;
        }
        readonly property bool armed: root.focusIdx >= 0 && root.armedIndex === root.focusIdx
        /**
         * The verb the destructive tiles ask for, per presentation: hold where
         * there is a fill to watch climb, double tap in the bar, and once armed
         * the second tap is named outright so the next press is never a guess.
         */
        readonly property string confirmHint: root.doubleTap
            ? (label.armed ? "tap again" : "double tap")
            : "hold"
        text: act ? (act.confirm ? act.label + " — " + label.confirmHint : act.label) : ""
        color: act && act.confirm ? Theme.vermLit : Theme.subtle
        font.family: Theme.font
        font.pixelSize: 11 * root.s
        font.weight: Font.Medium
        font.letterSpacing: 0.4 * root.s
        opacity: (text.length > 0 && root.open && reveal.ready) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }
}

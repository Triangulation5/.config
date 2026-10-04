import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.bar.blocks as Blocks

/**
 * One monitor's strip: a layer-shell window pinned full width to the top edge
 * that reserves its own band, so tiled windows start below it the way they do
 * under the pill's reserve.
 *
 * Everything on it is a text readout. There is deliberately no MouseArea
 * anywhere in this module: the bar is a glance, not a control surface, and the
 * only interaction it owns is the screen space it holds — plus the two things it
 * can be asked to pick from (the launcher's Dmenu and the power list's
 * PowerList), both keyboard-driven. While either is open on this output the strip
 * hides its readouts, draws that surface over the whole band and takes the
 * keyboard exclusively, and puts itself on the overlay layer for that time: on
 * the top layer a fullscreen window covers the strip, which would leave a picker
 * nobody can see holding the keyboard.
 *
 * The layout symbol (`[]=`, `[\]`, `|||`) sits right after the workspace tags, in
 * dwm's own place, and follows this output's active workspace.
 *
 * The status group sits on `Chip`s, which draw nothing at all unless
 * `Flags.barChips` is on, so the readouts can carry a backdrop without the
 * strip's rhythm changing when that is switched. The chrome stays here rather
 * than inside each block: a block is its text, and only this file knows how the
 * strip's blocks are meant to sit together.
 *
 * Height and type scale come from `Flags.barHeight` and `uiScale` on the same
 * height/1080 ratio the pill uses, so one setting lands evenly on any output.
 * On top of that ratio the blocks are laid out at `typeScale`, which carries the
 * user's own `Flags.barFontScale` as well: every readout's type comes off it, and
 * so do the chip padding and the tag spacing that are built from it, so one
 * slider grows the whole strip's words together. The strip's height, its margins
 * and the gap between blocks stay on `s`, because those belong to Bar height and
 * to the layout rather than to the type.
 *
 * The backdrop and every colour on the strip come from BarStyle, so the bar
 * follows the palette and the chosen style without a token named in here.
 *
 * Arriving is part of the bar. The strip falls into place and its words come up
 * behind it, both driven by `BarSwap` rather than by anything here, because the
 * strip is one of four surfaces that have to move together for the switch off
 * the pill to read as a switch and not a flicker. Nothing in this file times it.
 */
PanelWindow {
    id: bar

    required property var modelData

    readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
    readonly property string screenName: modelData ? modelData.name : ""

    /** What the blocks are laid out at: the geometry scale, plus the font scale. */
    readonly property real typeScale: bar.s * Flags.barFontScale

    /** True on the one output whose strip is carrying the launcher right now. */
    readonly property bool launcherHere: BarLauncher.open && BarLauncher.monitor === bar.screenName

    /** True on the one output whose strip is carrying the power list right now. */
    readonly property bool powerHere: BarPower.open && BarPower.monitor === bar.screenName

    /**
     * Either picker on this output. The readouts and the layer both key off this
     * rather than off each surface, so the two cannot disagree about whether the
     * strip is currently a glance or something you can pick from.
     */
    readonly property bool picking: bar.launcherHere || bar.powerHere

    screen: modelData

    /**
     * The surface is transparent and the strip paints its own backdrop.
     *
     * This used to be the window's own `color`. A window's clear colour fills the
     * whole surface the frame the window exists, and the surface is now full
     * height for its whole life (see `implicitHeight`) — so a clear colour here
     * would paint the whole band at once and there would be no arrival to watch.
     */
    color: "transparent"

    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "silhouette-bar"
    WlrLayershell.layer: bar.picking ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: bar.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true }

    /**
     * How far the strip has dropped, 0 before it starts and 1 the whole way down.
     * The bar comes in as a solid band sliding off the top edge rather than
     * appearing at full size, so the switch reads as something arriving from
     * above — the same motion, in the opposite direction, the pill left by.
     */
    readonly property real drop: BarSwap.barPresence

    readonly property real fullHeight: Math.round(Flags.barHeight * bar.s)

    /**
     * The surface is its final size for as long as it is alive, and is never
     * resized.
     *
     * This used to be `fullHeight * drop`, with `exclusiveZone` following it. That
     * is the one part of the swap the compositor cannot interpolate: a changed
     * height reconfigures the layer surface, and a changed exclusive zone makes
     * Hyprland re-lay-out every tiled window. Both are discrete events, and both
     * were happening on every frame of a 450ms swap — around sixty surface
     * reconfigures and sixty full relayouts, which is what made the strip flicker
     * against the top edge while the windows below stair-stepped down it.
     *
     * A compositor is handed a number and acts on it; it does not tween, and
     * asking it to land somewhere new sixty times a second is exactly the wrong
     * way to animate. So the reserve is claimed once, whole, and the arrival is
     * drawn inside the window instead (see `strip`).
     *
     * The trade is real and worth stating: the tiled windows are now pushed down
     * in a single step when the bar appears, rather than being carried down with
     * the strip as it falls. One discrete relayout reads as the bar taking its
     * band; sixty of them read as two shells fighting over the top edge.
     */
    implicitHeight: Math.max(1, bar.fullHeight)

    exclusiveZone: implicitHeight

    /** The readouts, which arrive behind the strip rather than with it. */
    readonly property real words: BarSwap.barWords

    /**
     * Clips the strip's arrival to the window. The scene graph bounds itself to
     * the render target — which is exactly the window's size — so this is belt
     * and braces, keeping the band's edge from bleeding along y = 0 while it is
     * still sliding in.
     */
    Item {
        anchors.fill: parent
        clip: true

        /**
         * The strip, already at its final size, slid down into view.
         *
         * Only `y` moves; the height is constant. That makes the arrival a
         * translate of one finished rectangle rather than a rectangle whose size
         * is recomputed and re-rasterised every frame — the same reason the
         * surface itself is not resized. At `drop` 0 the strip sits entirely above
         * the window and is clipped away; at 1 it is exactly in place.
         */
        Item {
            id: strip
            width: parent.width
            height: bar.fullHeight
            y: bar.fullHeight * (bar.drop - 1)

            Rectangle {
                anchors.fill: parent
                color: BarStyle.bg
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12 * bar.s
                anchors.rightMargin: 12 * bar.s
                spacing: 12 * bar.s
                visible: !bar.picking
                opacity: bar.words

                /**
                 * The tags and the layout symbol are one group, as in dwm: the symbol
                 * sits against the tags at their own tight spacing, not a block-width
                 * away. It takes a tag's padding (a transparent chip, the same trick an
                 * idle tag uses) so its text lines up with the digits' rhythm.
                 */
                RowLayout {
                    spacing: 2 * bar.typeScale
                    Layout.alignment: Qt.AlignVCenter

                    Blocks.Workspaces {
                        s: bar.typeScale
                        screenName: bar.screenName
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Chip {
                        s: bar.typeScale
                        radius: 0
                        fill: "transparent"
                        edge: "transparent"
                        visible: symbol.visible
                        Layout.alignment: Qt.AlignVCenter

                        Blocks.LayoutSymbol {
                            id: symbol
                            s: bar.typeScale
                            screenName: bar.screenName
                        }
                    }
                }

                Blocks.WindowTitle {
                    s: bar.typeScale
                    screenName: bar.screenName
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: 460 * bar.s
                }

                Item { Layout.fillWidth: true }

                Chip {
                    s: bar.typeScale
                    Layout.alignment: Qt.AlignVCenter
                    Blocks.Cpu { s: bar.typeScale }
                }

                Chip {
                    s: bar.typeScale
                    Layout.alignment: Qt.AlignVCenter
                    Blocks.Memory { s: bar.typeScale }
                }

                /** The chip follows the block: a machine with no pack has neither. */
                Chip {
                    s: bar.typeScale
                    Layout.alignment: Qt.AlignVCenter
                    visible: Battery.present
                    Blocks.Battery { s: bar.typeScale }
                }

                Chip {
                    s: bar.typeScale
                    Layout.alignment: Qt.AlignVCenter
                    Blocks.Volume { s: bar.typeScale }
                }

                Chip {
                    s: bar.typeScale
                    Layout.alignment: Qt.AlignVCenter
                    Blocks.Clock { s: bar.typeScale }
                }
            }

            /**
             * Built only while the launcher is open on this output, and fresh each time,
             * so the query and the selection reset by construction. It is declared after
             * the readouts so it draws over them, and it takes focus once it exists.
             *
             * The power list is its own loader beside this one rather than a branch inside
             * it, so each surface is built only while it is the one open — the same reason
             * the readouts and each surface are separate trees rather than one item with
             * its contents swapped.
             */
            Loader {
                anchors.fill: parent
                active: bar.launcherHere
                onLoaded: item.focusInput()

                sourceComponent: Dmenu {
                    s: bar.typeScale
                    g: bar.s
                }
            }

            Loader {
                anchors.fill: parent
                active: bar.powerHere
                onLoaded: item.focusInput()

                sourceComponent: PowerList {
                    s: bar.typeScale
                    g: bar.s
                }
            }
        }
    }
}

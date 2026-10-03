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
    color: BarStyle.bg
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: implicitHeight
    WlrLayershell.namespace: "silhouette-bar"
    WlrLayershell.layer: bar.picking ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: bar.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true }
    implicitHeight: Math.round(Flags.barHeight * bar.s)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12 * bar.s
        anchors.rightMargin: 12 * bar.s
        spacing: 12 * bar.s
        visible: !bar.picking

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

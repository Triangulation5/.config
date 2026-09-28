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
 * only interaction it owns is the screen space it holds.
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

    screen: modelData
    color: BarStyle.bg
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: implicitHeight
    WlrLayershell.namespace: "silhouette-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true }
    implicitHeight: Math.round(Flags.barHeight * bar.s)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12 * bar.s
        anchors.rightMargin: 12 * bar.s
        spacing: 12 * bar.s

        Blocks.Workspaces {
            s: bar.typeScale
            screenName: bar.screenName
            Layout.alignment: Qt.AlignVCenter
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
}

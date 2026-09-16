import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config

/**
 * Slider editor for `type: "slider"` rows: the name with the live value on the
 * right, and the groove on its own full-width line under both. Drag anywhere
 * along the groove, or click to jump — a press jumps to the pointer, a press
 * and move follows it, and the handle tracks the cursor with no animation while
 * it is held.
 *
 * The row carries the bounds and the formatting: `min`/`max`/`step` (a step of 0
 * keeps the value continuous), `unit` and `displayScale` (which multiplies for
 * display only, so a 0.7 fraction can read as `70 %`), and `format: "time"` for
 * a minutes-of-day value shown as `HH:MM` — the same split the shell's
 * `ScrubValue` makes with its `fmt`. An empty `unit` is meaningful: bare
 * fractions, no suffix.
 */
SettingRow {
    id: root

    property var row: null

    readonly property real from: root.row && root.row.min !== undefined ? root.row.min : 0
    readonly property real to: root.row && root.row.max !== undefined ? root.row.max : 1
    readonly property real step: root.row && root.row.step !== undefined ? root.row.step : 0
    readonly property string unit: root.row && root.row.unit !== undefined ? root.row.unit : "px"
    readonly property real displayScale: root.row && root.row.displayScale !== undefined ? root.row.displayScale : 1
    readonly property string format: root.row && root.row.format ? root.row.format : ""

    readonly property real value: Sources.read(root.row) !== undefined ? Sources.read(root.row) : 0

    label: root.row ? root.row.label : ""
    caption: root.row && root.row.caption ? root.row.caption : ""

    /**
     * The value as the row reads it: `HH:MM` in time format, otherwise the
     * display-scaled number with its unit. Integers stay integers and fractional
     * steps keep their decimals, so a row can read `0.7`, `55 %` or `3600 K`.
     */
    function displayText() {
        if (root.format === "time") {
            var mins = Math.round(root.value) % 1440;
            if (mins < 0)
                mins += 1440;
            var h = Math.floor(mins / 60);
            var m = mins % 60;
            return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
        }
        var scaled = Math.round(root.value * root.displayScale * 100) / 100;
        var number = Number.isInteger(scaled) ? String(scaled)
                                              : String(scaled.toFixed(2)).replace(/\.?0+$/, "");
        return root.unit.length > 0 ? number + " " + root.unit : number;
    }

    /** The row's one write path: the groove's only job is to call it. */
    function commit(value) {
        Sources.write(root.row, value);
    }

    /** `raw` landed on the step grid and clamped to the bounds. */
    function snap(raw) {
        var v = root.step > 0 ? Math.round(raw / root.step) * root.step : raw;
        v = Math.max(root.from, Math.min(root.to, v));
        return Math.round(v * 10000) / 10000;
    }

    control: Text {
        text: root.displayText()
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeNormal
        // Fixed width, so the name beside it does not shift as the digits grow.
        Layout.preferredWidth: 72
        horizontalAlignment: Text.AlignRight
    }

    below: Item {
        Layout.fillWidth: true
        implicitHeight: 18

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Theme.sliderTrack

            Rectangle {
                width: Math.max(handle.width / 2, handle.x + handle.width / 2)
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }

        Rectangle {
            id: handle
            width: 16
            height: 16
            radius: 8
            color: Theme.accent
            anchors.verticalCenter: parent.verticalCenter
            x: ((root.value - root.from) / (root.to - root.from)) * (track.width - width)
            scale: dragArea.pressed ? 1.15 : 1.0

            // Animated only for programmatic moves (Reset, or the shell writing
            // the flag); while the pointer holds it the handle must not lag.
            Behavior on x {
                enabled: !dragArea.pressed
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }

            layer.enabled: true
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            function update(mx) {
                // A groove with no width yet — the first frame after a page
                // switch — would divide by zero, and the NaN would land in
                // flags.json as a 0. Nothing to drag against, nothing to write.
                if (track.width <= 0)
                    return;
                var ratio = Math.max(0, Math.min(1, mx / track.width));
                var v = root.snap(root.from + ratio * (root.to - root.from));
                if (v !== root.value)
                    root.commit(v);
            }

            onPressed: mouse => update(mouse.x)
            // positionChanged keeps firing while a button is held without
            // hoverEnabled, which is what makes this draggable anywhere on the
            // groove rather than click-to-jump only.
            onPositionChanged: mouse => { if (pressed) update(mouse.x); }
        }
    }
}

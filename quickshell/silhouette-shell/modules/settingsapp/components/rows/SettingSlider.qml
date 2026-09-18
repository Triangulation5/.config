import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.components
import qs.modules.settingsapp.config

/**
 * Slider editor for `type: "slider"` rows: the name with the live value on the
 * right, and the groove on its own full-width line under both. Press the knob
 * and it moves with the pointer, keeping the spot you grabbed it by, the way a
 * phone's level bar does; press the bare groove and the value jumps to the
 * pointer first, then keeps following. The knob tracks the cursor with no
 * animation while it is held.
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
        // A little taller than the resting knob so the pressed knob (which grows)
        // still has a pixel to spare instead of touching the slot's edges.
        implicitHeight: 20

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

        /**
         * The knob's holder: a fixed 16px box that does the travelling (`x` is
         * mapped against *this* width, so the mapping never shifts under a
         * growing knob), with the visible dot centred inside it.
         */
        Item {
            id: handle
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            x: ((root.value - root.from) / (root.to - root.from)) * (track.width - width)

            // Animated only for programmatic moves (Reset, or the shell writing
            // the flag); while the pointer holds it the handle must not lag.
            Behavior on x {
                enabled: !dragArea.pressed
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }

            /**
             * The dot itself, and the press feedback: held, it grows. Deliberately
             * a *size* change and not a `scale` transform, and deliberately not
             * layered (`layer.enabled`). Both composite the dot into an offscreen
             * texture and stretch it — the knob goes soft the moment it is held,
             * which is exactly what a transform-scaled or rasterised knob does.
             * Animating the geometry instead redraws the shape at every step and
             * stays sharp. Nothing here needs an offscreen pass.
             */
            Rectangle {
                id: knob
                width: dragArea.pressed ? 18 : handle.width
                height: width
                radius: width / 2
                color: Theme.accent
                anchors.centerIn: parent

                Behavior on width {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            /**
             * Without this the row is click-only in practice. The page lives in
             * a ScrollView, and its Flickable takes the press as soon as the
             * pointer moves past the drag threshold — so a knob dragged more
             * than a few pixels turned into a scroll and stopped following the
             * pointer, while a plain click still landed. Same idiom as the
             * shell's own ScrubValue.
             */
            preventStealing: true

            /**
             * Distance from the pointer to the knob's centre while held.
             * Grabbing the knob keeps it, so the value does not jump under the
             * finger; pressing bare groove leaves it at 0, which is what makes
             * that press behave like a jump to the pointer.
             */
            property real grabOffset: 0

            /**
             * What the knob's centre travels across. The knob's own width is the
             * margin at each end, matching the handle's own mapping — measuring
             * against the full track instead left the knob unable to reach the
             * ends and put the value under the pointer slightly off.
             */
            readonly property real span: track.width - handle.width

            function update(mx) {
                // A groove with no width yet — the first frame after a page
                // switch — would divide by zero, and the NaN would land in
                // flags.json as a 0. Nothing to drag against, nothing to write.
                if (track.width <= 0 || span <= 0)
                    return;
                var ratio = Math.max(0, Math.min(1, (mx - grabOffset) / span));
                var v = root.snap(root.from + ratio * (root.to - root.from));
                if (v !== root.value)
                    root.commit(v);
            }

            onPressed: mouse => {
                var onKnob = mouse.x >= handle.x && mouse.x <= handle.x + handle.width;
                grabOffset = onKnob ? mouse.x - (handle.x + handle.width / 2) : 0;
                if (!onKnob)
                    update(mouse.x);
            }
            // positionChanged keeps firing while a button is held without
            // hoverEnabled, which is what makes this draggable anywhere on the
            // groove rather than click-to-jump only.
            onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            onReleased: dragArea.grabOffset = 0
        }
    }
}

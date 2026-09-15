import QtQuick
import QtQuick.Layouts
import "../config"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 0
    property string unit: "px"

    // Captured once at startup (after the initial `value:` binding is applied)
    // so resetToDefault() can restore it later.
    // Multiplier for display only (e.g. 100 to show a fraction as %).
    // Named displayScale to avoid clashing with Item.scale.
    property real displayScale: 1

    property real defaultValue: 0
    Component.onCompleted: defaultValue = value
    function resetToDefault() { root.commit(defaultValue) }

    // When a store drives the slider, bind `value` to the store and assign
    // `onCommit` instead — writes route through commit() so the `value:`
    // binding is never destroyed by a drag (the reference behavior).
    property var onCommit: null
    function commit(v) {
        if (onCommit !== null) onCommit(v);
        else value = v;
    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: root.label
            color: Theme.text
            font.pixelSize: Theme.fontSizeNormal
            Layout.fillWidth: true
        }

        Text {
            // Step-aware value text: integers stay integers, fractional
            // steps show their decimals (0.7 px, 5 %, 3600 K...).
            property string shown: {
                var v = root.value * root.displayScale;
                var rounded = Math.round(v * 100) / 100;
                return (Number.isInteger(rounded) ? rounded : rounded.toFixed(2).replace(/\.?0+$/, "")) + " " + root.unit;
            }
            text: shown
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeNormal
        }
    }

    Item {
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

            // Only animate x when the value changes programmatically (e.g. Reset
            // to Defaults). While the user is actively dragging, the handle must
            // track the cursor with zero lag, so the Behavior is switched off.
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

            function updateValue(mx) {
                var ratio = Math.max(0, Math.min(1, mx / track.width))
                var raw = root.from + ratio * (root.to - root.from)
                if (root.step > 0)
                    raw = Math.round(raw / root.step) * root.step
                raw = Math.max(root.from, Math.min(root.to, raw))
                root.commit(Math.round(raw * 10000) / 10000)
            }

            onPressed: (mouse) => updateValue(mouse.x)
            // positionChanged fires continuously while a button is held even
            // without hoverEnabled, so this is what makes the slider draggable
            // anywhere along the track, not just click-to-jump.
            onPositionChanged: (mouse) => { if (pressed) updateValue(mouse.x) }
        }
    }
}

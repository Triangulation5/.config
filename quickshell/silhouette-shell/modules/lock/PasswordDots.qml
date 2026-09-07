pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.lock
import "shapeGeometry.js" as Shapes

/**
 * Lock screen password dots: one bead per typed character, synced to the
 * field's text length. The entrance style is driven by the LOCKSCREEN setting
 * (Flags.lockDotsMode) and each style lives in its own component - DropDot
 * springs beads in from above with a bounce, PulseDot makes the freshest
 * bead breathe like a wick tip, and GPixelDot faithfully ports the AOSP
 * PIN-shape entry animation: each
 * bead plays one of six per-session-shuffled geometric flourishes (sparkle,
 * triangle, star, circle ripple, heart, rounded square) that collapse into
 * the standard dot on the AOSP 350ms timeline, with the ring cross-fade on
 * backspace. `field` is the password TextInput and `host` the lock surface
 * (for `revealPassword`).
 */
Item {
    id: root

    property real s: 1.1
    property var host: null
    property var field: null
    /** Entrance style for new beads, driven by the shared LOCKSCREEN setting. */
    readonly property string mode: Flags.lockDotsMode

    /** Number of AOSP shapes in the flourish cycle (see shapeGeometry.js). */
    readonly property int shapeCount: Shapes.SHAPES.length

    /** Live bead count; also the index into the shuffled cycle (AOSP mPosition). */
    property int liveCount: 0

    /** Per-session shuffled order of the six flourishes (AOSP PinShapeAdapter). */
    property var gpixelCycle: []

    /** True while a GPixel delete cross-fade plays; extra backspaces queue up. */
    property bool deleteInFlight: false
    property int pendingDelete: 0

    Component {
        id: dropDot
        DropDot {}
    }
    Component {
        id: pulseDot
        PulseDot {}
    }
    Component {
        id: gpixelDot
        GPixelDot {}
    }

    /** Shuffle 0..N-1 once per session, mirroring PinShapeAdapter.shapes.shuffle(). */
    function shuffleCycle() {
        var order = [];
        for (var i = 0; i < root.shapeCount; ++i)
            order.push(i);
        for (var j = order.length - 1; j > 0; --j) {
            var k = Math.floor(Math.random() * (j + 1));
            var tmp = order[j];
            order[j] = order[k];
            order[k] = tmp;
        }
        root.gpixelCycle = order;
    }

    /** Remove a bead whose delete cross-fade finished; drain the queue. */
    function removeDeleting(i) {
        if (i < 0 || i >= passwordDots.count) {
            // The model was cleared underneath us (bulk remove).
            root.deleteInFlight = false;
            root.pendingDelete = 0;
            return;
        }
        passwordDots.remove(i);
        root.deleteInFlight = false;
        if (root.pendingDelete > 0 && passwordDots.count > 0) {
            root.pendingDelete--;
            root.deleteInFlight = true;
            passwordDots.setProperty(passwordDots.count - 1, "deleting", true);
        }
        root.liveCount = Math.max(0, root.liveCount - 1);
    }

    Row {
        anchors.centerIn: parent
        // GPixel's big flourish canvases sit tighter together; the classic
        // styles keep their original spacing.
        spacing: root.mode === "gpixel" ? 3 * root.s : 7 * root.s
        visible: passwordDots.count > 0 && !host.revealPassword

        ListModel {
            id: passwordDots
        }

        Connections {
            target: field

            property int previousLength: 0

            function onTextChanged() {
                var current = field.text.length;

                if (current > previousLength) {
                    for (var i = previousLength; i < current; ++i) {
                        // Shape slot is fixed at creation, like getShape(mPosition).
                        passwordDots.append({
                            deleting: false,
                            gshape: root.gpixelCycle[root.liveCount % root.shapeCount]
                        });
                        root.liveCount++;
                    }
                } else if (current < previousLength) {
                    var removed = previousLength - current;
                    if (root.mode === "gpixel" && removed === 1 && passwordDots.count > 0) {
                        // Single backspace: quick ring cross-fade, serialized so
                        // each plays to completion; extra backspaces queue up.
                        if (!root.deleteInFlight) {
                            root.deleteInFlight = true;
                            passwordDots.setProperty(passwordDots.count - 1, "deleting", true);
                        } else {
                            root.pendingDelete++;
                        }
                    } else if (root.mode === "gpixel") {
                        // Bulk removal (Ctrl+U, select+delete): instant, no cross-fade.
                        // The model may hold a pending-deleting row, so drop rows
                        // until it matches the new text length.
                        root.deleteInFlight = false;
                        root.pendingDelete = 0;
                        var toRemove = passwordDots.count - current;
                        for (var k = 0; k < toRemove; ++k)
                            passwordDots.remove(passwordDots.count - 1);
                        root.liveCount = passwordDots.count;
                    } else {
                        for (var j = 0; j < removed; ++j)
                            passwordDots.remove(passwordDots.count - 1);
                    }
                }

                previousLength = current;
            }
        }

        Repeater {
            model: passwordDots

            Loader {
                required property int index
                required property bool deleting
                required property int gshape

                sourceComponent: root.mode === "drop" ? dropDot
                    : (root.mode === "pulse" ? pulseDot : gpixelDot)

                onLoaded: {
                    item.s = Qt.binding(() => root.s);
                    item.last = Qt.binding(() => index === passwordDots.count - 1);
                    /** Pulse beads cycle a small palette per slot, fixed at creation. */
                    if (root.mode === "pulse")
                        item.tone = index % 4;
                    /** GPixel beads: fixed shape from the shuffled cycle, plus
                        the serialized ring delete wired to the model row. */
                    if (root.mode === "gpixel") {
                        item.shapeIndex = gshape;
                        item.deleting = Qt.binding(() => deleting);
                        item.deleteDone.connect(() => root.removeDeleting(index));
                    }
                }
            }
        }
    }

    Component.onCompleted: root.shuffleCycle()
}
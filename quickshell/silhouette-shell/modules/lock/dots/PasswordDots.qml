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
 * PIN-shape entry animation: each bead plays one of six geometric
 * flourishes (sparkle, triangle, star,
 * circle ripple, heart, rounded square) that collapse into the standard dot
 * on the AOSP 350ms timeline, with the ring cross-fade on backspace. The six
 * shapes are shuffled afresh every typing session — mirroring AOSP's
 * per-bouncer PinShapeAdapter — and walked round-robin, so each session
 * opens a different order. Once the row is wider than the field it follows
 * AOSP's non-hinting Gravity.END fallback and pins to the field's right
 * edge, scrolling the oldest beads out under the left edge fade while the
 * newest dot always stays visible — every move smoothed by a 160ms slide.
 * `field` is the password TextInput and `host` the lock surface (for
 * `revealPassword`).
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
            /** The model was cleared underneath us (bulk remove). */
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

    /** Wipe every bead instantly and drop any queued deletes (the held-
     * backspace clear). Rows mid-cross-fade are simply destroyed; the next
     * typing session reshuffles and starts fresh. */
    function clearAll() {
        root.deleteInFlight = false;
        root.pendingDelete = 0;
        passwordDots.clear();
        root.liveCount = 0;
    }

    Row {
        id: dotsRow
        anchors.verticalCenter: parent.verticalCenter
        /** GPixel's big flourish canvases sit tighter together; the classic
         * styles keep their original spacing. */
        spacing: root.mode === "gpixel" ? 3 * root.s : 7 * root.s
        visible: passwordDots.count > 0 && !host.revealPassword

        /**
         * Horizontal follow so the row scrolls instead of piling up past the
         * field: centered while it fits (x = -w/2), then the right edge is
         * pinned to the field's right edge once wider (x = fw/2 - w) — AOSP
         * non-hinting Gravity.END. The formula is continuous across the
         * boundary, and the Behavior slides the row left as beads are added
         * and right as they're removed, so the newest dot always scrolls
         * into view and the oldest slide out under the left edge fade.
         */
        x: root.field ? Math.min(dotsRow.implicitWidth, root.field.width) / 2 - dotsRow.implicitWidth : -(dotsRow.implicitWidth / 2)

        Behavior on x {
            NumberAnimation {
                /** AOSP's 160ms reflow slide (LINEAR_OUT_SLOW_IN ≈ OutCubic). */
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        ListModel {
            id: passwordDots
        }

        Connections {
            target: field

            property int previousLength: 0

            function onTextChanged() {
                var current = field.text.length;

                if (current > previousLength) {
                    /** A typing session starts from an empty row: reshuffle the
                     * six shapes, mirroring AOSP's per-bouncer PinShapeAdapter
                     * so every session opens a different order. */
                    if (previousLength === 0)
                        root.shuffleCycle();
                    for (var i = previousLength; i < current; ++i) {
                        /** Shape slot is fixed at creation, like getShape(mPosition). */
                        passwordDots.append({
                            deleting: false,
                            gshape: root.gpixelCycle[root.liveCount % root.shapeCount]
                        });
                        root.liveCount++;
                    }
                } else if (current < previousLength) {
                    var removed = previousLength - current;
                    if (root.mode === "gpixel" && removed === 1 && passwordDots.count > 0) {
                        /** Single backspace: quick ring cross-fade, serialized so
                         * each plays to completion; extra backspaces queue up. */
                        if (!root.deleteInFlight) {
                            root.deleteInFlight = true;
                            passwordDots.setProperty(passwordDots.count - 1, "deleting", true);
                        } else {
                            root.pendingDelete++;
                        }
                    } else if (root.mode === "gpixel") {
                        /** Bulk removal (Ctrl+U, select+delete): instant, no cross-fade.
                         * The model may hold a pending-deleting row, so drop rows
                         * until it matches the new text length. */
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
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * Offscreen probe for the wallpaper surface's close dissolve.
 *
 * Renders the real `Wallpaper.qml` widget inside a pill-shaped stand-in, then
 * walks a ladder of static surface opacities in both layer states (the close
 * dissolve's layer on, and forced off as a control), grabbing a PNG at every
 * rung and logging the item's own state. Runs under QT_QPA_PLATFORM=offscreen,
 * so no window reaches the compositor and every frame is pixel-exact.
 *
 * Sequencer: one action per tick, and every rung is set on one tick and grabbed
 * on the next, so the `Behavior on opacity` has settled before the grab.
 */
ShellRoot {
    id: probe

    /** Session scale: (720 / 1080) * Flags.uiScale. */
    readonly property real us: 0.7333
    readonly property int pillW: Math.round(720 * us)
    readonly property int pillH: Math.round(172 * us)
    readonly property string outDir: Quickshell.env("HOME") + "/.config/quickshell/.probe-frames/out/"

    property bool probeOpen: true
    property bool forceLayerOff: false
    property int step: 0

    readonly property var ladder: [1.0, 0.92, 0.8, 0.6, 0.4, 0.25, 0.12, 0.05, 0.01]

    Window {
        id: win
        width: probe.pillW + 120
        height: probe.pillH + 80
        visible: true
        color: "#000000"

        property string lastState: ""

        Item {
            id: pill
            x: 60
            y: 40
            width: probe.pillW
            height: probe.pillH

            /** The pill body the surface sits on: anything the surface draws
             *  outside its own rect lands here and reads as "over the pill". */
            Rectangle {
                anchors.fill: parent
                radius: 20
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#26282c" }
                    GradientStop { position: 1.0; color: "#15161a" }
                }
            }

            Loader {
                id: ld
                anchors.fill: parent
                asynchronous: false
                source: "../silhouette-shell/modules/pill/widgets/wallpaper/Wallpaper.qml"
                onLoaded: {
                    item.s = Qt.binding(() => probe.us);
                    item.open = Qt.binding(() => probe.probeOpen);
                    item.morphCloseness = Qt.binding(() => 1.0);
                }
            }
        }

        function grab(tag) {
            var it = ld.item;
            win.lastState = tag + " presence=" + (it ? it.presence.toFixed(3) : "?")
                + " closing=" + (it ? it.closing : "?")
                + " layer=" + (it ? it.layer.enabled : "?")
                + " search=" + (it ? it.searching : "?");
            console.log("PROBE grab", win.lastState);
            win.contentItem.grabToImage(function (res) {
                res.saveToFile(probe.outDir + tag + ".png");
            }, Qt.size(win.width, win.height));
        }

        function setLayer(on) {
            var it = ld.item;
            if (!it)
                return;
            if (on)
                it.layer.enabled = Qt.binding(() => it.closing);
            else
                it.layer.enabled = false;
        }

        /**
         * Actions, one per tick:
         *   0            warm up (thumbs load async)
         *   1            open reference, layer off (what the strip looks like)
         *   2            close: open=false, layer on
         *   3 ..         per rung: set `presence`, then grab it on the next tick,
         *                first with the dissolve layer live, then the same ladder
         *                as a control with the layer forced off
         */
        Timer {
            interval: 320
            running: true
            repeat: true
            onTriggered: {
                var it = ld.item;
                var s = probe.step;
                probe.step = s + 1;

                if (s === 0) {
                    if (!it) {
                        console.log("PROBE waiting for the surface item");
                        probe.step = 0;
                        return;
                    }
                    return;
                }
                if (s === 1) {
                    probe.forceLayerOff = true;
                    probe.probeOpen = true;
                    win.setLayer(false);
                    return;
                }
                if (s === 2) {
                    win.grab("open_ref");
                    return;
                }
                if (s === 3) {
                    probe.forceLayerOff = false;
                    probe.probeOpen = false;
                    win.setLayer(true);
                    return;
                }

                /** s >= 4: the presence ladder, phase 0 with the layer live and
                 *  phase 1 as the same ladder with the layer forced off. Each
                 *  rung takes two ticks: one to set it, one to grab it settled. */
                var t = s - 4;
                var phase = Math.floor(t / (probe.ladder.length * 2));
                var within = t % (probe.ladder.length * 2);
                var rung = Math.floor(within / 2);
                var isControl = phase === 1;

                if (phase > 1) {
                    console.log("PROBE done, last:", win.lastState);
                    running = false;
                    return;
                }
                if ((within % 2) === 0) {
                    probe.forceLayerOff = isControl;
                    win.setLayer(!isControl);
                    it.presence = probe.ladder[rung];
                    return;
                }
                win.grab((isControl ? "control_" : "layer_") + rung
                         + "_pre" + probe.ladder[rung]);
            }
        }
    }
}

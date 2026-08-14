import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.modules.pill.widgets
import qs.components.animation

/**
 * Mixer surface: header with DND / Keep-Awake chips and a row of four vertical
 * ink-faders wired to real hardware (brightness via ddcutil, vibrance via
 * nvibrant, volume and mic via Pipewire). Fills the lower body of the pill.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 14
    mRight: 14
    mBottom: 12

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    /**
     * Output devices the user can make default: real sinks only, never the
     * per-app playback streams. Sorted by label so the list order stays stable
     * as nodes appear and vanish.
     */
    readonly property var outputSinks: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isSink && !n.isStream && n.audio)
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    /**
     * Input devices the user can make default: real sources only. The sink
     * monitors that Pipewire exposes alongside real mics also match isSink=false,
     * so they are dropped by name to keep the list to actual capture devices.
     */
    readonly property var inputSources: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && !n.isSink && !n.isStream && n.audio && !/monitor/i.test(n.name || ""))
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    function deviceLabel(node) {
        if (!node)
            return "";
        return node.description || node.nickname || node.name || "";
    }

    /** Which device dropdown is open: "out", "in", or "" for none. */
    property string openPicker: ""

    property int focusIndex: -1
    readonly property int faderCount: faders.length
    readonly property var faders: {
        void brRep.count;
        void blLoader.item;
        var out = [];
        for (var i = 0; i < brRep.count; i++) {
            var f = brRep.itemAt(i);
            if (f)
                out.push(f);
        }
        if (blLoader.item)
            out.push(blLoader.item);
        out.push(vibFader, volFader, micFader);
        return out;
    }
    readonly property bool surfaceHovered: hoverTracker.hovered

    /**
     * Tick centre of the focused fader, mapped into this mixer's root so the
     * bead glides as keyboard/hover focus moves across the row. Layout deps are
     * voided before mapToItem so the binding re-evaluates on resize (else stale).
     */
    readonly property point focusTickPoint: {
        void root.width;
        void root.height;
        void root.focusIndex;
        const i = Math.max(0, Math.min(faders.length - 1, root.focusIndex));
        const f = faders[i];
        if (!f)
            return Qt.point(0, 0);
        return f.mapToItem(root, f.tickCenter.x, f.tickCenter.y);
    }

    ameForm: "tick"
    amePoint: focusTickPoint

    /**
     * Pointer-driven fader targeting. MouseArea hover is flaky on this
     * layer-shell surface, so a non-blocking HoverHandler is the only hover
     * source. Its pointer x maps to a fader column and drives keyboard focus.
     */
    readonly property int hoverIndex: surfaceHovered && width > 0 && faders.length > 0
        && hoverTracker.point.position.y >= faderRow.y
        ? Math.max(0, Math.min(faders.length - 1, Math.floor(hoverTracker.point.position.x / (width / faders.length))))
        : -1
    onHoverIndexChanged: if (hoverIndex >= 0 && !keyLatch.running) focusIndex = hoverIndex

    HoverHandler {
        id: hoverTracker
    }

    /**
     * Brief keyboard-nav precedence: an arrow keypress latches focus for
     * Motion.standard so a stray pointer move doesn't yank the target away
     * mid-navigation. Hover resumes driving focus once it lapses.
     */
    Timer {
        id: keyLatch
        interval: Motion.standard
    }

    onActiveChanged: {
        focusIndex = active ? 0 : -1;
        if (!active)
            openPicker = "";
    }

    /**
     * Nudge the focused fader by `deltaPct` percent. Returns true when a fader
     * handled the step.
     */
    function stepFocused(deltaPct) {
        if (focusIndex < 0)
            return false;
        faders[focusIndex].step(deltaPct);
        keyLatch.restart();
        return true;
    }

    /**
     * Move keyboard focus across the fader row, wrapping at the ends. `dir` is +1
     * (right) or -1 (left); a fresh focus lands on the first or last fader.
     */
    function moveFocus(dir) {
        focusIndex = focusIndex < 0 ? (dir > 0 ? 0 : faders.length - 1)
                                    : (focusIndex + dir + faders.length) % faders.length;
        keyLatch.restart();
    }

    Component.onCompleted: Devices.detect()

    property real pendingVibrance: -1
    property int pendingBacklight: -1

    Timer {
        id: vibDebounce
        interval: 160
        onTriggered: if (root.pendingVibrance >= 0) {
            Devices.setVibrance(root.pendingVibrance);
            root.pendingVibrance = -1;
        }
    }

    Timer {
        id: blDebounce
        interval: 160
        onTriggered: if (root.pendingBacklight >= 0) {
            Devices.setBacklight(root.pendingBacklight);
            root.pendingBacklight = -1;
        }
    }

    /**
     * Mirror the shared backlight poller into Devices.backlightPct so the mixer
     * fader follows brightness keys / OSD changes, not just its own drags.
     */
    Connections {
        target: Backlight
        function onChanged() {
            Devices.backlightPct = Math.round(Backlight.brightness * 100);
        }
    }

    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.outputSinks).concat(root.inputSources).filter(Boolean)
    }

    Item {
        id: header
        z: 5
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "調"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "MIXER"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            DevicePickerChip {
                s: root.s
                glyph: "speaker"
                open: root.openPicker === "out"
                tip: "Output device"
                onToggled: root.openPicker = root.openPicker === "out" ? "" : "out"
            }
            DevicePickerChip {
                s: root.s
                glyph: "mic"
                open: root.openPicker === "in"
                tip: "Input device"
                onToggled: root.openPicker = root.openPicker === "in" ? "" : "in"
            }
            IconChip {
                s: root.s
                glyph: "dnd"
                on: Flags.dnd
                tipTitle: "Do not disturb"
                tipDesc: "Silence notifications"
                onToggled: Flags.dnd = !Flags.dnd
            }
            IconChip {
                s: root.s
                glyph: "awake"
                on: Flags.keepAwake
                tipTitle: "Keep awake"
                tipDesc: "Block sleep & screen-off"
                onToggled: Flags.keepAwake = !Flags.keepAwake
            }
            IconChip {
                s: root.s
                glyph: "sun"
                on: Flags.nightLightMode !== "off"
                tipTitle: "Night light"
                tipDesc: "Warm the screen"
                onToggled: NightLight.setMode(Flags.nightLightMode === "off" ? "on" : "off")
            }
            IconChip {
                s: root.s
                glyph: "gamepad"
                on: Flags.gameMode
                tipTitle: "Game mode"
                tipDesc: "Strip effects, quiet the desktop"
                onToggled: Flags.gameMode = !Flags.gameMode
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    DeviceMenu {
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.right: parent.right
        s: root.s
        kind: "out"
        open: root.openPicker === "out"
        model: root.outputSinks
        current: root.sink
        deviceLabel: root.deviceLabel
        onPick: (node) => { Pipewire.preferredDefaultAudioSink = node; root.openPicker = ""; }
    }

    DeviceMenu {
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.right: parent.right
        s: root.s
        kind: "in"
        open: root.openPicker === "in"
        model: root.inputSources
        current: root.source
        deviceLabel: root.deviceLabel
        onPick: (node) => { Pipewire.preferredDefaultAudioSource = node; root.openPicker = ""; }
    }

    Row {
        id: faderRow
        anchors.top: divider.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 142 * root.s
        spacing: 0

        readonly property real colW: width / Math.max(1, root.faderCount)

        Repeater {
            id: brRep
            model: Devices.ddcMonitors

            VFader {
                id: brFader

                required property var modelData
                required property int index

                property int pct: 75
                property real pendingPct: -1

                width: faderRow.colW
                s: root.s
                icon: "sun"
                subLabel: "Brightness"
                subPersistent: false
                focused: root.focusIndex === index
                value: pct / 100
                valueLabel: pct + "%"
                onMoved: (v) => pct = Math.max(5, Math.min(100, Math.round(v * 100)))
                onCommitted: (v) => {
                    pendingPct = Math.max(5, Math.min(100, Math.round(v * 100)));
                    brCommit.restart();
                }

                Timer {
                    id: brCommit
                    interval: 160
                    onTriggered: if (brFader.pendingPct >= 0) {
                        Devices.setBrightness(brFader.modelData.bus, brFader.pendingPct);
                        brFader.pendingPct = -1;
                    }
                }

                Process {
                    id: brRead
                    command: ["timeout", "3", "ddcutil", "getvcp", "10", "--bus", brFader.modelData.bus, "--brief"]
                    running: true
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var v = Devices.parseBrightness(this.text);
                            if (v >= 0)
                                brFader.pct = v;
                        }
                    }
                }
            }
        }

        Loader {
            id: blLoader
            active: Devices.backlightPresent
            visible: active
            width: active ? faderRow.colW : 0

            sourceComponent: VFader {
                width: faderRow.colW
                s: root.s
                icon: "sun"
                subLabel: "Brightness"
                subPersistent: false
                focused: root.focusIndex === brRep.count
                value: Devices.backlightPct / 100
                valueLabel: Devices.backlightPct + "%"
                onMoved: (v) => Devices.backlightPct = Math.max(1, Math.min(100, Math.round(v * 100)))
                onCommitted: (v) => { root.pendingBacklight = Math.max(1, Math.min(100, Math.round(v * 100))); blDebounce.restart(); }
            }
        }

        VFader {
            id: vibFader
            width: faderRow.colW
            s: root.s
            icon: "monitor"
            subLabel: "Vibrance"
            subPersistent: false
            focused: root.focusIndex === root.faderCount - 3
            value: Devices.vibrance / 100
            valueLabel: Devices.vibrance + "%"
            onMoved: (v) => Devices.vibrance = Math.round(v * 100)
            onCommitted: (v) => { root.pendingVibrance = v * 100; vibDebounce.restart(); }
        }
        VFader {
            id: volFader
            width: faderRow.colW
            s: root.s
            icon: "speaker"
            subLabel: "Volume"
            subPersistent: false
            focused: root.focusIndex === root.faderCount - 2
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            valueLabel: Math.round((root.sink && root.sink.audio ? root.sink.audio.volume : 0) * 100) + "%"
            onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v; }
        }
        VFader {
            id: micFader
            width: faderRow.colW
            s: root.s
            icon: (root.source && root.source.audio && root.source.audio.muted) ? "mic-off" : "mic"
            subLabel: "Microphone"
            subPersistent: false
            focused: root.focusIndex === root.faderCount - 1
            value: root.source && root.source.audio ? root.source.audio.volume : 0
            valueLabel: (root.source && root.source.audio && root.source.audio.muted)
                ? "off"
                : (Math.round((root.source && root.source.audio ? root.source.audio.volume : 0) * 100) + "%")
            onMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v; }

            MouseArea {
                id: micMute
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 24 * root.s
                height: 22 * root.s
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; }
            }
        }
    }

    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0 && root.stepFocused(notches * 5))
                acc -= notches;
            event.accepted = true;
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.pill.surfaces
import "../../../utils/format.js" as Fmt

/**
 * 録 RECORD surface: drives gpu-screen-recorder through the ScreenRec singleton,
 * built as a flat washi "capture card". The header carries the kanji, label and
 * a status slot (Idle / pulsing dot + elapsed m:ss / Get ready). A tappable
 * config stage (recorder/ConfigStage.qml) shows the recording spec and folds
 * open an options drawer (Frame rate / Quality MiniSegs and a Capture-cursor
 * toggle). A full-width flame action bar (recorder/RecordBar.qml) starts, counts
 * down and stops the capture; two compact audio rows expose
 * the captured mic and desktop levels on flat-tick faders; a horizontal filmstrip
 * lists recent clips.
 *
 * The flow is chill: the user picks WHAT to record at leisure with nothing
 * recording yet, THEN a pre-roll countdown runs, THEN gsr records. Pressing while
 * idle opens an in-surface source chooser with two choices — Screen and Window /
 * Region. Screen resolves to a monitor (a sub-chooser of the connected screens
 * when more than one) via ScreenRec.prepareScreen; Window / Region feeds the
 * Hyprland client rectangles to slurp (prepareWindow) so a click snaps to a
 * window and a drag draws a freeform region, captured as a static rectangle.
 * Either resolves to ScreenRec.targetReady(token), at which point the
 * Flags.recordCountdown countdown runs (the bar fills over it, tap cancels) and
 * then gsr starts. Zero countdown starts at once; a cancelled pick aborts
 * cleanly. Pressing while recording stops and saves. Audio faders drive the
 * default Pipewire sink and source levels, matching what gsr captures via its
 * default_output / default_input aliases.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 16
    mRight: 16
    mBottom: 13

    implicitHeight: content.implicitHeight

    property string screenName: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property int countdown: ScreenRec.countdown
    readonly property bool counting: ScreenRec.counting
    property int elapsed: 0

    property bool drawerOpen: false

    /** Chooser state, owned by the RecordBar and mirrored for the shell. */
    readonly property bool chooserOpen: recBar.chooserOpen

    /**
     * Audio-fader keyboard focus index: 0 mic, 1 desktop, -1 none. Only an
     * enabled (toggled-on) fader accepts the focus; the host's hover and arrow
     * keys set it.
     */
    property int faderFocus: -1

    readonly property point recPoint: {
        void root.width;
        void root.height;
        return recBar.recDot.mapToItem(root, recBar.recDot.width / 2, recBar.recDot.height / 2);
    }

    ameForm: (open && !root.counting && !ScreenRec.recording) ? "dock" : "off"
    amePoint: recPoint

    readonly property string qualityLabel: {
        var q = ScreenRec.quality;
        return q.charAt(0).toUpperCase() + q.slice(1);
    }

    readonly property string stageTitle: ScreenRec.recording ? "Recording" : "Screen recorder"

    readonly property string stageSpec: ScreenRec.fps + " fps · " + root.qualityLabel
        + (ScreenRec.usingFallback ? " · ffmpeg" : "")

    /** Deletes one clip file (argv form, no shell), then re-reads the strip. */
    Process {
        id: rmClipProc
        onExited: ScreenRec.refreshRecent()
    }

    function press() {
        if (ScreenRec.recording) {
            ScreenRec.stop();
            return;
        }
        if (counting) {
            ScreenRec.cancel();
            return;
        }
        recBar.toggleChooser();
    }

    /**
     * A source tile was picked in the chooser. Screen with several monitors opens
     * the monitor sub-chooser; otherwise each source kicks off its resolver
     * (which counts down once the target is ready), then the chooser closes.
     */
    function chooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                recBar.openMonitorChooser();
                return;
            }
            ScreenRec.prepareScreen(root.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        recBar.closeChoosers();
    }

    function pickMonitor(name) {
        recBar.closeChoosers();
        ScreenRec.prepareScreen(name);
    }

    /**
     * Thin forwards to the RecordBar's chooser; Nav routes the recorder
     * chooser keys through these (see recorder/RecordBar.qml).
     */
    function chooserMove(dir) { return recBar.chooserMove(dir); }
    function chooserActivate() { return recBar.chooserActivate(); }
    function chooserBack() { return recBar.chooserBack(); }

    /**
     * Step the focused audio fader by `deltaPct`; returns true when an enabled
     * fader consumed it. Mirrors the mixer's stepFocused so the host can route
     * scroll-wheel and arrow keys here.
     */
    function stepFocused(deltaPct) {
        if (faderFocus === 0 && ScreenRec.micOn && root.source && root.source.audio) {
            root.source.audio.volume = Math.max(0, Math.min(1, root.source.audio.volume + deltaPct / 100));
            return true;
        }
        if (faderFocus === 1 && ScreenRec.desktopOn && root.sink && root.sink.audio) {
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + deltaPct / 100));
            return true;
        }
        return false;
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(Boolean)
    }

    onActiveChanged: {
        ScreenRec.recorderOpen = active;
        if (active) {
            ScreenRec.refreshRecent();
            faderFocus = -1;
            drawerOpen = false;
        }
        recBar.reset(active);
    }

    Timer {
        id: elapsedTimer
        interval: 1000
        repeat: true
        running: ScreenRec.recording
        onTriggered: root.elapsed += 1
    }

    Connections {
        target: ScreenRec
        function onRecordingChanged() {
            if (ScreenRec.recording) {
                root.elapsed = 0;
                root.drawerOpen = false;
                recBar.closeChoosers();
            }
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "録"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "RECORD"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.8 * root.s
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ScreenRec.recording
                    width: 7 * root.s
                    height: 7 * root.s
                    radius: width / 2
                    color: Theme.verm
                    SequentialAnimation on opacity {
                        running: ScreenRec.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ScreenRec.recording ? Fmt.fmtTime(root.elapsed)
                        : (root.counting ? "GET READY" : "IDLE")
                    color: ScreenRec.recording ? Theme.vermLit : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * root.s
                    font.features: { "tnum": 1 }
                }
            }
        }

        Item { width: 1; height: 13 * root.s }

        ConfigStage {
            s: root.s
            drawerOpen: root.drawerOpen
            chooserOpen: root.chooserOpen
            counting: root.counting
            recording: ScreenRec.recording
            title: root.stageTitle
            spec: root.stageSpec
            onToggleRequested: root.drawerOpen = !root.drawerOpen
        }

        Item { width: 1; height: 13 * root.s }

        RecordBar {
            id: recBar
            s: root.s
            counting: root.counting
            countdown: root.countdown
            recording: ScreenRec.recording
            monitors: ScreenRec.monitors
            fallback: ScreenRec.usingFallback
            fallbackNote: ScreenRec.backendNote
            onPressRequested: root.press()
            onSourcePicked: (kind) => root.chooseSource(kind)
            onMonitorPicked: (name) => root.pickMonitor(name)
        }

        Item { width: 1; height: 13 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 11 * root.s }

        AudioFaders {
            s: root.s
            faderFocus: root.faderFocus
            onStepFocused: (delta) => root.stepFocused(delta)
        }

        Item { width: 1; height: 11 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 11 * root.s }

        SaveRow {
            s: root.s
        }

        Item { width: 1; height: 11 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 12 * root.s }

        ClipList {
            s: root.s
            surface: root
        }
    }
}

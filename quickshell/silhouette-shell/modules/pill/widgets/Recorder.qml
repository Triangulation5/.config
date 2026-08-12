pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.controlcenter
import qs.modules.settings
import qs.components.animation
import qs.components.controls
import qs.components.icons
import qs.modules.pill.surfaces
import "../../../utils/format.js" as Fmt

/**
 * 録 RECORD surface: drives gpu-screen-recorder through the ScreenRec singleton,
 * built as a flat washi "capture card". The header carries the kanji, label and
 * a status slot (Idle / pulsing dot + elapsed m:ss / Get ready). A tappable
 * config stage shows the recording spec and folds open an options drawer (Frame
 * rate / Quality MiniSegs and a Capture-cursor toggle). A full-width flame action
 * bar starts, counts down and stops the capture; two compact audio rows expose
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
    property bool chooserOpen: false
    property bool screenChooserOpen: false

    /**
     * Audio-fader keyboard focus index: 0 mic, 1 desktop, -1 none. Only an
     * enabled (toggled-on) fader accepts the focus; the host's hover and arrow
     * keys set it.
     */
    property int faderFocus: -1

    readonly property point recPoint: {
        void root.width;
        void root.height;
        return recDot.mapToItem(root, recDot.width / 2, recDot.height / 2);
    }

    ameForm: (open && !root.counting && !ScreenRec.recording) ? "dock" : "off"
    amePoint: recPoint

    readonly property string qualityLabel: {
        var q = ScreenRec.quality;
        return q.charAt(0).toUpperCase() + q.slice(1);
    }

    readonly property string stageTitle: ScreenRec.recording ? "Recording" : "Screen recorder"

    readonly property string stageSpec: ScreenRec.fps + " fps · " + root.qualityLabel

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
        if (chooserOpen) {
            chooserOpen = false;
            screenChooserOpen = false;
            return;
        }
        chooserOpen = true;
        screenChooserOpen = false;
    }

    /**
     * A source tile was picked in the chooser. Screen with several monitors opens
     * the monitor sub-chooser; otherwise each source kicks off its resolver
     * (which counts down once the target is ready), then the chooser closes.
     */
    function chooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                screenChooserOpen = true;
                return;
            }
            ScreenRec.prepareScreen(root.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        chooserOpen = false;
        screenChooserOpen = false;
    }

    function pickMonitor(name) {
        chooserOpen = false;
        screenChooserOpen = false;
        ScreenRec.prepareScreen(name);
    }

    /**
     * Keyboard focus inside the inline source chooser: 0 = Screen, 1 = Window /
     * Region; once the monitor sub-chooser is open it walks the monitor tiles
     * instead. Returns true when a chooser consumed the move.
     */
    property int chooserFocus: -1
    property int monFocus: -1
    readonly property int monCount: ScreenRec.monitors.length

    function chooserMove(dir) {
        if (!root.chooserOpen)
            return false;
        if (root.screenChooserOpen) {
            if (monCount === 0)
                return false;
            if (monFocus < 0 || monFocus >= monCount)
                monFocus = 0;
            monFocus = (monFocus + dir + monCount) % monCount;
            monList.positionViewAtIndex(monFocus, ListView.Contain);
            return true;
        }
        if (chooserFocus < 0 || chooserFocus > 1)
            chooserFocus = 0;
        chooserFocus = (chooserFocus + dir + 2) % 2;
        return true;
    }

    /** Return on the inline source chooser: pick the focused tile. */
    function chooserActivate() {
        if (!root.chooserOpen)
            return false;
        if (root.screenChooserOpen) {
            if (monFocus >= 0 && monFocus < monCount)
                root.pickMonitor(ScreenRec.monitors[monFocus].name);
            return true;
        }
        var idx = chooserFocus < 0 ? 0 : chooserFocus;
        root.chooseSource(idx === 0 ? "screen" : "window");
        return true;
    }

    /**
     * Backspace on the inline source chooser: the monitor sub-chooser returns
     * to the source tiles, the source tiles close the chooser. Returns true
     * when a chooser consumed it.
     */
    function chooserBack() {
        if (!root.chooserOpen)
            return false;
        if (root.screenChooserOpen) {
            root.screenChooserOpen = false;
            return true;
        }
        root.chooserOpen = false;
        return true;
    }

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
            chooserFocus = 0;
            monFocus = 0;
            drawerOpen = false;
            chooserOpen = false;
            screenChooserOpen = false;
        } else {
            chooserFocus = -1;
            monFocus = -1;
            chooserOpen = false;
            screenChooserOpen = false;
        }
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
                root.chooserOpen = false;
                root.screenChooserOpen = false;
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

        Item {
            id: stageGroup
            width: parent.width
            height: stage.height + drawer.height

            Rectangle {
                id: stage
                property bool pressActive: false
                width: parent.width
                height: 76 * root.s
                radius: 13 * root.s
                color: Theme.cardBot
                transformOrigin: Item.Center
                scale: pressActive ? 0.984 : 1
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.radius + 1
                    visible: root.drawerOpen
                    color: Theme.cardBot
                }

                Repeater {
                    model: [
                        { hx: false, vy: false },
                        { hx: true, vy: false },
                        { hx: false, vy: true },
                        { hx: true, vy: true }
                    ]

                    Item {
                        id: corner
                        required property var modelData
                        readonly property color arm: Qt.alpha(Theme.vermLit, 0.5)
                        width: 14 * root.s
                        height: 14 * root.s
                        opacity: root.counting || ScreenRec.recording
                            || (modelData.vy && root.drawerOpen) ? 0 : 1
                        x: modelData.hx ? stage.width - width - 11 * root.s : 11 * root.s
                        y: modelData.vy ? stage.height - height - 11 * root.s : 11 * root.s
                        rotation: modelData.hx ? (modelData.vy ? 180 : 90) : (modelData.vy ? 270 : 0)
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: corner.arm
                                strokeWidth: 2 * root.s
                                fillColor: "transparent"
                                capStyle: ShapePath.FlatCap
                                joinStyle: ShapePath.RoundJoin
                                startX: 1 * root.s
                                startY: 13 * root.s
                                PathLine { x: 1 * root.s; y: 5.5 * root.s }
                                PathQuad { controlX: 1 * root.s; controlY: 1 * root.s; x: 5.5 * root.s; y: 1 * root.s }
                                PathLine { x: 13 * root.s; y: 1 * root.s }
                            }
                        }
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 22 * root.s
                    anchors.right: chevron.left
                    anchors.rightMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5 * root.s

                    Text {
                        width: parent.width
                        text: root.stageTitle
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: 6 * root.s

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5 * root.s
                            height: 5 * root.s
                            radius: width / 2
                            color: ScreenRec.recording ? Theme.verm : Theme.vermDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.stageSpec
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            font.features: { "tnum": 1 }
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    visible: ScreenRec.recording
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * root.s
                    anchors.top: parent.top
                    anchors.topMargin: 13 * root.s
                    spacing: 5 * root.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 * root.s
                        height: 6 * root.s
                        radius: width / 2
                        color: Theme.verm
                    }
                    Text {
                        text: "REC"
                        color: Theme.vermLit
                        font.family: Theme.font
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.2 * root.s
                    }
                }

                GlyphIcon {
                    id: chevron
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13 * root.s
                    height: 13 * root.s
                    name: "chevron-down"
                    color: root.drawerOpen ? Theme.vermLit : Theme.faint
                    stroke: 2.2
                    rotation: root.drawerOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: stage.pressActive = true
                    onReleased: stage.pressActive = false
                    onCanceled: stage.pressActive = false
                    onClicked: if (!ScreenRec.recording && !root.counting && !root.chooserOpen)
                        root.drawerOpen = !root.drawerOpen
                }
            }

            Item {
                id: drawer
                anchors.top: stage.bottom
                width: parent.width
                height: root.drawerOpen ? drawerCol.implicitHeight : 0
                clip: true
                visible: height > 0
                Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Rectangle {
                    anchors.fill: parent
                    radius: 13 * root.s
                    color: Theme.cardBot
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 13 * root.s + 1
                    color: Theme.cardBot
                }

                Column {
                    id: drawerCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 18 * root.s
                    anchors.rightMargin: 16 * root.s
                    topPadding: 2 * root.s
                    bottomPadding: 10 * root.s

                    ORow {
                        s: root.s
                        name: "Frame rate"
                        first: true
                        MiniSeg {
                            s: root.s
                            options: [
                                { label: "30", value: 30 },
                                { label: "60", value: 60 },
                                { label: "120", value: 120 },
                                { label: "144", value: 144 }
                            ]
                            value: ScreenRec.fps
                            onPicked: (v) => ScreenRec.fps = v
                        }
                    }
                    ORow {
                        s: root.s
                        name: "Quality"
                        MiniSeg {
                            s: root.s
                            options: [
                                { label: "Med", value: "medium" },
                                { label: "High", value: "high" },
                                { label: "Ultra", value: "ultra" },
                                { label: "Loss", value: "lossless" }
                            ]
                            value: ScreenRec.quality
                            onPicked: (v) => ScreenRec.quality = v
                        }
                    }
                    ORow {
                        s: root.s
                        name: "Capture cursor"
                        LinkToggle {
                            s: root.s
                            on: ScreenRec.captureCursor
                            onToggled: ScreenRec.captureCursor = !ScreenRec.captureCursor
                        }
                    }
                    ORow {
                        s: root.s
                        name: "Countdown"
                        MiniSeg {
                            s: root.s
                            options: [
                                { label: "Off", value: 0 },
                                { label: "3s", value: 3 },
                                { label: "5s", value: 5 },
                                { label: "10s", value: 10 }
                            ]
                            value: Flags.recordCountdown
                            onPicked: (v) => Flags.recordCountdown = v
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 13 * root.s }

        Item {
            id: actionGroup
            width: parent.width
            height: 44 * root.s

            Rectangle {
                id: actionBar
                anchors.fill: parent
                radius: 14 * root.s
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: ScreenRec.recording ? Qt.alpha(Theme.verm, 0.34) : Qt.alpha(Theme.verm, 0.2) }
                    GradientStop { position: 1.0; color: ScreenRec.recording ? Qt.alpha(Theme.verm, 0.16) : Qt.alpha(Theme.flameGlow, 0.09) }
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: actionBar.radius
                    color: "transparent"

                    Rectangle {
                        id: cdFill
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: root.counting
                        width: parent.width * (root.counting && Flags.recordCountdown > 0
                            ? (Flags.recordCountdown - root.countdown + 1) / Flags.recordCountdown : 0)
                        color: Qt.alpha(Theme.vermLit, 0.18)
                        Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                    }
                }

                Rectangle {
                    id: recDot
                    anchors.left: parent.left
                    anchors.leftMargin: 18 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.counting && !ScreenRec.recording
                    width: 17 * root.s
                    height: 17 * root.s
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.vermLit }
                        GradientStop { position: 1.0; color: Theme.vermDeep }
                    }
                }

                Rectangle {
                    id: stopSquare
                    anchors.left: parent.left
                    anchors.leftMargin: 18 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ScreenRec.recording
                    width: 15 * root.s
                    height: 15 * root.s
                    radius: 4 * root.s
                    color: Theme.vermLit
                    SequentialAnimation on scale {
                        running: ScreenRec.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.08; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    id: cdNumber
                    anchors.left: parent.left
                    anchors.leftMargin: 20 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.counting
                    text: root.countdown
                    color: Theme.flameGlow
                    font.family: Theme.font
                    font.pixelSize: 24 * root.s
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.counting ? 46 * root.s : 47 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: ScreenRec.recording ? "Stop recording"
                        : (root.counting ? "Starting…" : "Start recording")
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.5 * root.s
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.counting ? "tap to cancel" : "tap"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.press()
                }
            }

            Rectangle {
                id: chooser
                anchors.fill: parent
                visible: root.chooserOpen
                radius: 14 * root.s
                color: Theme.cardBot
                border.width: 1
                border.color: Theme.border

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.chooserOpen = false
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 6 * root.s
                    spacing: 6 * root.s

                    Repeater {
                        model: [
                            { kind: "screen", label: "Screen", glyph: "monitor" },
                            { kind: "window", label: "Window / Region", glyph: "video" }
                        ]

                        Rectangle {
                            id: srcTile
                            required property var modelData
                            required property int index
                            readonly property bool focused: !root.screenChooserOpen && root.chooserFocus === index
                            width: (chooser.width - 12 * root.s - 6 * root.s) / 2
                            height: parent.height
                            radius: 9 * root.s
                            color: srcArea.containsMouse || srcTile.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                            border.width: 1
                            border.color: srcArea.containsMouse || srcTile.focused ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            HoverHandler {
                                onHoveredChanged: if (hovered) root.chooserFocus = index
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8 * root.s

                                GlyphIcon {
                                    width: 16 * root.s
                                    height: 16 * root.s
                                    name: srcTile.modelData.glyph
                                    color: srcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                                    stroke: 1.7
                                }
                                Text {
                                    height: 16 * root.s
                                    verticalAlignment: Text.AlignVCenter
                                    text: srcTile.modelData.label
                                    color: srcArea.containsMouse ? Theme.cream : Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                id: srcArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.chooseSource(srcTile.modelData.kind)
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: screenChooser
                anchors.fill: parent
                visible: root.screenChooserOpen
                radius: 14 * root.s
                color: Theme.cardBot
                border.width: 1
                border.color: Theme.border

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.screenChooserOpen = false
                }

                ListView {
                    id: monList
                    anchors.fill: parent
                    anchors.margins: 6 * root.s
                    anchors.rightMargin: 22 * root.s
                    orientation: ListView.Horizontal
                    spacing: 6 * root.s
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScreenRec.monitors

                    delegate: MonTile {
                        surface: root
                        modelData: modelData
                        index: index
                    }
                }

                WheelScroller {
                    flick: monList
                    s: root.s
                    anchors.fill: monList
                }

                GlyphIcon {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 7 * root.s
                    width: 12 * root.s
                    height: 12 * root.s
                    name: "chevron-left"
                    color: backArea.containsMouse ? Theme.cream : Theme.faint
                    stroke: 2

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        anchors.margins: -7 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.screenChooserOpen = false;
                            root.chooserOpen = true;
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 13 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 11 * root.s }

        AudioRow {
            s: root.s
            faderFocus: root.faderFocus
            onStepFocused: (delta) => root.stepFocused(delta)
            glyph: "mic"
            name: "Microphone"
            on: ScreenRec.micOn
            faderIndex: 0
            level: root.source && root.source.audio ? root.source.audio.volume : 0
            onFaderMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v; }

            MouseArea {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * root.s
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.micOn = !ScreenRec.micOn
            }
        }

        AudioRow {
            s: root.s
            faderFocus: root.faderFocus
            onStepFocused: (delta) => root.stepFocused(delta)
            glyph: "speaker"
            name: "Desktop"
            on: ScreenRec.desktopOn
            faderIndex: 1
            level: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onFaderMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v; }

            MouseArea {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * root.s
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.desktopOn = !ScreenRec.desktopOn
            }
        }

        Item { width: 1; height: 11 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 11 * root.s }

        /**
         * Save-location row: a tracked "SAVE TO" label, the output directory
         * collapsed to `~` and elided to fit, and Change / Open affordances that
         * drive the native picker and file manager.
         */
        Item {
            id: pathRow
            width: parent.width
            height: 18 * root.s

            readonly property string shownDir: {
                var d = ScreenRec.outDir;
                var h = ScreenRec.home;
                return h.length > 0 && d.indexOf(h) === 0 ? "~" + d.slice(h.length) : d;
            }

            Text {
                id: pathLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SAVE TO"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }

            Item {
                id: pathActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: changeTxt.width + 9 * root.s + openTxt.width

                Text {
                    id: changeTxt
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CHANGE"
                    color: changeArea.containsMouse ? Theme.flameGlow : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s

                    MouseArea {
                        id: changeArea
                        anchors.fill: parent
                        anchors.margins: -5 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRec.pickDir()
                    }
                }
                Text {
                    id: openTxt
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OPEN"
                    color: openArea.containsMouse ? Theme.flameGlow : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s

                    MouseArea {
                        id: openArea
                        anchors.fill: parent
                        anchors.margins: -5 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRec.openDir()
                    }
                }
            }

            Text {
                id: pathText
                anchors.left: pathLabel.right
                anchors.leftMargin: 10 * root.s
                anchors.right: pathActions.left
                anchors.rightMargin: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: pathRow.shownDir
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }

        Item { width: 1; height: 11 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 12 * root.s }

        Item {
            width: parent.width
            height: 16 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * root.s

                Text {
                    visible: Flags.showGlyphs
                    height: 16 * root.s
                    verticalAlignment: Text.AlignVCenter
                    text: "録"
                    color: Theme.subtle
                    font.family: Theme.fontJp
                    font.pixelSize: 11 * root.s
                }
                Text {
                    height: 16 * root.s
                    verticalAlignment: Text.AlignVCenter
                    text: "RECENT · " + ScreenRec.recentCount
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * root.s
                }
            }

            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: clearTxt.width + (Flags.showGlyphs ? clearKanji.width + 5 * root.s : 0)
                visible: ScreenRec.recentCount > 0

                Text {
                    id: clearKanji
                    anchors.right: clearTxt.left
                    anchors.rightMargin: 5 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "払"
                    color: clearArea.containsMouse ? Theme.flameGlow : Theme.vermDeep
                    font.family: Theme.fontJp
                    font.pixelSize: 11 * root.s
                }
                Text {
                    id: clearTxt
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLEAR"
                    color: clearArea.containsMouse ? Theme.flameGlow : Theme.vermDeep
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s
                }

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ScreenRec.clearRecent()
                }
            }
        }

        Item { width: 1; height: 9 * root.s }

        Item {
            width: parent.width
            height: 64 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: ScreenRec.recentCount === 0
                text: "No recordings yet"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }

            ListView {
                id: filmstrip
                anchors.fill: parent
                visible: ScreenRec.recentCount > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: 9 * root.s
                boundsBehavior: Flickable.StopAtBounds
                model: ScreenRec.recent

                delegate: ClipRow {
                    surface: root
                    modelData: modelData
                    index: index
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: (event) => {
                    var max = Math.max(0, filmstrip.contentWidth - filmstrip.width);
                    filmstrip.contentX = Math.max(0, Math.min(max, filmstrip.contentX - event.angleDelta.y / 120 * 48 * root.s));
                    event.accepted = true;
                }
            }
        }
    }
}

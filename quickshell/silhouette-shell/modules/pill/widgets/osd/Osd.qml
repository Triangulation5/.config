import QtQuick
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.pill.widgets

/**
 * Pill OSD face. Morphs the pill open for a flash of volume, brightness, battery,
 * now-playing, workspace, or record status, throttled and cooled so preview churn
 * can't spam it; the track flash holds open until a late cover decodes.
 *
 * This root owns the flash state machine and the per-face wiring; each face is a
 * small component under osd/ (OsdLevelFace for the bar-style volume, brightness
 * and battery states; OsdMic, OsdTrack, OsdWorkspace and OsdRecord for the
 * others) that renders one state from props.
 */

Item {
    id: root

    property real s: 1.1
    property string screenName: ""
    property bool suppressed: false
    property bool expanded: false
    property bool flashing: false
    property string kind: "volume"
    property bool armed: false
    property bool dirty: false
    property bool cooling: false
    property int holdExtends: 0

    /**
     * The player the current flash speaks for. Normally the active source, but an
     * announce can point it at another player that just started, so a video over
     * your music still gets its own flash without stealing the surface.
     */
    property var pendingSubject: null
    readonly property var subject: pendingSubject ? pendingSubject : Players.active
    readonly property bool subjectHas: subject !== null
    readonly property bool subjectPlaying: subjectHas && subject.isPlaying
    readonly property string subjectTitle: subjectHas ? Players.refineTitle(subject, subject.trackTitle || Players.labelOf(subject)) : ""
    readonly property string subjectArtist: subjectHas ? Theme.joinArtists(subject.trackArtists, subject.trackArtist) : ""
    readonly property string subjectIcon: subjectHas ? Players.appIconFor(subject) : ""

    /** Subject art, live so a cover that lands a beat after the title still resolves; the key forces a reload when a browser reuses one file path. */
    readonly property string liveArt: {
        if (!subjectHas)
            return "";
        var u = Players.artUrlFor(subject);
        if (!u)
            return "";
        return u.indexOf("file:") === 0 ? u + "#" + Players.keyFor(subject) : u;
    }

    readonly property real brightness: Backlight.brightness
    property bool recordStarted: false

    /** Flame gradient shared by the brightness and battery level fills. */
    readonly property Gradient flameGradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Theme.vermDeep }
        GradientStop { position: 1.0; color: Theme.flameGlow }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    readonly property real desiredW: kind === "workspace" ? Math.max(120 * s, wsFace.indicatorWidth + 40 * s)
        : (kind === "track" ? 344 * s : (kind === "record" ? 256 * s : (kind === "mic" ? 220 * s : 248 * s)))
    readonly property real desiredH: kind === "track" ? 64 * s : 44 * s

    /**
     * Active workspace name on this monitor. Any switch (Super+arrow,
     * Super+wheel, clicking a dot) changes it, so flashing the workspace OSD
     * here briefly morphs the pill open to show where you landed. The arm timer
     * swallows the initial populate, so login doesn't flash. Skipped while the
     * pill is expanded: the hover/surface pill already shows the live dots with
     * the active one marked, so the OSD would only be a redundant morph.
     */
    readonly property string activeWsName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }
    onActiveWsNameChanged: if (activeWsName.length > 0 && !expanded) flash("workspace");

    /**
     * Leading-edge throttle. The first change flashes at once so a real track
     * switch feels instant, then the cooldown mutes the burst that hovering the
     * YouTube grid throws off. Anything that lands during the cooldown, or while
     * the OSD is suppressed (a surface open, the pill pinned), stays `dirty` and
     * fires when the gate opens, so the stashed-player flash still replays.
     */
    function tryShow() {
        if (cooling)
            return;
        if (flash("track")) {
            dirty = false;
            cooling = true;
            cooldownTimer.restart();
        }
    }

    /**
     * Every pill carries its own Osd but the volume/track/battery signals are
     * global, so without this gate one keypress flashes every monitor at once.
     * Workspace flashes skip it: those are already keyed to this screen's own
     * active workspace.
     */
    readonly property bool onFocusedMonitor: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === screenName

    function flash(which) {
        if (!armed || suppressed)
            return false;
        if (which !== "workspace" && !onFocusedMonitor)
            return false;
        if (which === "track" && flashing && (kind === "volume" || kind === "brightness"))
            return false;
        if (which === "track")
            holdExtends = 0;
        kind = which;
        flashing = true;
        hideTimer.interval = (which === "battery" || which === "record") ? 2000 : 1800;
        hideTimer.restart();
        return true;
    }

    onSuppressedChanged: {
        if (suppressed) {
            hideTimer.stop();
            flashing = false;
        } else if (dirty) {
            tryShow();
        }
    }

    /** A track announce that lost to live hardware feedback replays once the bar clears. */
    onFlashingChanged: if (!flashing && dirty) tryShow()

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: cooldownTimer
        interval: 1500
        onTriggered: {
            root.cooling = false;
            if (root.dirty)
                root.tryShow();
        }
    }

    /**
     * Hold a track flash open until its cover decodes, so a cold remote thumbnail
     * that arrives after the base window still gets seen. Capped so a dead art url
     * never pins the OSD.
     */
    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: {
            if (root.kind === "track" && !trackFace.coverReady && root.liveArt.length > 0 && root.holdExtends < 5) {
                root.holdExtends++;
                hideTimer.interval = 350;
                hideTimer.restart();
            } else {
                root.flashing = false;
            }
        }
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(Boolean)
    }

    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onVolumesChanged() { root.flash("volume"); }
        function onMutedChanged() { root.flash("volume"); }
    }

    Connections {
        target: root.source && root.source.audio ? root.source.audio : null
        function onMutedChanged() { root.flash("mic"); }
    }

    Connections {
        target: Players
        function onAnnounce(player) {
            root.pendingSubject = player;
            root.dirty = true;
            root.tryShow();
        }
    }

    Connections {
        target: Battery
        enabled: Battery.present
        function onChargingChanged() {
            if (Battery.charging)
                root.flash("battery");
        }
    }

    Connections {
        target: ScreenRec
        function onRecordingChanged() {
            root.recordStarted = ScreenRec.recording;
            root.flash("record");
        }
    }

    Connections {
        target: Backlight
        function onChanged() {
            root.flash("brightness");
        }
    }

    OsdLevelFace {
        anchors.fill: parent
        s: root.s
        active: root.kind === "volume"
        glyph: root.muted ? "speaker-off" : "speaker-level"
        glyphProgress: root.volume
        glyphColor: root.muted ? Theme.dim : Theme.iconDim
        pctText: Math.round(root.volume * 100) + "%"
        pctColor: root.muted ? Theme.dim : Theme.cream
        fill: root.volume
        fillColor: root.muted ? Theme.vermDim : Theme.vermLit
    }

    OsdMic {
        anchors.fill: parent
        s: root.s
        active: root.kind === "mic"
        micMuted: root.micMuted
    }

    OsdTrack {
        id: trackFace
        anchors.fill: parent
        s: root.s
        active: root.kind === "track"
        art: root.liveArt
        icon: root.subjectIcon
        title: root.subjectTitle
        artist: root.subjectArtist
        playing: root.subjectPlaying
        onArtReady: if (root.kind === "track" && root.flashing) {
            hideTimer.interval = 1300;
            hideTimer.restart();
        }
    }

    OsdLevelFace {
        anchors.fill: parent
        s: root.s
        active: root.kind === "brightness"
        glyph: "sun-level"
        glyphProgress: root.brightness
        pctText: Math.round(root.brightness * 100) + "%"
        fill: root.brightness
        fillGradient: root.flameGradient
    }

    OsdLevelFace {
        anchors.fill: parent
        s: root.s
        active: root.kind === "battery"
        glyph: "bolt"
        glyphColor: Theme.flameGlow
        pctText: Battery.pct + "%"
        pctWidth: 40 * root.s
        fill: Battery.frac
        fillGradient: root.flameGradient
        shimmerOn: Battery.charging
    }

    OsdWorkspace {
        id: wsFace
        anchors.fill: parent
        s: root.s
        screenName: root.screenName
        active: root.kind === "workspace"
    }

    OsdRecord {
        anchors.fill: parent
        s: root.s
        active: root.kind === "record"
        recordStarted: root.recordStarted
    }
}

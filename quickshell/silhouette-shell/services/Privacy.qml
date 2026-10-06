pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Privacy: is anything capturing the user right now, and if so, what.
 *
 * Three sources, and they are not equal in kind:
 *
 *   - **Screen.** `ScreenRec.recording` is the shell's own recorder and already
 *     authoritative — it is polled from the real process, so an externally
 *     started recorder is covered too. Read directly, never polled here: the
 *     dot is exact the instant a recording starts.
 *   - **Audio in, audio out and camera.** PipeWire, through `wpctl status`.
 *     There is no Quickshell service for capture state, and inventing one is
 *     out of scope; this is a slow read of the one tool that already answers
 *     the question. "Audio in" is deliberately not named "microphone": the
 *     arrow PipeWire reports is a direction, so a screen share that carries
 *     system sound reads as exactly the same thing as a mic does. See
 *     `wantAudioIn`.
 *
 * The rules this file exists to enforce are in the TODO item that asked for it,
 * and they are worth restating because both are easy to get backwards:
 *
 *   1. **Fail visible.** A probe that cannot run is not the same as a clean
 *      result, and it is emphatically not "nothing is capturing". `wpctl`
 *      missing, a non-zero exit, a hang, or output that parses to nothing while
 *      claiming success all land in `unknown` — which *shows* the dot. The last
 *      good answer is kept alongside so the user is not left with a bare
 *      question mark, but the state never quietly reverts to idle.
 *   2. **Say what is capturing.** "Something is using your microphone" is
 *      weaker than "Firefox is using your microphone", and the application name
 *      is right there in the stream header for nearly every real stream. The *     names are collected and kept in `audioInUsers` / `cameraUsers` /
 *     `audioOutUsers`; nothing prints them yet, because the rest surface is 38px
 *      tall and holds a mark and nothing else. A surface with room for words can
 *      read them off directly.
 *
 * Which of those sources is worth a dot is the user's decision, so each one has
 * its own switch and there is a master above them (`enabled`). A switched-off
 * source is not probed at all where that is possible: audio in, camera and
 * audio out all off leaves a screen-only indicator that costs no process spawn.
 *
 * Two things this deliberately does not do, because both were specified:
 *
 *   - It does not infer anything from the notification server. A notification
 *     that *mentions* a meeting is not evidence that a camera is running, and
 *     coupling the two would make the indicator wrong in both directions.
 *   - It does not guess at the cost of being late. Each tick is a process
 *     spawn, so the cadence is `Flags.privacyPollMs` (1 s) rather than
 *     something tighter, and `interval` below floors it at 500 ms so a
 *     hand-edited flag cannot spin it. At 12.9 ms a probe, that is the price
 *     of a dot that is there the instant you start talking.
 *   - It does not carry a label. The dot draws on the rest surface alone, and
 *     a name needs a surface with room for one; see `PrivacyDot`.
 *
 * A transient parse failure trips rule 1 rather than clearing the dot, so the
 * indicator can blink to amber and settle back, but it cannot blink to nothing.
 *
 * Screen capture is instant and independent of the probe, so the dot for it
 * never waits on PipeWire.
 *
 * ## What `wpctl status` actually looks like
 *
 * The shape below was read off a real machine (`wpctl status`, PipeWire 1.6.9)
 * and cross-checked against a live recording, because the obvious reading of it
 * is wrong in the most consequential direction available:
 *
 * ```
 * Audio
 *  ├─ Sources:
 *  │  *   49. Built-in Audio Analog Stereo        [vol: 0.70]
 *  │  
 *  └─ Streams:
 *         80. pw-record
 *              79. input_FR        < ALC257 Analog:capture_FR   [active]
 *              81. input_FL        < ALC257 Analog:capture_FL   [active]
 * ```
 *
 * The `*` on a `Sources:` line looks like the answer and is not. That star was
 * already there with nothing recording, because a monitor being consumed marks
 * the source running; reading it as "the mic is in use" pins the indicator on,
 * permanently and wrongly. The signal is the **Streams** section, and the arrow
 * is the direction: `<` means the stream is reading from a device (capturing),
 * `>` means it is writing to one (playback). The stream header is the
 * application name, which is rule 2 delivered for free.
 *
 * Both directions are reported, separately, because what counts as worth
 * lighting a dot about is the owner's call: a camera opening is, a speaker in
 * use is not. See `wantAudioOut` for why that one ships off.
 */
Singleton {
    id: root

    /** -- what the user has switched on ------------------------------------- */

    /** Master switch. Off means the dot does not exist, and nothing is probed. */
    readonly property bool enabled: Flags.privacyDot

    /** Report a screen recording. On by default; needs no probe. */
    readonly property bool wantScreen: Flags.privacyScreen

    /**
     * Report audio *arriving* from a device. Off by default.
     *
     * Not named "microphone", because it is not one thing. The signal is a
     * PipeWire stream with `<` on its link — a device feeding a process — and a
     * microphone is only the obvious member of that set. A screen share that
     * carries system audio, an app recording a conference call, anything
     * looping a source back into itself: all identical on the wire, all
     * equally a thing drawing your sound out of the machine. One flag covers
     * them because one flag is all that can tell them apart at all.
     *
     * Off by default because of that same set, from the other end: the most
     * reliable thing holding a microphone open is a visualiser like cava,
     * which runs all session and never lets go. Left on, this row does not
     * report the interesting capture, it reports the permanent one and the dot
     * sits lit until it is switched off rather than ignored. It is the row to
     * turn on if a mic you did not start is the thing you most want caught.
     */
    readonly property bool wantAudioIn: Flags.privacyAudioIn

    /** Report a live camera. On by default. */
    readonly property bool wantCamera: Flags.privacyCam

    /**
     * Report audio *leaving* for a device — playback. Off by default, and that
     * is the interesting one: a speaker in use is not a privacy event, it is
     * somebody listening to something. Any media player, a video call, a game
     * — all of them would light a dot that means "something is playing", which
     * is noise wearing an indicator's clothes. It is here because someone may
     * well want to know, not because it belongs on by default.
     *
     * This is about *which process is sending sound*, and has nothing to do
     * with volume: the shell's mixer, the OSD and every fader are a separate
     * concern that this row neither reads nor changes.
     */
    readonly property bool wantAudioOut: Flags.privacyAudioOut

    /** -- the sources ------------------------------------------------------- */

    /** The shell's own recorder, or one started outside it. Exact, not polled. */
    readonly property bool screen: ScreenRec.recording

    /**
     * Everything the last good probe found, kept so a failure still names it.
     *
     * Replaced wholesale rather than edited in place: a plain JS object has no
     * change signal, so mutating these arrays would leave every binding reading
     * them stale. These are the writable source; everything the UI reads
     * (`state`) is derived below and stays readonly.
     */
    property var audioInUsers: ({ apps: [], devices: [] })
    property var cameraUsers: ({ apps: [], devices: [] })
    property var audioOutUsers: ({ apps: [], devices: [] })

    /** -- the one answer the UI reads ------------------------------------- */

    /**
     * `off` — the master switch is off. Nothing is shown, and nothing is probed.
     * `idle` — nothing is happening among the sources you switched on, and we
     *   know it. The dot is invisible.
     * `capture` — something is, and the dot takes the capture colour.
     * `unknown` — the check could not run or could not be read; the dot is
     *   shown in the unknown colour, because a blank dot here would be a lie.
     *
     * Each source is gated on its own switch, and a source that is switched off
     * is not merely hidden — it stops being asked about. A `capture` therefore
     * means "one of the things you asked to know about is happening", never a
     * source you turned off resurfacing.
     *
     * Screen is asked first and is deliberately not gated on `probeOk`: it
     * comes from a different, exact source, so a dead PipeWire must not be able
     * to downgrade a recording that is plainly happening.
     *
     * `unknown` needs a probe-backed source switched on to mean anything. If
     * you asked about screen only, there is no check that can fail, so there is
     * nothing to report amber.
     *
     * The one state that is not "fail visible" is `idle` before the very first
     * probe finishes, which draws nothing. That is not a failure being hidden —
     * nothing has been checked yet, and amber for the single frame the shell
     * takes to load would be noise dressed up as information. The first probe
     * to *complete*, successfully or not, settles it for good.
     */
    readonly property string state: {
        if (!root.enabled)
            return "off";
        if ((root.screen && root.wantScreen)
            || (root.wantAudioIn && audioInUsers.apps.length > 0)
            || (root.wantCamera && cameraUsers.apps.length > 0)
            || (root.wantAudioOut && audioOutUsers.apps.length > 0))
            return "capture";
        if (!probeOk) {
            if (!probed || !root.needsProbe)
                return "idle";
            return "unknown";
        }
        return "idle";
    }

    /** True when something is genuinely capturing. */
    readonly property bool capturing: state === "capture"

    /**
     * Which source is responsible for the capture state, as a key of
     * `ColorScheme.privacyTones`. Empty when nothing is capturing.
     *
     * The dot is one dot, so when several things are capturing at once it has
     * to pick one to be coloured by, and the order here is that pick:
     * camera, then screen, then audio in, then audio out. Camera first because
     * a dot that means "the camera" when it can mean it is worth more than one
     * that means "something, somewhere"; audio out last because it is the row
     * that is off unless asked for, and a dot that reports the thing you opted
     * into first reads as a bug.
     *
     * Every source switched off is skipped, so this can never name a source the
     * user turned off — a colour that reports a source nobody asked about is
     * the same bug as a lit dot for a source nobody asked about.
     */
    readonly property string source: {
        if (!root.capturing)
            return "";
        if (root.wantCamera && cameraUsers.apps.length > 0)
            return "camera";
        if (root.wantScreen && root.screen)
            return "screen";
        if (root.wantAudioIn && audioInUsers.apps.length > 0)
            return "audioIn";
        if (root.wantAudioOut && audioOutUsers.apps.length > 0)
            return "audioOut";
        return "";
    }

    /**
     * The pick this source's row is set to: a key of
     * `ColorScheme.privacySwatches`, or `"auto"` for the source's own tone.
     */
    readonly property string toneChoice: {
        if (root.source === "camera")
            return Flags.privacyToneCam;
        if (root.source === "screen")
            return Flags.privacyToneScreen;
        if (root.source === "audioIn")
            return Flags.privacyToneAudioIn;
        if (root.source === "audioOut")
            return Flags.privacyToneAudioOut;
        return "auto";
    }

    /**
     * The colour the dot takes while capturing: this source's tone, or whatever
     * the user picked for it. Amber for `unknown` is not decided here — the
     * dot asks `unknown` first, because that is a different claim.
     */
    readonly property color tone: ColorScheme.privacyTone(source, toneChoice)

    /** True when we could not find out. Deliberately never folded into idle. */
    readonly property bool unknown: state === "unknown"

    /** True when the dot should be drawn at all. */
    readonly property bool visible: state === "capture" || state === "unknown"

    /**
     * True when at least one PipeWire-backed source is switched on.
     *
     * Gates the probe outright rather than merely the dot, so turning audio in,
     * the camera and audio out all off leaves a screen-only indicator that
     * costs nothing at all — no `wpctl`, no process spawn, no cadence timer.
     */
    readonly property bool needsProbe: enabled && (wantAudioIn || wantCamera || wantAudioOut)

    /** -- the probe -------------------------------------------------------- */

    /** True once a probe has completed and parsed into something usable. */
    property bool probeOk: false

    /** True once any probe has finished, which is what makes `unknown` honest. */
    property bool probed: false

    /**
     * Cadence in ms.
     *
     * This was 10 s with a 5 s floor, on the reasoning that a capture is rare
     * and each tick is a process spawn. That reasoning was right about the cost
     * and wrong about the feeling: a capture that takes up to ten seconds to
     * appear is not an indicator, it is a post-mortem. Measured on this machine,
     * one `wpctl status` averages 12.9 ms, so a one-second cadence is about 1.3%
     * of a core and buys instant detection — an easy trade, and the one the
     * owner asked for.
     *
     * The floor stays, at 500 ms, so a hand-edited flags.json cannot turn this
     * into a spin loop.
     */
    readonly property int interval: Math.max(500, Flags.privacyPollMs)

    /** A hung `wpctl` must not hold the indicator hostage forever. */
    readonly property int timeoutMs: 6000

    /** The last body `wpctl` printed, held between the collector and onExited. */
    property string raw: ""

    Process {
        id: probe
        command: ["wpctl", "status"]

        stdout: StdioCollector {
            onStreamFinished: root.raw = this.text
        }

        onExited: function (exitCode, exitStatus) {
            watch.stop();
            /**
             * Non-zero, or killed by our own watchdog: the check did not run.
             * Rule 1 — this is `unknown`, never `idle`.
             *
             * Empty output on a clean exit falls through to `null` too, which
             * is right: a `wpctl` that prints nothing has not told us the
             * microphone is free. Relying on the collector having landed before
             * this signal therefore costs nothing if it has not.
             */
            root.apply(exitCode === 0 ? parseStatus(root.raw) : null);
            root.raw = "";
        }
    }

    Timer {
        id: watch
        interval: root.timeoutMs
        onTriggered: {
            /**
             * No usable answer inside the watchdog. `running = false` also kills
             * a probe that did start and hung, and leaves the next cadence free
             * to retry, so a probe that recovers does not need the shell.
             */
            probe.running = false;
            root.apply(null);
        }
    }

    Timer {
        id: cadence
        interval: root.interval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (probe.running || !root.needsProbe)
                return;
            root.raw = "";
            probe.running = true;
            /**
             * Armed here rather than in `onStarted`, and that is not a detail.
             * When the binary is missing the process never starts and `onStarted`
             * never fires — so arming there means the watchdog never arms, and
             * the dot sits at "idle" forever on a machine with no PipeWire check
             * at all. That is precisely the failure rule 1 exists to prevent:
             * the check could not run, and the indicator reported all clear.
             * Measured, not assumed: with `wpctl` off PATH, `exited` never fires.
             */
            watch.restart();
        }
    }

    /**
     * Fold one probe result in. `parsed` is null for "the check did not run";
     * anything else is the stream list from `parseStatus`.
     *
     * A null leaves the three lists exactly as they were. That is the point:
     * the previous answer is what lets a later failure say what was last seen,
     * and clearing it would turn every hiccup into "nothing there".
     */
    function apply(parsed) {
        probed = true;
        if (parsed === null) {
            probeOk = false;
            return;
        }
        var inAudio = { apps: [], devices: [] };
        var cam = { apps: [], devices: [] };
        var outAudio = { apps: [], devices: [] };
        for (var i = 0; i < parsed.length; i++) {
            var node = parsed[i];
            if (node.dir === "out")
                collect(outAudio, node);
            else if (node.kind === "audio")
                collect(inAudio, node);
            else
                collect(cam, node);
        }
        audioInUsers = inAudio;
        cameraUsers = cam;
        audioOutUsers = outAudio;
        probeOk = true;
    }

    /** File a stream into one source's list, keeping both halves de-duplicated. */
    function collect(into, node) {
        if (node.app.length > 0 && into.apps.indexOf(node.app) < 0)
            into.apps.push(node.app);
        if (node.device.length > 0 && into.devices.indexOf(node.device) < 0)
            into.devices.push(node.device);
    }

    /**
     * Pull the live streams out of `wpctl status`.
     *
     * Only `Audio` / `Video` → `Streams` is read. Devices, sinks and sources are
     * ignored on purpose — see the header for what their `*` marker actually
     * means, which is not "in use".
     *
     * Every stream carries the direction it was seen going: `in` for `<`, a
     * stream drawing from a device (a capture), and `out` for `>`, writing to
     * one (playback). Both are returned rather than playback being dropped,
     * because which of the two lights the dot is the owner's choice and not
     * this file's — but it is kept *separate*, never merged, precisely because
     * a speaker in use is not a camera.
     *
     * Returns null when the body is not the shape we expect — that is a failed
     * read, not a clean one, and the caller turns it into `unknown`.
     */
    function parseStatus(text) {
        if (typeof text !== "string" || text.length === 0)
            return null;

        var lines = text.split("\n");
        var out = [];
        var pending = [];
        var domain = null;
        var inStreams = false;
        var sawDomain = false;
        var headCol = -1;
        var stream = null;

        for (var i = 0; i < lines.length; i++) {
            var gutter = lines[i];

            /** An `Audio` or `Video` header is the one unindented, boxed-in line. */
            if (!/^[\s\u2500-\u257F]/.test(gutter)) {
                domain = /^Audio$/i.test(gutter.trim()) ? "audio"
                      : /^Video$/i.test(gutter.trim()) ? "video"
                      : null;
                if (domain !== null)
                    sawDomain = true;
                inStreams = false;
                headCol = -1;
                stream = null;
                continue;
            }

            var line = bare(gutter);
            if (line.length === 0) {
                stream = null;
                continue;
            }

            var sec = /^(Devices|Sinks|Sources|Filters|Streams):$/.exec(line);
            if (sec !== null) {
                inStreams = sec[1] === "Streams";
                headCol = -1;
                stream = null;
                continue;
            }

            if (!inStreams || domain === null) {
                stream = null;
                continue;
            }

            var num = /^\d+\.\s*(.*)$/.exec(line);
            if (num === null) {
                stream = null;
                continue;
            }

            /**
             * Headers and links are the same shape — `NN. something` — and no
             * blank line separates one stream from the next. Indentation is the
             * only thing that tells them apart: a header sits at one column and
             * its links are indented further. Depth is read before the gutter is
             * stripped, because stripping is exactly what loses it.
             */
            var col = /^[ \t\u00A0\u2500-\u257F]*/.exec(gutter)[0].length;
            if (headCol < 0)
                headCol = col;
            if (col > headCol) {
                /**
                 * A link, and the arrow is the direction. `<` means the stream
                 * draws from a device; `>` means it writes to one. Only the
                 * first arrow of a stream is kept — a recorder with two input
                 * ports is one thing happening, not two.
                 *
                 * A link with no arrow at all (an unconnected port) says nothing
                 * and is left alone, so the stream falls through to the rule
                 * below.
                 */
                var arrow = /([<>])\s+(.+)$/.exec(num[1]);
                if (stream !== null && arrow !== null) {
                    stream.dir = arrow[1] === "<" ? "in" : "out";
                    stream.device = cleanDevice(arrow[2]);
                    out.push(stream);
                    stream.pushed = true;
                    stream = null;
                }
                continue;
            }

            /** A stream header: `80. pw-record`. */
            stream = { kind: domain, app: cleanApp(num[1]), device: "", dir: "", pushed: false };
            pending.push(stream);
        }

        /**
         * A stream that was never seen going anywhere is treated as capturing.
         * This is the one inference left, and it is deliberately pointed at the
         * capture side: if a future PipeWire stops printing arrows the cost is a
         * dot that may stay lit, not a camera that silently stops being reported.
         * It never invents *output* out of a stream it could not read a
         * direction for, because output is opt-in and guessing at it would put
         * the dot on for reasons the user did not ask about.
         */
        for (var k = 0; k < pending.length; k++)
            if (!pending[k].pushed) {
                pending[k].dir = "in";
                out.push(pending[k]);
            }

        /** No Audio or Video header means we did not read a report at all. */
        return sawDomain ? out : null;
    }

    /**
     * Strip the tree gutter `wpctl status` indents with — spaces and box
     * characters — so the rest of the parser can match on what a line says.
     */
    function bare(line) {
        return String(line).replace(/^[\s\u2500-\u257F]+/, "").trim();
    }

    /**
     * Turn a stream header into an application name.
     *
     * Headers are free text: "Chrome", "Firefox Web Content", "pw-record", and
     * occasionally a path or a stream named after the node it opened. The leaf
     * name is taken and the wrapper suffixes dropped, so what is left reads like
     * the program that opened it.
     */
    function cleanApp(name) {
        var s = String(name).replace(/^.*\//, "");
        s = s.replace(/\s+on\s+.*$/i, "");
        s = s.replace(/^alsa_(input|output)\..*$/i, "");
        s = s.replace(/\s*\(.*\)\s*$/, "").trim();
        return s;
    }

    /**
     * Clean a link target into something readable enough for a tooltip. It is a
     * raw PipeWire port name, and it is only reached when the stream header
     * gave no application at all — the device is the fallback, not the story.
     */
    function cleanDevice(text) {
        return String(text).replace(/\s*\[[^\]]*\]\s*$/, "").replace(/\s+/g, " ").trim();
    }
}

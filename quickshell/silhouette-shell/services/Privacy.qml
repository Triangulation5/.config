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
 *   - **Microphone and camera.** PipeWire, through `wpctl status`. There is no
 *     Quickshell service for capture state, and inventing one is out of scope;
 *     this is a slow read of the one tool that already answers the question.
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
 *      is right there in the stream header for nearly every real stream. The
 *      names are collected and kept in `micUsers` / `cameraUsers`; nothing
 *      prints them yet, because the rest surface is 38px tall and holds a mark
 *      and nothing else. A surface with room for words can read them off
 *      directly.
 *
 * Two things this deliberately does not do, because both were specified:
 *
 *   - It does not infer anything from the notification server. A notification
 *     that *mentions* a meeting is not evidence that a camera is running, and
 *     coupling the two would make the indicator wrong in both directions.
 *   - It does not poll fast. A mic click is a rare event against a session that
 *     runs for hours, so the cadence is `Flags.privacyPollMs` (10 s) and is
 *     floored at 5 s by `interval` below — it is a process spawn per tick, and
 *     a flag that could be wound down to a busy loop would defeat the point.
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
 * permanently and wrongly. The capture signal is the **Streams** section, and
 * the arrow is the direction: `<` means the stream is reading from a device
 * (capturing), `>` means it is writing to one (playback). The stream header is
 * the application name, which is rule 2 delivered for free.
 */
Singleton {
    id: root

    /** -- the three sources ------------------------------------------------ */

    /** The shell's own recorder, or one started outside it. Exact, not polled. */
    readonly property bool screen: ScreenRec.recording

    /**
     * Everything the last good probe found, kept so a failure still names it.
     *
     * Replaced wholesale rather than edited in place: a plain JS object has no
     * change signal, so mutating these arrays would leave every binding reading
     * them stale. These are the writable source; everything the UI reads
     * (`state`, `label`) is derived below and stays readonly.
     */
    property var micUsers: ({ apps: [], devices: [] })
    property var cameraUsers: ({ apps: [], devices: [] })

    /** -- the one answer the UI reads ------------------------------------- */

    /**
     * `idle` — nothing is capturing, and we know it. The dot is invisible.
     * `capture` — something is, and the dot takes the capture colour.
     * `unknown` — the check could not run or could not be read; the dot is
     *   shown in the unknown colour, because a blank dot here would be a lie.
     *
     * Screen is asked first and is deliberately not gated on `probeOk`: it
     * comes from a different, exact source, so a dead PipeWire must not be able
     * to downgrade a recording that is plainly happening.
     *
     * The one state that is not "fail visible" is `idle` before the very first
     * probe finishes, which draws nothing. That is not a failure being hidden —
     * nothing has been checked yet, and amber for the single frame the shell
     * takes to load would be noise dressed up as information. The first probe
     * to *complete*, successfully or not, settles it for good.
     */
    readonly property string state: {
        if (screen)
            return "capture";
        if (!probeOk)
            return probed ? "unknown" : "idle";
        if (micUsers.apps.length > 0 || cameraUsers.apps.length > 0)
            return "capture";
        return "idle";
    }

    /** True when something is genuinely capturing. */
    readonly property bool capturing: state === "capture"

    /** True when we could not find out. Deliberately never folded into idle. */
    readonly property bool unknown: state === "unknown"

    /** True when the dot should be drawn at all. */
    readonly property bool visible: state !== "idle"

    /** -- the probe -------------------------------------------------------- */

    /** True once a probe has completed and parsed into something usable. */
    property bool probeOk: false

    /** True once any probe has finished, which is what makes `unknown` honest. */
    property bool probed: false

    /**
     * Cadence in ms. The floor is load-bearing, not defensive tidiness: the
     * brief for this service is explicit that a process spawn per tick is the
     * thing to avoid, so a hand-edited flags.json cannot turn this into a busy
     * loop either.
     */
    readonly property int interval: Math.max(5000, Flags.privacyPollMs)

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
            if (probe.running)
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
     * anything else is the capture list from `parseStatus`.
     *
     * A null leaves `micUsers`/`cameraUsers` exactly as they were. That is the
     * point: the previous answer is what lets the label name the last thing
     * seen, and clearing it would turn every hiccup into "nothing there".
     */
    function apply(parsed) {
        probed = true;
        if (parsed === null) {
            probeOk = false;
            return;
        }
        var mic = { apps: [], devices: [] };
        var cam = { apps: [], devices: [] };
        for (var i = 0; i < parsed.length; i++) {
            if (parsed[i].kind === "audio")
                collect(mic, parsed[i]);
            else
                collect(cam, parsed[i]);
        }
        micUsers = mic;
        cameraUsers = cam;
        probeOk = true;
    }

    /** File a capture into a source's list, keeping both halves de-duplicated. */
    function collect(into, node) {
        if (node.app.length > 0 && into.apps.indexOf(node.app) < 0)
            into.apps.push(node.app);
        if (node.device.length > 0 && into.devices.indexOf(node.device) < 0)
            into.devices.push(node.device);
    }

    /**
     * Pull the capturing streams out of `wpctl status`.
     *
     * Only `Audio` / `Video` → `Streams` is read. Devices, sinks and sources are
     * ignored on purpose — see the header for what their `*` marker actually
     * means, which is not "in use".
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
                 * A link. `<` is the whole of the detection — the stream is
                 * drawing from a device. `>` is playback, and a media player
                 * sets that constantly, so mistaking it for a capture would pin
                 * the dot on. A link with no arrow at all (an unconnected port)
                 * says nothing either way and is left alone.
                 */
                var arrow = /([<>])\s+(.+)$/.exec(num[1]);
                if (stream !== null && arrow !== null) {
                    if (arrow[1] === "<") {
                        stream.device = cleanDevice(arrow[2]);
                        out.push(stream);
                        stream.pushed = true;
                        stream = null;
                    } else {
                        stream.playback = true;
                    }
                }
                continue;
            }

            /** A stream header: `80. pw-record`. */
            stream = { kind: domain, app: cleanApp(num[1]), device: "", playback: false, pushed: false };
            pending.push(stream);
        }

        /**
         * A stream that was never seen playing is treated as capturing. This is
         * the one inference left, and it is deliberately pointed at showing the
         * dot: if a future PipeWire stops printing arrows the cost is a dot that
         * stays lit, not a camera that silently stops being reported.
         */
        for (var k = 0; k < pending.length; k++)
            if (!pending[k].pushed && !pending[k].playback)
                out.push(pending[k]);

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

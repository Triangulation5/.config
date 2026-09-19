pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services

/**
 * 系 SYSTEM surface: a flat washi card of live machine vitals fed by the Sysmon
 * singleton. The header carries the kanji, label and uptime. Below it sit flame
 * dials for CPU, GPU and memory load, each a 270deg arc stroked with the mixer's
 * vermLit-to-vermBurn gradient on a thread track and rounded caps, the sweep
 * eased over the value change; the centre shows the value, a unit and a sub line
 * (CPU/GPU temperature, memory total). A hairline stripe underneath reports
 * network throughput, root-disk fill, swap and VRAM with their units folded into
 * the faint labels so the values read bare. On a machine with no discrete GPU the
 * GPU dial and VRAM cell drop and the remaining dials recentre. Polling lives in
 * the singleton and only runs while this surface is open.
 *
 * The card under the stripe is an on-demand speed test: a Cloudflare round trip
 * in three phases (ping, download, upload), each its own process so one phase
 * can be cut without touching the others, with the running phase's readout lit
 * and the failure line folded into the card's height. Nothing here runs until
 * the trigger is pressed, and the whole run is torn down when the surface
 * closes, so a test never outlives the card that started it.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 16

    implicitHeight: content.implicitHeight

    readonly property var dialKeys: Sysmon.hasGpu ? ["cpu", "gpu", "mem"] : ["cpu", "mem"]
    readonly property var cellKeys: Sysmon.hasVram ? ["net", "disk", "swap", "vram"] : ["net", "disk", "swap"]

    onActiveChanged: {
        Sysmon.open = active;
        /**
         * Closing the card cancels a run rather than leaving it in flight: the
         * phases are child processes of this surface, so they would otherwise
         * keep pulling 25MB chunks for a card nobody is looking at (and this
         * surface is freed outright once it idles out).
         */
        if (!active)
            stopSpeed();
    }

    readonly property point soulPoint: {
        void root.width;
        void root.height;
        if (Flags.showGlyphs)
            return kanji.mapToItem(root, kanji.width / 2, -3 * root.s);
        return sysLabel.mapToItem(root, -8 * root.s, sysLabel.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: soulPoint

    /**
     * Speed-test state. `speedPhase` is "ping" | "download" | "upload" while a
     * run is in flight and "" otherwise; `speedDone` latches a finished run so
     * the card can tell "ran and succeeded" from "never run", and `speedError`
     * carries the reason a run ended early. Values are Mbps, ping is ms.
     */
    property bool speedRunning: false
    property string speedPhase: ""
    property real speedPing: 0
    property real speedDown: 0
    property real speedUp: 0
    property bool speedDone: false
    property string speedError: ""

    /** Cloudflare's speed endpoints: `__down`/`__up` move bulk, and a zero-byte
        `__down` is the round trip the ping measures. The `meta` endpoint the web
        client uses answers this one with a 403, so the ping asks for no bytes
        instead — the smallest thing the endpoint will actually serve, and the
        same single HTTPS round trip. They rate-limit by IP under load, so they
        are named here and the phases treat a refusal as one. */
    readonly property string speedHost: "https://speed.cloudflare.com"
    readonly property string speedPingUrl: speedHost + "/__down?bytes=0"
    readonly property string speedDownUrl: speedHost + "/__down?bytes=25000000"
    readonly property string speedUpUrl: speedHost + "/__up"

    /** Mbps, or Gbps once past 1000, so a readout column stays one line. */
    function fmtSpeed(mbps) {
        return mbps >= 1000 ? (mbps / 1000).toFixed(1) + " Gbps" : mbps.toFixed(1) + " Mbps";
    }

    /**
     * The failure a phase's reply means, or "" when it carries a number.
     *
     * This is the layer that makes the numbers trustworthy: curl exits 0 on an
     * HTTP error, and the endpoint answers a rate limit with a 429 and a
     * one-byte body — which, taken at face value, is a "successful" transfer of
     * one byte and reads as 0.0 Mbps. So each phase reports the status code it
     * saw alongside the bytes, and every non-2xx ends the run with a reason
     * instead of a number that measures nothing.
     */
    function phaseError(txt, where) {
        if (txt === "__RATE__")
            return "Rate limited by the test server";
        if (txt === "__HTTP__")
            return "Test server refused the request";
        if (txt === "__EMPTY__")
            return "No data transferred";
        if (txt === "__FAIL__" || txt.length === 0)
            return where === "ping" ? "No internet connection" : "Connection lost during " + where;
        return "";
    }

    /**
     * End the run with a reason. The phase list is cleared but the values read
     * so far stay on the card, so a failure mid-download still shows the ping it
     * managed. The watchdog is stopped here too — otherwise it would fire its
     * own timeout on top of an error that already ended the run.
     */
    function speedFail(msg) {
        root.speedError = msg;
        root.speedRunning = false;
        root.speedPhase = "";
        root.speedDone = false;
        speedTimeout.stop();
        speedPingProc.running = false;
        speedDlProc.running = false;
        speedUlProc.running = false;
    }

    function startSpeed() {
        if (root.speedRunning)
            return;
        root.speedRunning = true;
        root.speedDone = false;
        root.speedError = "";
        root.speedPhase = "ping";
        root.speedPing = 0;
        root.speedDown = 0;
        root.speedUp = 0;
        speedTimeout.start();
        speedPingProc.running = true;
    }

    /** Cancel without a reason: used by the trigger and by the close hook. */
    function stopSpeed() {
        root.speedRunning = false;
        root.speedPhase = "";
        speedTimeout.stop();
        speedPingProc.running = false;
        speedDlProc.running = false;
        speedUlProc.running = false;
    }

    /**
     * Ping is the whole request's time to first byte against a zero-byte
     * download — one HTTPS round trip, which is the number a speed test means by
     * "ping". A curl that fails either way (no route, DNS, timeout) reports the
     * sentinel and the run ends as "no connection".
     */
    Process {
        id: speedPingProc
        command: ["sh", "-c",
            "s=$(curl -s -m 6 -o /dev/null -w '%{http_code} %{time_total}' '" + root.speedPingUrl + "' 2>/dev/null) || { echo '__FAIL__'; exit 0; }; "
            + "set -- $s; case \"$1\" in 429) echo '__RATE__'; exit 0 ;; 2*) ;; *) echo '__HTTP__'; exit 0 ;; esac; "
            + "printf '%s' \"$2\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                const err = root.phaseError(txt, "ping");
                if (err.length > 0) {
                    root.speedFail(err);
                    return;
                }
                root.speedPing = Math.round((parseFloat(txt) || 0) * 1000);
                root.speedPhase = "download";
                speedDlProc.running = true;
            }
        }
    }

    /**
     * Download: 25MB pulls for five seconds, summed, and capped at eight
     * requests so a fast link cannot hammer the endpoint into refusing (the
     * rate limit is per IP and lasts the better part of an hour). A fixed
     * window rather than a fixed size keeps the run short on fast links and
     * still meaningful on slow ones; curl's own cap is a little longer than
     * the window so a slow link is not counted as a failure. The rate is taken
     * over the time actually spent, not a hard five seconds — the last chunk of
     * the window can run past it, and dividing that by five would over-report.
     */
    Process {
        id: speedDlProc
        command: ["sh", "-c",
            "bytes=0; it=0; rc=0; t0=$(date +%s%N); "
            + "while [ $(( ($(date +%s%N) - t0) / 1000000000 )) -lt 5 ] && [ \"$it\" -lt 8 ]; do "
            + "s=$(curl -s -m 6 -o /dev/null -w '%{http_code} %{size_download}' '" + root.speedDownUrl + "' 2>/dev/null) || { rc=1; break; }; "
            + "set -- $s; case \"$1\" in 429) rc=2; break ;; 2*) ;; *) rc=3; break ;; esac; "
            + "bytes=$((bytes + ${2:-0})); it=$((it + 1)); done; "
            + "el=$(( ($(date +%s%N) - t0) / 1000000 )); [ \"$el\" -lt 1000 ] && el=1000; "
            + "[ \"$rc\" = 1 ] && { echo '__FAIL__'; exit 0; }; "
            + "[ \"$rc\" = 2 ] && { echo '__RATE__'; exit 0; }; "
            + "[ \"$rc\" = 3 ] && { echo '__HTTP__'; exit 0; }; "
            + "[ \"$bytes\" -lt 200000 ] && { echo '__EMPTY__'; exit 0; }; "
            + "awk -v b=\"$bytes\" -v ms=\"$el\" 'BEGIN { printf \"%.1f\", b * 8 / (ms / 1000) / 1000000 }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                const err = root.phaseError(txt, "download");
                if (err.length > 0) {
                    root.speedFail(err);
                    return;
                }
                root.speedDown = Math.round((parseFloat(txt) || 0) * 10) / 10;
                root.speedPhase = "upload";
                speedUlProc.running = true;
            }
        }
    }

    /**
     * Upload: the same five-second window pushing 25MB of filler per pull, with
     * the same request cap and status checks as the download. The filler comes
     * from /dev/zero piped through tr, so nothing is read off disk — the bytes
     * curl counts are the ones it actually handed to the socket, and a body the
     * server truncated still shows up as the smaller number.
     */
    Process {
        id: speedUlProc
        command: ["sh", "-c",
            "bytes=0; it=0; rc=0; t0=$(date +%s%N); "
            + "while [ $(( ($(date +%s%N) - t0) / 1000000000 )) -lt 5 ] && [ \"$it\" -lt 8 ]; do "
            + "s=$(head -c 25000000 /dev/zero | tr '\\0' 'x' | curl -s -m 6 -o /dev/null -w '%{http_code} %{size_upload}' -X POST --data-binary @- '" + root.speedUpUrl + "' 2>/dev/null) || { rc=1; break; }; "
            + "set -- $s; case \"$1\" in 429) rc=2; break ;; 2*) ;; *) rc=3; break ;; esac; "
            + "bytes=$((bytes + ${2:-0})); it=$((it + 1)); done; "
            + "el=$(( ($(date +%s%N) - t0) / 1000000 )); [ \"$el\" -lt 1000 ] && el=1000; "
            + "[ \"$rc\" = 1 ] && { echo '__FAIL__'; exit 0; }; "
            + "[ \"$rc\" = 2 ] && { echo '__RATE__'; exit 0; }; "
            + "[ \"$rc\" = 3 ] && { echo '__HTTP__'; exit 0; }; "
            + "[ \"$bytes\" -lt 200000 ] && { echo '__EMPTY__'; exit 0; }; "
            + "awk -v b=\"$bytes\" -v ms=\"$el\" 'BEGIN { printf \"%.1f\", b * 8 / (ms / 1000) / 1000000 }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                const err = root.phaseError(txt, "upload");
                if (err.length > 0) {
                    root.speedFail(err);
                    return;
                }
                root.speedUp = Math.round((parseFloat(txt) || 0) * 10) / 10;
                root.speedPhase = "done";
                root.speedRunning = false;
                root.speedDone = true;
                speedTimeout.stop();
            }
        }
    }

    /** Backstop for a link that hangs rather than errors: three phases of at
        most six seconds each, plus process startup, sit well inside 45s. */
    Timer {
        id: speedTimeout
        interval: 45000
        onTriggered: root.speedFail("Speed test timed out")
    }

    /**
     * One speed readout: faint caps label over the value, the value lit while
     * its own phase is the one running. A column that has not produced a number
     * yet reads "---", so the row never reflows as the values arrive.
     */
    component Readout: Column {
        property string label: ""
        property string value: "---"
        property bool lit: false

        width: parent.width / 4
        spacing: 3 * root.s

        Text {
            text: parent.label
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 7.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.9 * root.s
        }
        Text {
            text: parent.value
            color: parent.lit ? Theme.vermLit : Theme.cream
            font.family: Theme.font
            font.pixelSize: 13 * root.s
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
    }

    // Run one measurement as soon as the surface is built. The button below
    // re-runs it on demand.
    Timer { interval: 1200; running: true; repeat: false; onTriggered: root.startSpeed() }

    component Dial: Item {
        id: dial

        property real arc: 0
        property string big: ""
        property string unit: ""
        property string sub: ""
        property string label: ""
        property bool shrink: false

        property real display: 0
        onArcChanged: display = arc
        Component.onCompleted: display = arc
        onDisplayChanged: face.requestPaint()
        Behavior on display { NumberAnimation { duration: Math.round(700 * Motion.mult); easing.type: Easing.OutCubic } }

        width: 110 * root.s
        height: 110 * root.s

        Canvas {
            id: face
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var lw = 8 * root.s;
                var r = Math.min(width, height) / 2 - lw / 2 - root.s;
                var start = 135 * Math.PI / 180;
                var full = 270 * Math.PI / 180;
                ctx.lineCap = "round";
                ctx.lineWidth = lw;
                ctx.strokeStyle = Qt.rgba(0.94, 0.88, 0.84, 0.13);
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + full, false);
                ctx.stroke();
                var v = Math.max(0, Math.min(100, dial.display));
                if (v > 0.5) {
                    var diag = r * 0.7071;
                    var grad = ctx.createLinearGradient(cx - diag, cy + diag, cx + diag, cy - diag);
                    grad.addColorStop(0, Theme.vermBurn);
                    grad.addColorStop(0.35, Theme.vermBurn);
                    grad.addColorStop(1, Theme.vermLit);
                    ctx.strokeStyle = grad;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + full * v / 100, false);
                    ctx.stroke();
                }
            }
        }

        /**
         * The big value owns the dial's exact centre so it reads as the focal
         * number whatever its width, with the label and sub line stacked
         * directly beneath it; centring the value rather than the whole column
         * means a one- or three-digit value never drifts off the eye line.
         */
        Row {
            id: bigRow
            anchors.centerIn: parent
            /** Ring gap is at the bottom, so its optical middle sits above the hole centre; lift the value there. */
            anchors.verticalCenterOffset: -12 * root.s
            spacing: 1 * root.s

            Text {
                id: bigText
                text: dial.big
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: (dial.shrink ? 16 : 20) * root.s
                font.weight: Font.ExtraBold
                font.letterSpacing: -0.5 * root.s
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.baseline: bigText.baseline
                visible: dial.unit.length > 0
                text: dial.unit
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Bold
            }
        }

        Column {
            anchors.top: bigRow.bottom
            anchors.topMargin: 3 * root.s
            anchors.horizontalCenter: bigRow.horizontalCenter
            spacing: 3 * root.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.label
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.sub
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
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
                    id: kanji
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "系"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    id: sysLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SYSTEM"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.8 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Sysmon.uptime
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1 * root.s
                font.features: { "tnum": 1 }
            }
        }

        Item { width: 1; height: 16 * root.s }

        Item {
            width: parent.width
            height: 110 * root.s

            Repeater {
                model: root.dialKeys

                Dial {
                    required property int index
                    required property var modelData
                    readonly property string key: modelData
                    readonly property int val: key === "cpu" ? Sysmon.cpu : key === "gpu" ? Sysmon.gpu : Sysmon.memPct

                    x: root.dialKeys.length > 1
                        ? index * (parent.width - width) / (root.dialKeys.length - 1)
                        : (parent.width - width) / 2

                    arc: val
                    big: key === "mem" ? Sysmon.memUsedGb.toFixed(1) : "" + val
                    unit: key === "mem" ? "" : "%"
                    shrink: key !== "mem" && val >= 100
                    label: key
                    sub: key === "cpu" ? (Sysmon.cpuTemp >= 0 ? Sysmon.cpuTemp + "°" : "")
                        : key === "gpu" ? (Sysmon.gpuTemp >= 0 ? Sysmon.gpuTemp + "°" : "")
                        : "/ " + Sysmon.memTotalGb.toFixed(0) + " GB"
                }
            }
        }

        Item { width: 1; height: 18 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 13 * root.s }

        Item {
            width: parent.width
            height: 30 * root.s

            Repeater {
                model: root.cellKeys

                Item {
                    id: cell
                    required property int index
                    required property var modelData
                    readonly property string key: modelData

                    width: parent.width / root.cellKeys.length
                    height: parent.height
                    x: index * width

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 2 * root.s
                        anchors.bottomMargin: 2 * root.s
                        height: parent.height - 4 * root.s
                        width: 1
                        visible: cell.index > 0
                        color: Theme.hairSoft
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.key === "net" ? "Net · MB/s"
                                : cell.key === "disk" ? "Disk · %"
                                : cell.key === "swap" ? "Swap · GB"
                                : "VRAM · GB"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 8 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.9 * root.s
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8 * root.s
                            visible: cell.key === "net"

                            Text {
                                text: "↓" + Sysmon.netDown.toFixed(1)
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                text: "↑" + Sysmon.netUp.toFixed(1)
                                color: Theme.vermLit
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: cell.key !== "net"
                            text: cell.key === "disk" ? "" + Sysmon.diskPct
                                : cell.key === "swap" ? Sysmon.swapUsedGb.toFixed(1)
                                : Sysmon.vramUsedGb.toFixed(1) + " / " + Sysmon.vramTotalGb.toFixed(0)
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            font.weight: Font.ExtraBold
                            font.features: { "tnum": 1 }
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

        Item { width: 1; height: 13 * root.s }

        /**
         * Speed-test card: three readouts and the trigger in one row, the same
         * frame language as the rest of the shell's cards. Fill and border carry
         * the state before any text does — accent while a run is in flight, the
         * error tone while a failure is up. The card grows by one error line
         * when there is something to explain, so a failure never clips.
         */
        Rectangle {
            id: speedBox

            width: parent.width
            height: (root.speedError.length > 0 ? 68 : 52) * root.s
            radius: 10 * root.s
            color: root.speedRunning ? Qt.alpha(Theme.vermLit, 0.12)
                : (root.speedError.length > 0 ? Qt.alpha(Theme.verm, 0.12) : Theme.frameBg)
            border.width: 1
            border.color: root.speedRunning ? Qt.alpha(Theme.vermLit, 0.3)
                : (root.speedError.length > 0 ? Qt.alpha(Theme.verm, 0.3) : Theme.frameBorder)

            Column {
                anchors.fill: parent
                anchors.margins: 10 * root.s
                spacing: 6 * root.s

                Row {
                    width: parent.width
                    spacing: 0

                    Readout {
                        label: "↓ Down"
                        value: root.speedDown > 0 ? root.fmtSpeed(root.speedDown) : "---"
                        lit: root.speedPhase === "download"
                    }
                    Readout {
                        label: "Ping"
                        value: root.speedPing > 0 ? root.speedPing + " ms" : "---"
                        lit: root.speedPhase === "ping"
                    }
                    Readout {
                        label: "↑ Up"
                        value: root.speedUp > 0 ? root.fmtSpeed(root.speedUp) : "---"
                        lit: root.speedPhase === "upload"
                    }

                    /**
                     * The trigger doubles as the phase readout while a run is on
                     * ("PING" → "DOWN" → "UP") and as a retry once something
                     * failed, so the card says what it is doing rather than
                     * leaving three dashes to guess from.
                     */
                    Rectangle {
                        width: parent.width / 4
                        height: 28 * root.s
                        radius: 8 * root.s
                        color: root.speedRunning ? Qt.alpha(Theme.vermLit, 0.15)
                            : (root.speedError.length > 0 ? Qt.alpha(Theme.verm, 0.15) : Qt.alpha(Theme.cream, 0.06))

                        Text {
                            anchors.centerIn: parent
                            text: root.speedRunning
                                ? (root.speedPhase === "ping" ? "Ping" : root.speedPhase === "download" ? "Down" : "Up")
                                : (root.speedError.length > 0 ? "Retry" : "Test")
                            color: root.speedRunning ? Theme.vermLit : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.9 * root.s
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.speedRunning ? root.stopSpeed() : root.startSpeed()
                        }
                    }
                }

                Text {
                    visible: root.speedError.length > 0
                    width: parent.width
                    text: "⚠  " + root.speedError
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }
        }
    }
}

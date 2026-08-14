pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services
import qs.modules.pill.widgets

/**
 * 飴 Ame, the shapeshifter. One molten-glass bead, the shell's only glowing
 * element. Idle it just breathes (2.5% scale over ~8s). No music/audio/physics
 * coupling; every motion is a fixed, scripted timeline.
 *
 * Travel: a form change runs the full shapeshift over `Motion.shapeshift` ms.
 * anticipation stretch, a remnant droplet pinching off at the origin, a
 * quadratic-bezier flight with a tapered streak, a three-droplet landing splash,
 * then an easeOutBack settle into the new form. The flight launches once and
 * tracks a moving target live (bezier endpoint, control point and heading
 * recomputed per frame), so anchors that slide with the pill's 320ms morph bend
 * the arc, no restart. Short-distance form change skips travel and plays the
 * settle in place. Same-form target moves (hover width, seam progress, mixer
 * focus hops, seeks) glide over `Motion.glide` ms, chasing the anchor, never
 * escalating to a flight.
 *
 * Forms: "rest" breathing bead, "caret" blinking launcher capsule, "seam" media
 * bead, "ring" calendar ring, "dock" plain bead (mixer/power/link), "off"
 * hidden. Entering "off" fades out over `Motion.fast` ms; leaving it snaps to
 * the current anchor and pops back with the settle, so toast/OSD handoffs don't
 * ghost-fly from stale positions. Body draws on a QtQuick Canvas: FrameAnimation
 * drives full-rate repaint only while the timeline, splash, remnant or a glide
 * is live; otherwise a Timer ticks the slow inner swirl at ~3fps (30fps while
 * the caret blinks) to keep idle cost low for a 24/7 shell. The swirl advance
 * is interval * 0.0005, so the slower tick keeps the exact same motion, just
 * fewer redraws (and fewer blur-layer re-renders on top of each one).
 */
Item {
    id: root

    property real s: 1.1
    property point point: Qt.point(0, 0)
    property string form: "rest"
    property real heat: 0
    property point wake: Qt.point(0, 0)
    property real wickDir: -1

    opacity: form === "off" ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    visible: opacity > 0.001

    readonly property real restR: 5 * s
    readonly property real heatScale: 1 - 0.4 * heat
    readonly property real flightThreshold: 30 * s
    readonly property real pAntic: 0.146
    readonly property real pFly: 0.658

    property real bx: 0
    property real by: 0
    property string activeForm: "rest"
    property bool hidden: false
    property bool arcFlip: false
    property bool quickFlight: false
    property point lastTarget: Qt.point(0, 0)

    property real prog: 1
    property string phase: "idle"
    property point fromPoint: Qt.point(0, 0)
    property point ctrlPoint: Qt.point(0, 0)
    property real flightAng: 0
    property real flightDist: 0
    property real remnant: 0
    property point remnantPoint: Qt.point(0, 0)
    property real swirl: 0

    property real glideT: 1
    property point glideFrom: Qt.point(0, 0)
    property point glideTo: Qt.point(0, 0)

    readonly property bool timelineLive: prog < 1 || remnant > 0
    readonly property bool gliding: glideT < 1
    readonly property bool blinking: activeForm === "caret"
    readonly property bool busy: timelineLive || gliding

    function clamp01(u) { return Math.max(0, Math.min(1, u)); }
    function smoothstep(u) { return u * u * (3 - 2 * u); }
    function easeInOutQuint(u) { return u < 0.5 ? 16 * u * u * u * u * u : 1 - Math.pow(-2 * u + 2, 5) / 2; }
    function easeOutBack(u) { const c = 1.70158; return 1 + (c + 1) * Math.pow(u - 1, 3) + c * Math.pow(u - 1, 2); }

    function bez(a, c, b, u) {
        const v = 1 - u;
        return Qt.point(v * v * a.x + 2 * v * u * c.x + u * u * b.x,
                        v * v * a.y + 2 * v * u * c.y + u * u * b.y);
    }

    /**
     * Recompute heading, distance and the perpendicular bezier control point
     * for the current fromPoint->point pair. Called per frame during the antic
     * and fly phases so a target that slides mid-flight bends the arc and the
     * painted streak stays on the same curve as the bead. Arc side is latched
     * in startFlight (arcFlip); re-deciding it per frame would mirror the whole
     * curve in one frame when the target crosses the vertical through the origin.
     */
    function updateFlightGeo() {
        const dx = point.x - fromPoint.x;
        const dy = point.y - fromPoint.y;
        const dd = Math.hypot(dx, dy) || 1;
        flightDist = dd;
        flightAng = Math.atan2(dy, dx);
        let px = -dy / dd;
        let py = dx / dd;
        if (arcFlip) { px = -px; py = -py; }
        ctrlPoint = Qt.point((fromPoint.x + point.x) / 2 + px * dd * 0.22,
                             (fromPoint.y + point.y) / 2 + py * dd * 0.22);
    }

    function stopGlide() {
        glideAnim.stop();
        glideTo = Qt.point(bx, by);
        glideT = 1;
    }

    function startFlight(targetForm, quick) {
        quickFlight = quick === true;
        fromPoint = Qt.point(bx, by);
        arcFlip = point.x > fromPoint.x;
        updateFlightGeo();
        remnantAnim.stop();
        remnantPoint = Qt.point(bx, by);
        remnant = flightDist > root.flightThreshold ? 1 : 0;
        activeForm = targetForm;
        stopGlide();
        settleAnim.stop();
        flightAnim.restart();
        if (remnant > 0)
            remnantAnim.restart();
    }

    /**
     * In-place transform: skip travel, replay only the settle window (splash +
     * easeOutBack pop) so a nearby form change still reads as a shapeshift
     * without a pointless flight.
     */
    function startMorph(targetForm) {
        flightAnim.stop();
        activeForm = targetForm;
        prog = root.pFly;
        settleAnim.restart();
    }

    function startGlide(target) {
        glideFrom = Qt.point(bx, by);
        glideTo = target;
        glideT = 0;
        glideAnim.restart();
    }

    /**
     * Wake from the hidden ("off") state. Re-shows start at the wake anchor: the
     * bead condenses there, then flies to its target if far or pops in place if
     * near. Positions from before the hidden period never leak in.
     */
    function appear() {
        stopGlide();
        remnantAnim.stop();
        remnant = 0;
        bx = wake.x;
        by = wake.y;
        if (Math.hypot(point.x - bx, point.y - by) > root.flightThreshold) {
            startFlight(form, true);
        } else {
            bx = point.x;
            by = point.y;
            startMorph(form);
        }
    }

    function retarget() {
        const dx = point.x - bx;
        const dy = point.y - by;
        const dd = Math.hypot(dx, dy);
        if (form !== activeForm) {
            if (dd > root.flightThreshold) {
                startFlight(form);
            } else {
                flightAnim.stop();
                settleAnim.stop();
                if (dd > 0.5)
                    startGlide(point);
                startMorph(form);
            }
        } else if (timelineLive && prog < root.pFly) {
            const jump = Math.hypot(point.x - lastTarget.x, point.y - lastTarget.y);
            if (jump > root.flightThreshold) {
                flightAnim.stop();
                startGlide(point);
                prog = 1;
            }
        } else if (dd > 0.5) {
            startGlide(point);
        } else if (!gliding) {
            bx = point.x;
            by = point.y;
        }
    }

    /**
     * Coalesced decision point. form and point are sibling bindings in Pill
     * whose change handlers fire mid-cascade in unspecified order. Deciding
     * synchronously would read a stale partner value (a far form change sees
     * dd≈0 against the not-yet-updated point and quietly degrades the flight to
     * an in-place morph). Qt.callLater defers the decision until both bindings
     * have settled, and collapses the per-frame handler bursts of a pill morph
     * into one retarget per tick. lastTarget tracks the previous settled anchor
     * so a mid-flight DISCRETE hop (mixer focus jump, seek snap) is told apart
     * from a morph slide and handed to a glide rather than teleporting the
     * airborne bead.
     */
    function decide() {
        if (form === "off") {
            if (hidden)
                return;
            hidden = true;
            flightAnim.stop();
            settleAnim.stop();
            remnantAnim.stop();
            remnant = 0;
            stopGlide();
            prog = 1;
            return;
        }
        if (hidden) {
            hidden = false;
            appear();
        } else {
            retarget();
        }
        lastTarget = Qt.point(point.x, point.y);
    }

    onPointChanged: Qt.callLater(root.decide)
    onFormChanged: Qt.callLater(root.decide)
    onHeatChanged: canvas.requestPaint()

    Component.onCompleted: {
        bx = point.x;
        by = point.y;
        activeForm = form;
        hidden = form === "off";
        lastTarget = Qt.point(point.x, point.y);
    }

    NumberAnimation {
        id: flightAnim
        target: root
        property: "prog"
        from: 0
        to: 1
        duration: root.quickFlight ? Math.round(460 * Motion.mult) : Motion.shapeshift
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: settleAnim
        target: root
        property: "prog"
        to: 1
        duration: Math.round(Motion.shapeshift * (1 - root.pFly))
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: remnantAnim
        target: root
        property: "remnant"
        from: 1
        to: 0
        duration: Math.round(350 * Motion.mult)
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: glideAnim
        target: root
        property: "glideT"
        from: 0
        to: 1
        duration: Motion.glide
        easing.type: Easing.OutCubic
    }

    onProgChanged: {
        if (prog < pAntic) {
            phase = "antic";
            updateFlightGeo();
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (prog < pFly) {
            phase = "fly";
            updateFlightGeo();
            const u = easeInOutQuint((prog - pAntic) / (pFly - pAntic));
            const p = bez(fromPoint, ctrlPoint, point, u);
            bx = p.x;
            by = p.y;
        } else {
            if (phase === "fly")
                flightAng = Math.atan2(point.y - ctrlPoint.y, point.x - ctrlPoint.x);
            phase = prog >= 1 ? "idle" : "settle";
            if (!gliding) {
                bx = point.x;
                by = point.y;
            }
        }
    }

    onGlideTChanged: if (gliding || glideT === 1) {
        bx = glideFrom.x + (glideTo.x - glideFrom.x) * glideT;
        by = glideFrom.y + (glideTo.y - glideFrom.y) * glideT;
        if (glideT >= 1) {
            bx = glideTo.x;
            by = glideTo.y;
        }
    }

    FrameAnimation {
        running: root.visible && root.busy
        onTriggered: {
            root.swirl += frameTime * 0.5;
            ameBody.requestPaint();
        }
    }

    Timer {
        running: root.visible && !root.busy
        interval: root.blinking ? 33 : 500
        repeat: true
        onTriggered: {
            root.swirl += interval * 0.0005;
            ameBody.requestPaint();
        }
    }

    AmeBody {
        id: ameBody
        anchors.fill: parent
        s: root.s
        host: root
    }
}

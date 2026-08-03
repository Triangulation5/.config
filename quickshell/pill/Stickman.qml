pragma ComponentBehavior: Bound

import QtQuick

/**
 * Stickman, the living cursor. At rest it is a small breathing dot (about
 * 4-5 px). Whenever its target moves far enough, the dot unfolds into a
 * tiny white line-figure, dives to the new spot along a bending quadratic
 * bezier, sticks the landing, then folds itself back down into the dot.
 * A small target move just glides the dot; it never unfolds for that.
 *
 * Everything is procedural: no sprite sheets, no keyframed poses. A single
 * timeline parameter (`progress`) drives phase selection, a handful of
 * staggered growth curves drive how much of the figure exists, and every
 * joint angle is computed each frame from travel direction, travel speed
 * and where we are in the timeline. The body frame is rebuilt every frame
 * from the live heading, so a target that keeps moving mid-flight bends
 * the whole figure's path continuously, no restart.
 *
 * PUBLIC SURFACE - kept deliberately compatible with Ame.qml's, so this
 * component can be swapped in wherever Ame is used in the dynamic island
 * without touching the surrounding bindings:
 *   - `s`      real   uniform scale, same meaning as Ame.s
 *   - `point`  point  destination/anchor, same meaning as Ame.point
 *   - `form`   string "dot" (visible/resting-or-traveling) or "hidden",
 *              filling the role Ame.form's "off" value plays
 *   - `wake`   point  where to reappear from when leaving "hidden",
 *              same role as Ame.wake
 *   - `heat`, `wickDir` accepted for binding-compatibility with call
 *     sites that share bindings across both components, but Stickman has
 *     no dock-heat or candle-wick concept, so they are inert here.
 */
Item {
    id: root

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------
    property real s: 1.0
    property point point: Qt.point(0, 0)
    property string form: "dot"          // "dot" | "hidden"
    property point wake: Qt.point(0, 0)

    // Accepted for drop-in compatibility with Ame's binding surface.
    // Stickman has nothing that maps to either concept, so they're inert.
    property real heat: 0
    property real wickDir: -1

    opacity: form === "hidden" ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: fastMs } }
    visible: opacity > 0.001

    // ------------------------------------------------------------------
    // Tunable constants (named, not magic numbers)
    // ------------------------------------------------------------------
    readonly property int fastMs: 160
    readonly property int travelMs: 900        // full anticipate..collapse cycle
    readonly property int travelMsQuick: 520   // used when waking from hidden
    readonly property int glideMs: 200

    readonly property real travelThreshold: 27 * s   // spec: ~25-30px triggers full travel
    readonly property real dotRadius: 4.5 * s

    readonly property real figureLen: 32 * s    // nominal full-figure height
    readonly property real headRFrac: 0.16
    readonly property real neckFrac: 0.05
    readonly property real torsoFrac: 0.30
    readonly property real upperArmFrac: 0.19
    readonly property real lowerArmFrac: 0.17
    readonly property real upperLegFrac: 0.22
    readonly property real lowerLegFrac: 0.20
    readonly property real shoulderWFrac: 0.09
    readonly property real hipWFrac: 0.07

    // Timeline breakpoints, all in [0,1] of the travel cycle.
    readonly property real pAnticipateEnd: 0.10
    readonly property real pUnfoldEnd: 0.26
    readonly property real pFlightEnd: 0.80
    readonly property real pLandingEnd: 0.92

    readonly property real leanLagRate: 10.0     // higher = snappier heading follow
    readonly property real armSwingFreq: 9.0
    readonly property real legSwingFreq: 7.0
    readonly property real idlePulseFreq: 1.1
    readonly property real stretchGain: 0.55     // travel elongation at top speed
    readonly property real pointOvershoot: 0.5   // landing arm-point overshoot (rad)
    readonly property real kneeBendLanding: 1.1  // extra knee bend at touchdown (rad)

    // ------------------------------------------------------------------
    // Internal animation state - the only things onPaint is allowed to read
    // ------------------------------------------------------------------
    property real bx: 0
    property real by: 0
    property bool hiddenState: false

    property real progress: 1            // 0..1 across one full travel cycle
    property string phase: "idle"        // idle | anticipate | unfold | flight | landing | collapse

    property point fromPoint: Qt.point(0, 0)
    property point ctrlPoint: Qt.point(0, 0)
    property real curveSign: 1           // latched arc side for the current travel
    property real flightDist: 0
    property real headingAngle: 0        // live target heading, recomputed each frame in flight
    property real leanAngle: 0           // heading with follow-through lag - what we draw with
    property bool quickTravel: false

    property real glideT: 1
    property point glideFrom: Qt.point(0, 0)
    property point glideTo: Qt.point(0, 0)

    property real clock: 0               // free-running accumulator for idle pulse / limb swing

    readonly property bool traveling: progress < 1
    readonly property bool gliding: glideT < 1
    readonly property bool busyMotion: traveling || gliding

    // ------------------------------------------------------------------
    // Pure math helpers
    // ------------------------------------------------------------------
    function clamp01(u) { return Math.max(0, Math.min(1, u)); }
    function remap(x, a, b) { return clamp01((x - a) / (b - a)); }
    function smoothstep(u) { u = clamp01(u); return u * u * (3 - 2 * u); }
    function easeOutCubic(u) { return 1 - Math.pow(1 - u, 3); }
    function easeInOutQuint(u) { return u < 0.5 ? 16 * u * u * u * u * u : 1 - Math.pow(-2 * u + 2, 5) / 2; }
    function easeOutBack(u) { const c = 1.70158; return 1 + (c + 1) * Math.pow(u - 1, 3) + c * Math.pow(u - 1, 2); }
    function lerp(a, b, u) { return a + (b - a) * u; }
    function dist(a, b) { return Math.hypot(b.x - a.x, b.y - a.y); }

    function angleDelta(a, b) {
        let d = (b - a) % (2 * Math.PI);
        if (d > Math.PI) d -= 2 * Math.PI;
        if (d < -Math.PI) d += 2 * Math.PI;
        return d;
    }

    function bez(a, c, b, u) {
        const v = 1 - u;
        return Qt.point(v * v * a.x + 2 * v * u * c.x + u * u * b.x,
                        v * v * a.y + 2 * v * u * c.y + u * u * b.y);
    }

    /** Analytic derivative of the quadratic bezier, used to gauge travel speed. */
    function bezVelocity(a, c, b, u) {
        return Qt.point(2 * (1 - u) * (c.x - a.x) + 2 * u * (b.x - c.x),
                        2 * (1 - u) * (c.y - a.y) + 2 * u * (b.y - c.y));
    }

    // ------------------------------------------------------------------
    // Motion control
    // ------------------------------------------------------------------

    /**
     * Recompute heading, distance and the arced control point for the
     * current fromPoint -> point pair. Called every frame while flight
     * geometry matters, so a destination that slides mid-dive bends the
     * curve live instead of snapping or restarting. The arc side itself
     * is decided once at launch (curveSign) so the curve doesn't flip to
     * its mirror image mid-flight when the target crosses straight over.
     */
    function updateFlightGeo() {
        const dx = point.x - fromPoint.x;
        const dy = point.y - fromPoint.y;
        const dd = Math.hypot(dx, dy) || 1;
        flightDist = dd;
        headingAngle = Math.atan2(dy, dx);
        const px = (-dy / dd) * curveSign;
        const py = (dx / dd) * curveSign;
        ctrlPoint = Qt.point((fromPoint.x + point.x) / 2 + px * dd * 0.20,
                             (fromPoint.y + point.y) / 2 + py * dd * 0.20);
    }

    function stopGlide() {
        glideAnim.stop();
        glideTo = Qt.point(bx, by);
        glideT = 1;
    }

    function startGlide(target) {
        glideFrom = Qt.point(bx, by);
        glideTo = target;
        glideT = 0;
        glideAnim.restart();
    }

    function startTravel(quick) {
        quickTravel = quick === true;
        fromPoint = Qt.point(bx, by);
        curveSign = point.x >= fromPoint.x ? 1 : -1;
        headingAngle = Math.atan2(point.y - fromPoint.y, point.x - fromPoint.x);
        leanAngle = headingAngle;
        updateFlightGeo();
        stopGlide();
        travelAnim.stop();
        travelAnim.restart();
    }

    /** Wake from "hidden": condense at wake anchor, then dive or pop to point. */
    function appear() {
        stopGlide();
        bx = wake.x;
        by = wake.y;
        if (dist(point, wake) > travelThreshold) {
            startTravel(true);
        } else {
            bx = point.x;
            by = point.y;
            progress = 1;
            phase = "idle";
        }
    }

    /**
     * Coalesced decision point (mirrors the Qt.callLater pattern used
     * elsewhere in the shell): `point` and `form` are sibling bindings
     * that can both change in the same tick, so we defer the decision
     * until both have settled rather than acting on a possibly-stale
     * partner value.
     */
    function decide() {
        if (form === "hidden") {
            if (hiddenState) return;
            hiddenState = true;
            travelAnim.stop();
            stopGlide();
            progress = 1;
            phase = "idle";
            return;
        }
        if (hiddenState) {
            hiddenState = false;
            appear();
            return;
        }
        if (!traveling) {
            const d = dist(Qt.point(bx, by), point);
            if (d > travelThreshold) {
                startTravel(false);
            } else if (d > 0.5) {
                startGlide(point);
            }
        }
        // else: already traveling - updateFlightGeo() (driven every frame
        // from onProgressChanged while in the flight window) picks up the
        // live `point` on its own, so the curve just bends toward it.
    }

    onPointChanged: Qt.callLater(root.decide)
    onFormChanged: Qt.callLater(root.decide)

    Component.onCompleted: {
        bx = point.x;
        by = point.y;
        hiddenState = form === "hidden";
        leanAngle = 0;
    }

    // ------------------------------------------------------------------
    // Animations - these drive parameters only, never pixels directly
    // ------------------------------------------------------------------
    NumberAnimation {
        id: travelAnim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.quickTravel ? root.travelMsQuick : root.travelMs
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: glideAnim
        target: root
        property: "glideT"
        from: 0
        to: 1
        duration: root.glideMs
        easing.type: Easing.OutCubic
    }

    /**
     * Progress -> phase & position. Anticipation and unfold happen in
     * place at the launch point; flight interpolates the bezier (bending
     * live if `point` keeps moving); landing and collapse settle onto the
     * live `point` every frame, so a small drift during touchdown is just
     * absorbed rather than snapped.
     */
    onProgressChanged: {
        if (progress < pAnticipateEnd) {
            phase = "anticipate";
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (progress < pUnfoldEnd) {
            phase = "unfold";
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (progress < pFlightEnd) {
            phase = "flight";
            updateFlightGeo();
            const u = easeInOutQuint(remap(progress, pUnfoldEnd, pFlightEnd));
            const p = bez(fromPoint, ctrlPoint, point, u);
            bx = p.x;
            by = p.y;
        } else if (progress < pLandingEnd) {
            phase = "landing";
            bx = point.x;
            by = point.y;
        } else {
            phase = progress >= 1 ? "idle" : "collapse";
            if (!gliding) {
                bx = point.x;
                by = point.y;
            }
        }
    }

    onGlideTChanged: if (gliding || glideT === 1) {
        bx = lerp(glideFrom.x, glideTo.x, glideT);
        by = lerp(glideFrom.y, glideTo.y, glideT);
        if (glideT >= 1) {
            bx = glideTo.x;
            by = glideTo.y;
        }
    }

    // ------------------------------------------------------------------
    // Repaint scheduling - full rate only while something is moving
    // ------------------------------------------------------------------
    FrameAnimation {
        running: root.visible && root.busyMotion
        onTriggered: {
            root.clock += frameTime;
            // Follow-through: the drawn lean lags the live heading and
            // eases to catch up, so sudden direction changes read as a
            // whip rather than an instant snap.
            if (root.phase === "flight" || root.phase === "landing") {
                const d = root.angleDelta(root.leanAngle, root.headingAngle);
                root.leanAngle += d * Math.min(1, frameTime * root.leanLagRate);
            }
            canvas.requestPaint();
        }
    }

    Timer {
        // Idle dot only needs a cheap, low, fixed-rate tick.
        running: root.visible && !root.busyMotion
        interval: 80
        repeat: true
        onTriggered: {
            root.clock += interval / 1000;
            canvas.requestPaint();
        }
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------
    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        antialiasing: true

        property color inkWarm: "#FAF6F0"

        /**
         * Builds every joint of the figure in world space for the current
         * frame. Nothing here is a stored keyframe: lengths come from the
         * staggered growth curves, angles come from heading/speed/phase.
         * Returns null when there is no figure to draw (pure dot state).
         */
        function buildPose() {
            const u = root.progress;
            const growing = u < root.pLandingEnd;

            // --- staggered growth: head first, then torso, then limbs
            //     unfolding; reverse order (limbs, torso, head) on collapse
            let headT, torsoT, limbT;
            if (growing) {
                const g = root.remap(u, 0.015, root.pUnfoldEnd);
                headT = root.smoothstep(root.remap(g, 0, 0.50));
                torsoT = root.smoothstep(root.remap(g, 0.15, 0.75));
                limbT = root.smoothstep(root.remap(g, 0.35, 1.00));
            } else {
                const c = root.remap(u, root.pLandingEnd, 1.0);
                limbT = 1 - root.smoothstep(root.remap(c, 0, 0.50));
                torsoT = 1 - root.smoothstep(root.remap(c, 0.25, 0.85));
                headT = 1 - root.smoothstep(root.remap(c, 0.55, 1.00));
            }

            if (headT <= 0.001 && torsoT <= 0.001 && limbT <= 0.001)
                return null; // nothing but the dot to draw

            // --- travel speed, used for stretch / bob / swing amplitude
            let speed = 0;
            if (root.phase === "flight") {
                const fu = root.remap(u, root.pUnfoldEnd, root.pFlightEnd);
                const v = root.bezVelocity(root.fromPoint, root.ctrlPoint, root.point, fu);
                speed = Math.min(1.4, Math.hypot(v.x, v.y) / Math.max(1, root.flightDist));
            }

            // --- landing crouch / overshoot envelope
            let landT = 0;
            if (root.phase === "landing")
                landT = root.remap(u, root.pFlightEnd, root.pLandingEnd);
            const compress = 1 - 0.22 * Math.sin(Math.PI * landT);
            const armOvershoot = Math.sin(Math.PI * landT) * root.pointOvershoot;
            const kneeExtra = Math.sin(Math.PI * landT) * root.kneeBendLanding;

            // --- anticipation stretch (elastic pull before launch)
            let anticStretch = 0;
            if (root.phase === "anticipate")
                anticStretch = root.smoothstep(root.remap(u, 0, root.pAnticipateEnd)) * 0.5;

            const L = root.figureLen;
            const neckLen = root.neckFrac * L * torsoT;
            const torsoLen = root.torsoFrac * L * torsoT * compress;
            const headR = root.lerp(root.dotRadius, root.headRFrac * L, headT);
            const armUpper = root.upperArmFrac * L * limbT;
            const armLower = root.lowerArmFrac * L * limbT;
            const legUpper = root.upperLegFrac * L * limbT;
            const legLower = root.lowerLegFrac * L * limbT;
            const shoulderW = root.shoulderWFrac * L * torsoT;
            const hipW = root.hipWFrac * L * torsoT;

            // --- body frame: forward = direction of travel, right = perpendicular
            const drawAngle = root.leanAngle;
            const fwd = Qt.point(Math.cos(drawAngle), Math.sin(drawAngle));
            const right = Qt.point(Math.sin(drawAngle), -Math.cos(drawAngle));
            const originX = root.bx, originY = root.by;
            function toWorld(forwardDist, sideDist) {
                const st = (1 + speed * root.stretchGain);
                return Qt.point(originX + fwd.x * forwardDist * st + right.x * sideDist,
                                originY + fwd.y * forwardDist * st + right.y * sideDist);
            }
            /** One limb segment: origin (forward,side) -> new joint at angle from the forward axis. */
            function limbStep(originF, originS, len, angleFromForward, sideSign) {
                return {
                    f: originF + len * Math.cos(angleFromForward),
                    s: originS + sideSign * len * Math.sin(angleFromForward)
                };
            }

            const hipF = -anticStretch * L * 0.15; // anticipation crouches back before launch
            const shoulderF = torsoLen * 0.82;
            const neckF = torsoLen;
            const headBob = Math.sin(root.clock * 6.2) * 1.2 * speed;
            const headF = torsoLen + neckLen + headR * 0.5 + headBob;
            const headS = Math.cos(root.clock * 4.4) * 0.8 * speed;

            // lead (right) arm: points toward travel, overshoots on landing
            const leadUpperA = 0.35 - speed * 0.12 + armOvershoot;
            const leadLowerA = leadUpperA - 0.22 + armOvershoot * 0.6;
            const shR = { f: shoulderF, s: shoulderW / 2 };
            const elR = limbStep(shR.f, shR.s, armUpper, leadUpperA, 1);
            const haR = limbStep(elR.f, elR.s, armLower, leadLowerA, 1);

            // trailing (left) arm: swings behind with secondary sine motion
            const swing = Math.PI * 0.72 + Math.sin(root.clock * root.armSwingFreq) * 0.30 * speed;
            const shL = { f: shoulderF, s: -shoulderW / 2 };
            const elL = limbStep(shL.f, shL.s, armUpper, swing, -1);
            const haL = limbStep(elL.f, elL.s, armLower, swing * 0.92, -1);

            // legs: trail behind, knees bend more at touchdown, slight scissor
            const legBase = Math.PI * 0.60 + kneeExtra;
            const legSwing = Math.sin(root.clock * root.legSwingFreq) * 0.18 * speed;
            const hpR = { f: hipF, s: hipW / 2 };
            const knR = limbStep(hpR.f, hpR.s, legUpper, legBase + legSwing, 1);
            const ftR = limbStep(knR.f, knR.s, legLower, legBase + kneeExtra + legSwing, 1);
            const hpL = { f: hipF, s: -hipW / 2 };
            const knL = limbStep(hpL.f, hpL.s, legUpper, legBase - legSwing, -1);
            const ftL = limbStep(knL.f, knL.s, legLower, legBase + kneeExtra - legSwing, -1);

            return {
                headR: headR,
                head: toWorld(headF, headS),
                neck: toWorld(neckF, 0),
                hip: toWorld(hipF, 0),
                shoulderR: toWorld(shR.f, shR.s),
                elbowR: toWorld(elR.f, elR.s),
                handR: toWorld(haR.f, haR.s),
                shoulderL: toWorld(shL.f, shL.s),
                elbowL: toWorld(elL.f, elL.s),
                handL: toWorld(haL.f, haL.s),
                hipR: toWorld(hpR.f, hpR.s),
                kneeR: toWorld(knR.f, knR.s),
                footR: toWorld(ftR.f, ftR.s),
                hipL: toWorld(hpL.f, hpL.s),
                kneeL: toWorld(knL.f, knL.s),
                footL: toWorld(ftL.f, ftL.s)
            };
        }

        function limb(ctx, a, b, c, width) {
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.lineTo(c.x, c.y);
            ctx.lineWidth = width;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.strokeStyle = inkWarm;
            ctx.stroke();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.visible)
                return;

            const strokeW = Math.max(1.1, 1.7 * root.s);

            const pose = buildPose();
            if (!pose) {
                // Pure dot: idle breathing, or a small glide in progress.
                const pulse = 1 + 0.05 * Math.sin(root.clock * root.idlePulseFreq * 2 * Math.PI);
                ctx.beginPath();
                ctx.arc(root.bx, root.by, root.dotRadius * pulse, 0, Math.PI * 2);
                ctx.fillStyle = inkWarm;
                ctx.fill();
                return;
            }

            // torso: neck -> hip
            ctx.beginPath();
            ctx.moveTo(pose.neck.x, pose.neck.y);
            ctx.lineTo(pose.hip.x, pose.hip.y);
            ctx.lineWidth = strokeW;
            ctx.lineCap = "round";
            ctx.strokeStyle = inkWarm;
            ctx.stroke();

            // limbs
            limb(ctx, pose.shoulderR, pose.elbowR, pose.handR, strokeW * 0.85);
            limb(ctx, pose.shoulderL, pose.elbowL, pose.handL, strokeW * 0.85);
            limb(ctx, pose.hipR, pose.kneeR, pose.footR, strokeW * 0.9);
            limb(ctx, pose.hipL, pose.kneeL, pose.footL, strokeW * 0.9);

            // head, drawn last so it sits on top of the neck line
            ctx.beginPath();
            ctx.arc(pose.head.x, pose.head.y, pose.headR, 0, Math.PI * 2);
            ctx.fillStyle = inkWarm;
            ctx.fill();
        }
    }
}

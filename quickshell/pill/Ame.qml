pragma ComponentBehavior: Bound

import QtQuick

/**
 * Stickman, the living cursor. At rest it is a tiny glowing ember bead -
 * as unobtrusive as Ame's idle bead, breathing only just barely. Whenever
 * its target moves far enough, the bead unfolds into a small warm
 * line-figure, dives to the new spot along a bending quadratic bezier,
 * sticks the landing, then folds itself back down into the bead. A small
 * target move just glides the bead a little; it never unfolds for that.
 *
 * Everything is procedural: no sprite sheets, no keyframed poses. A single
 * timeline parameter (`progress`) drives phase selection, a handful of
 * staggered growth curves drive how much of the figure exists, and every
 * joint angle is computed each frame from travel direction, dragged travel
 * speed and where we are in the timeline. The body frame is rebuilt every
 * frame from the live heading, so a target that keeps moving mid-flight
 * bends the whole figure's path continuously, no restart.
 *
 * Motion quality notes:
 *  - The anticipation, arc height, hang time and landing impact all scale
 *    with how far the jump is (`travelReach`), so a short hop reads as a
 *    quick flick and a long flight reads as a real running leap.
 *  - Heading, body lean and head orientation form a three-link follow-
 *    through chain, each stage trailing the one before it with its own
 *    lag rate, so a sudden turn ripples through the figure instead of
 *    snapping everywhere at once.
 *  - Limb swing and body stretch are driven by a *dragged* speed value,
 *    not the instantaneous one, so the limbs visibly spin up after
 *    launch and keep drifting for a beat after the body itself has
 *    stopped - ordinary inertia rather than an on/off switch.
 *  - Landing runs a single squash-then-overshoot curve shared by body
 *    scale and head shape, so the impact and its little rebound before
 *    settling come from one continuous function, not two separate bits.
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
    readonly property int travelMsQuick: 480    // used when waking from hidden
    readonly property int travelMsShort: 520    // full cycle duration at reach=0 (a short hop)
    readonly property int travelMsLong: 1040    // full cycle duration at reach=1 (a long flight)
    readonly property int glideMs: 210

    readonly property real travelThreshold: 27 * s   // ~25-30px triggers full travel, per spec
    readonly property real reachRef: 260 * s         // distance at which travelReach saturates
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

    // Distance-adaptive ranges: everything below is lerped between its
    // "short hop" and "long flight" value by travelReach, latched once
    // per travel at launch (see startTravel).
    readonly property real pAnticipateMin: 0.08
    readonly property real pAnticipateMax: 0.16
    readonly property real unfoldWidthMin: 0.13
    readonly property real unfoldWidthMax: 0.17
    readonly property real pFlightMin: 0.76
    readonly property real pFlightMax: 0.80
    readonly property real landingWidthMin: 0.08
    readonly property real landingWidthMax: 0.13
    readonly property real arcBulgeMin: 0.12      // short hops: flatter, more direct
    readonly property real arcBulgeMax: 0.30      // long flights: a confident, bowed dive
    readonly property real launchSquashMin: 0.32
    readonly property real launchSquashMax: 0.58
    readonly property real landingSquashMin: 0.14
    readonly property real landingSquashMax: 0.26

    readonly property real leanLagRate: 10.0     // body lean chasing heading
    readonly property real headLagRate: 5.0      // head chasing the body lean (trails further)
    readonly property real speedLagRate: 6.0     // limb "energy" chasing instantaneous speed
    readonly property real armSwingFreq: 9.0
    readonly property real legSwingFreq: 7.0
    readonly property real idlePulseFreq: 1.1
    readonly property real stretchGain: 0.55     // travel elongation at top dragged speed
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
    property real leanAngle: 0           // heading with follow-through lag - body draws with this
    property real headLagAngle: 0        // leanAngle with a second, slower lag - the head's own tilt
    property real speedLag: 0            // dragged/inertial speed that actually drives the pose
    property bool quickTravel: false

    // Distance-adaptive timeline, computed once per travel by startTravel().
    property real travelReach: 0
    property real pAnticipateCur: 0.10
    property real pUnfoldCur: 0.24
    property real pFlightCur: 0.78
    property real pLandingCur: 0.90
    property real arcBulge: 0.20
    property real launchSquashAmt: 0.45
    property real landingSquashAmt: 0.20
    property int travelMsCur: 780

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
    function easeInOutQuint(u) { return u < 0.5 ? 16 * u * u * u * u * u : 1 - Math.pow(-2 * u + 2, 5) / 2; }
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

    /** Analytic derivative of the quadratic bezier, used to gauge instantaneous travel speed. */
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
        ctrlPoint = Qt.point((fromPoint.x + point.x) / 2 + px * dd * arcBulge,
                             (fromPoint.y + point.y) / 2 + py * dd * arcBulge);
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

    /**
     * Launch a full travel cycle. Distance decides the whole cycle's
     * personality up front - anticipation size, arc bow, hang time and
     * landing impact are all latched here from travelReach, so a hop and
     * a leap feel like genuinely different actions, not the same
     * animation played at different speeds.
     */
    function startTravel(quick) {
        quickTravel = quick === true;
        fromPoint = Qt.point(bx, by);
        curveSign = point.x >= fromPoint.x ? 1 : -1;
        headingAngle = Math.atan2(point.y - fromPoint.y, point.x - fromPoint.x);
        leanAngle = headingAngle;
        headLagAngle = headingAngle;

        const rawDist = dist(fromPoint, point);
        travelReach = clamp01(rawDist / reachRef);
        pAnticipateCur = lerp(pAnticipateMin, pAnticipateMax, travelReach);
        pUnfoldCur = pAnticipateCur + lerp(unfoldWidthMin, unfoldWidthMax, travelReach);
        pFlightCur = lerp(pFlightMin, pFlightMax, travelReach);
        pLandingCur = Math.min(0.97, pFlightCur + lerp(landingWidthMin, landingWidthMax, travelReach));
        arcBulge = lerp(arcBulgeMin, arcBulgeMax, travelReach);
        launchSquashAmt = lerp(launchSquashMin, launchSquashMax, travelReach);
        landingSquashAmt = lerp(landingSquashMin, landingSquashMax, travelReach);
        travelMsCur = quickTravel ? travelMsQuick : Math.round(lerp(travelMsShort, travelMsLong, travelReach));

        updateFlightGeo(); // rebuilds ctrlPoint using the arcBulge just latched above

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
        duration: root.travelMsCur
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
        if (progress < pAnticipateCur) {
            phase = "anticipate";
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (progress < pUnfoldCur) {
            phase = "unfold";
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (progress < pFlightCur) {
            phase = "flight";
            updateFlightGeo();
            const u = easeInOutQuint(remap(progress, pUnfoldCur, pFlightCur));
            const p = bez(fromPoint, ctrlPoint, point, u);
            bx = p.x;
            by = p.y;
        } else if (progress < pLandingCur) {
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

            // Follow-through chain: heading -> body lean -> head lag, each
            // stage trailing the one before it, so a sudden turn ripples
            // through the figure instead of snapping everywhere at once.
            if (root.phase === "flight" || root.phase === "landing") {
                const dLean = root.angleDelta(root.leanAngle, root.headingAngle);
                root.leanAngle += dLean * Math.min(1, frameTime * root.leanLagRate);
            }
            const dHead = root.angleDelta(root.headLagAngle, root.leanAngle);
            root.headLagAngle += dHead * Math.min(1, frameTime * root.headLagRate);

            // Dragged speed: limbs/stretch chase this, not the instant
            // bezier speed, so they visibly spin up after launch and keep
            // drifting for a beat after the body itself has stopped.
            let targetSpeed = 0;
            if (root.phase === "flight") {
                const fu = root.remap(root.progress, root.pUnfoldCur, root.pFlightCur);
                const v = root.bezVelocity(root.fromPoint, root.ctrlPoint, root.point, fu);
                targetSpeed = Math.min(1.4, Math.hypot(v.x, v.y) / Math.max(1, root.flightDist));
            }
            root.speedLag += (targetSpeed - root.speedLag) * Math.min(1, frameTime * root.speedLagRate);

            canvas.requestPaint();
        }
    }

    Timer {
        // Idle bead only needs a cheap, low, fixed-rate tick.
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

        // Warm ember / molten-glass palette, shared by the resting bead
        // and the stickman's head - one draw routine, two identities.
        property color emberGlint: "#FFF6EC"
        property color emberHot: "#FFB07A"
        property color emberBody: "#E4572E"
        property color emberDeep: "#7A2410"
        property color limbColor: "#D9601F"
        property color limbGlowColor: Qt.rgba(0.851, 0.376, 0.122, 0.16)

        /**
         * Builds every joint of the figure in world space for the current
         * frame. Nothing here is a stored keyframe: lengths come from the
         * staggered growth curves, angles come from heading/drag/phase.
         * Returns null when there is no figure to draw (pure bead state).
         */
        function buildPose() {
            const u = root.progress;
            const growing = u < root.pLandingCur;

            // --- staggered growth: head first, then torso, then limbs
            //     unfolding; reverse order (limbs, torso, head) on collapse,
            //     so the figure folds itself away rather than just shrinking
            //     uniformly - the last thing left is always the head/bead.
            let headT, torsoT, limbT;
            if (growing) {
                const g = root.remap(u, 0.015, root.pUnfoldCur);
                headT = root.smoothstep(root.remap(g, 0, 0.50));
                torsoT = root.smoothstep(root.remap(g, 0.15, 0.75));
                limbT = root.smoothstep(root.remap(g, 0.35, 1.00));
            } else {
                const c = root.remap(u, root.pLandingCur, 1.0);
                limbT = 1 - root.smoothstep(root.remap(c, 0, 0.50));
                torsoT = 1 - root.smoothstep(root.remap(c, 0.25, 0.85));
                headT = 1 - root.smoothstep(root.remap(c, 0.55, 1.00));
            }

            if (headT <= 0.001 && torsoT <= 0.001 && limbT <= 0.001)
                return null; // nothing but the bead to draw

            // --- landing: one continuous squash-then-overshoot curve,
            //     shared by the body's length scale and the head's shape,
            //     so the impact and its little rebound come from a single
            //     function rather than two separately-tuned bits.
            let landScale = 1, headSquash = 0;
            if (root.phase === "landing") {
                const landT = root.remap(u, root.pFlightCur, root.pLandingCur);
                if (landT < 0.5) {
                    const q = landT / 0.5;
                    landScale = 1 - root.landingSquashAmt * Math.sin(Math.PI * q);
                    headSquash = root.landingSquashAmt * 1.6 * Math.sin(Math.PI * q);
                } else {
                    const q = (landT - 0.5) / 0.5;
                    landScale = 1 + root.landingSquashAmt * 0.42 * Math.sin(Math.PI * q);
                    headSquash = -root.landingSquashAmt * 0.9 * Math.sin(Math.PI * q);
                }
            }

            // --- anticipation: elastic pull-back plus a squash that
            //     builds toward the coming heading, so the bead visibly
            //     "loads up" before it launches - bigger for long jumps.
            let anticPull = 0;
            if (root.phase === "anticipate") {
                const q = root.smoothstep(root.remap(u, 0, root.pAnticipateCur));
                anticPull = q * root.launchSquashAmt;
                headSquash += q * root.launchSquashAmt * 0.8;
            }

            // Dragged speed drives stretch and limb-swing amplitude, not
            // the instantaneous bezier speed - see the FrameAnimation.
            const speed = root.speedLag;

            const L = root.figureLen;
            const neckLen = root.neckFrac * L * torsoT;
            const torsoLen = root.torsoFrac * L * torsoT * landScale;
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
                const st = 1 + speed * root.stretchGain;
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

            // landing overshoot on the pointing arm / knees, riding the
            // same landing window as the squash-rebound curve above.
            let armOvershoot = 0, kneeExtra = 0;
            if (root.phase === "landing") {
                const landT = root.remap(u, root.pFlightCur, root.pLandingCur);
                armOvershoot = Math.sin(Math.PI * landT) * root.pointOvershoot;
                kneeExtra = Math.sin(Math.PI * landT) * root.kneeBendLanding;
            }

            const hipF = -anticPull * L * 0.16;
            const shoulderF = torsoLen * 0.82;
            const neckF = torsoLen;

            // Head inertia: a rhythmic forward bob (floaty dive motion)
            // plus a lateral wag driven by how far the head's own lag is
            // still catching up to the body's lean - a real delayed
            // rotation rather than a fixed decorative wiggle.
            const headBobF = Math.sin(root.clock * 6.2) * 1.1 * speed;
            const headLagWag = root.angleDelta(root.headLagAngle, root.leanAngle) * L * 1.2;
            const headF = torsoLen + neckLen + headR * 0.5 + headBobF;
            const headS = headLagWag + Math.sin(root.clock * 4.4) * 0.35 * speed;

            // lead (right) arm: points toward travel, overshoots on landing
            const leadUpperA = 0.35 - speed * 0.12 + armOvershoot;
            const leadLowerA = leadUpperA - 0.22 + armOvershoot * 0.6;
            const shR = { f: shoulderF, s: shoulderW / 2 };
            const elR = limbStep(shR.f, shR.s, armUpper, leadUpperA, 1);
            const haR = limbStep(elR.f, elR.s, armLower, leadLowerA, 1);

            // trailing (left) arm: swings behind with secondary sine motion,
            // amplitude scaled by the dragged speed - true inertial drag.
            const swing = Math.PI * 0.72 + Math.sin(root.clock * root.armSwingFreq) * 0.30 * speed;
            const shL = { f: shoulderF, s: -shoulderW / 2 };
            const elL = limbStep(shL.f, shL.s, armUpper, swing, -1);
            const haL = limbStep(elL.f, elL.s, armLower, swing * 0.92, -1);

            // legs: trail behind, knees bend more at touchdown; the two
            // legs use slightly offset swing phases so the flutter reads
            // as organic rather than a mirrored, mechanical scissor.
            const legBase = Math.PI * 0.60 + kneeExtra;
            const legSwingR = Math.sin(root.clock * root.legSwingFreq) * 0.18 * speed;
            const legSwingL = Math.sin(root.clock * root.legSwingFreq + 0.9) * 0.18 * speed;
            const hpR = { f: hipF, s: hipW / 2 };
            const knR = limbStep(hpR.f, hpR.s, legUpper, legBase + legSwingR, 1);
            const ftR = limbStep(knR.f, knR.s, legLower, legBase + kneeExtra + legSwingR, 1);
            const hpL = { f: hipF, s: -hipW / 2 };
            const knL = limbStep(hpL.f, hpL.s, legUpper, legBase - legSwingL, -1);
            const ftL = limbStep(knL.f, knL.s, legLower, legBase + kneeExtra - legSwingL, -1);

            return {
                headR: headR,
                headSquash: headSquash,
                headAngle: drawAngle,
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

        /** Warm two-pass stroke (a soft glow bleed, then the crisp line) for one poly-line. */
        function strokePath(ctx, pts, width) {
            ctx.beginPath();
            ctx.moveTo(pts[0].x, pts[0].y);
            for (let i = 1; i < pts.length; i++)
                ctx.lineTo(pts[i].x, pts[i].y);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.lineWidth = width * 1.8;
            ctx.strokeStyle = limbGlowColor;
            ctx.stroke();
            ctx.lineWidth = width;
            ctx.strokeStyle = limbColor;
            ctx.stroke();
        }

        /**
         * The one glowing-bead draw routine, reused for both the resting
         * bead and the stickman's head - "the head becomes the bead" is
         * literal here, not just a size interpolation. `squash` elongates
         * it along `angle`; both are usually 0 outside anticipation,
         * landing and gliding, keeping the fully-formed figure's head
         * round and readable.
         */
        function paintEmber(ctx, x, y, r, squash, angle, alpha) {
            if (r < 0.35) return;
            ctx.save();
            if (alpha !== undefined) ctx.globalAlpha = alpha;

            const glowR = r * 1.9;
            const glow = ctx.createRadialGradient(x, y, r * 0.2, x, y, glowR);
            glow.addColorStop(0, Qt.rgba(0.894, 0.341, 0.180, 0.30));
            glow.addColorStop(1, Qt.rgba(0.894, 0.341, 0.180, 0));
            ctx.beginPath();
            ctx.arc(x, y, glowR, 0, Math.PI * 2);
            ctx.fillStyle = glow;
            ctx.fill();

            ctx.translate(x, y);
            ctx.rotate(angle);
            ctx.scale(1 + squash, 1 / Math.sqrt(1 + Math.max(-0.9, squash)));
            ctx.rotate(-angle);

            const g = ctx.createRadialGradient(-r * 0.30, -r * 0.34, 0, 0, 0, r);
            g.addColorStop(0, emberGlint);
            g.addColorStop(0.32, emberHot);
            g.addColorStop(0.68, emberBody);
            g.addColorStop(1, emberDeep);
            ctx.beginPath();
            ctx.arc(0, 0, r, 0, Math.PI * 2);
            ctx.fillStyle = g;
            ctx.fill();

            ctx.beginPath();
            ctx.ellipse(-r * 0.32, -r * 0.36, r * 0.34, r * 0.20, -0.5, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(1, 0.97, 0.93, 0.55);
            ctx.fill();

            ctx.restore();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.visible)
                return;

            const strokeW = Math.max(1.1, 1.6 * root.s);
            const pose = buildPose();

            if (!pose) {
                // Pure bead: very subtle idle breathing, or - while a
                // small move is underway - a light stretch along the
                // glide direction. No other idle motion.
                const pulse = 1 + 0.035 * Math.sin(root.clock * root.idlePulseFreq * 2 * Math.PI);
                let stretch = 0, ang = 0;
                if (root.gliding) {
                    const dx = root.glideTo.x - root.glideFrom.x;
                    const dy = root.glideTo.y - root.glideFrom.y;
                    const gd = Math.hypot(dx, dy);
                    if (gd > 0.5) {
                        ang = Math.atan2(dy, dx);
                        stretch = Math.sin(Math.PI * root.clamp01(root.glideT)) * Math.min(0.14, gd / 140);
                    }
                }
                paintEmber(ctx, root.bx, root.by, root.dotRadius * pulse, stretch, ang, 1);
                return;
            }

            strokePath(ctx, [pose.neck, pose.hip], strokeW);
            strokePath(ctx, [pose.shoulderR, pose.elbowR, pose.handR], strokeW * 0.85);
            strokePath(ctx, [pose.shoulderL, pose.elbowL, pose.handL], strokeW * 0.85);
            strokePath(ctx, [pose.hipR, pose.kneeR, pose.footR], strokeW * 0.9);
            strokePath(ctx, [pose.hipL, pose.kneeL, pose.footL], strokeW * 0.9);

            // head, drawn last so it sits on top of the neck line
            paintEmber(ctx, pose.head.x, pose.head.y, pose.headR, pose.headSquash, pose.headAngle, 1);
        }
    }
}

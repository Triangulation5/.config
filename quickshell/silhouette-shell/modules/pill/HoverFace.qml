pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.pill.widgets

/**
 * The expanded (hover) face of the pill, extracted from Pill.qml: the clock
 * that grows out of the rest clock with its handoff crossfade, the media bud,
 * the minimized-window row, the tray and the calendar strip, plus the keyboard
 * focus rings that Nav drives. Pure presentation: every state value comes in
 * through `host` (the pill) and the three widget aliases Nav consumes.
 */
Item {
    id: face

    /** The pill this face belongs to. */
    property var host: null

    /** The rest-face clock Text, used to capture the handoff flight origin. */
    property var restClock: null

    /** Current time text fed by the pill, formatted by the rest clock. */
    property string timeText: ""

    /** Exposed for the pill's soul-bead anchor and hover-mode reset. */
    property alias calendarStrip: calendarStyle

    /** Exposed for the pill's hover width math and Nav's per-icon rows. */
    property alias hoverRow: hoverRow
    property alias minimizedRow: minimized
    property alias trayRow: tray

    anchors.fill: parent

    readonly property bool live: host.mode === "hover"

    /**
     * How far the pill has grown along the rest→hover hop, from the two
     * constant heights. The clock rides this instead of contentMorph — which
     * is 1 the instant hover mode begins and would pop the clock — so the
     * flight tracks the pill's actual growth. Only the pill's own geometry
     * is read, so it behaves identically on any monitor, at any scale, in
     * any notch style.
     */
    readonly property real clockHop: {
        const den = Math.max(1, host.hoverH - host.restH);
        return Math.max(0, Math.min(1, (host.height - host.restH) / den));
    }

    /**
     * The clock grows out of the rest clock's spot and shrinks back into it:
     * one continuous scale+slide driven by clockMorph, which is clockHop itself
     * — the pill body's own rest→hover growth. The *scale* rides that growth
     * 1:1, so the clock is never bigger than the pill morphing under it, and it
     * settles on the same frame the pill does, with no lead and no overshoot.
     *
     * The *travel* deliberately does not ride it 1:1 — the morph curve is far
     * too front-loaded for a distance this long (see `flight`), so the offset
     * re-eases the same progress instead of inheriting it.
     *
     * The rest-to-hover handoff is a separate crossfade (clockHandoff) in the
     * first moments, while the hover clock still sits exactly on the rest clock
     * at the same size — so the swap is invisible and the growth reads as one
     * clock smoothly travelling to its place.
     */
    readonly property real clockProgress: Math.max(0, Math.min(1, clockHop))
    readonly property real clockMorph: clockProgress

    /**
     * How much of the rest→hover flight offset is applied.
     *
     * The offset is sqrt(1 - clockMorph), not 1 - clockMorph. clockMorph comes
     * straight off the pill's height, and that hop rides
     * cubic-bezier(0.16, 1, 0.30, 1), whose y is exactly 1 - (1 - t)^3 — an
     * ease-out cubic *in time*. Reading the offset back through it hands the
     * clock only the time fraction: at 20% of the duration the pill has already
     * covered 49% of the hop, and a clock riding the same number has covered
     * 49% of a ~200px travel across the pill in three frames, then crept the
     * rest of the way. That is the "flashes to the right at breakneck speed".
     * sqrt(1 - y) undoes the cubic (y expressed in time, the offset becomes
     * (1 - t)^1.5), so the clock leaves at a readable speed, accelerates, and
     * still lands on the same frame the pill settles.
     *
     * Zero when the origin was never measured, so an un-measured hop scales
     * into place instead of flying from a garbage point — see clockStartValid,
     * and clockHandoff, which dissolves that swap instead of cutting it.
     */
    readonly property real flight: clockStartValid ? Math.sqrt(1 - clockMorph) : 0
    /**
     * Width of the rest→hover swap, as a fraction of the hop. The rest clock's
     * opacity is (1 - clockHandoff) in Pill.qml and the hover clock's is
     * clockHandoff itself, so this is the crossfade between them.
     *
     * 0.006 of the hop is 0.89px of travel at the shipping uiScale (the rest and
     * hover heights are 41.8px and 189.2px), a fade short enough that it happens
     * while the two clocks are still on top of each other. It was 0.004 before —
     * the same reasoning, a window small enough to be a swap and not a shimmer —
     * but that small a window is one frame, and one frame is what turns any
     * error in the flight origin into a blink rather than a movement.
     *
     * With no measured origin there is no flight at all (see clockStartValid),
     * so the hover clock sits at its settled spot — half a pill away from the
     * rest clock — and a one-frame swap between those two is a teleport of the
     * clock from the left of the pill to the right. The window opens to 0.45 of
     * the hop there: a real crossfade, long enough to read as the clock
     * dissolving across to its place, which is the best a hop with no origin can
     * look. Measured, it stays a swap.
     */
    readonly property real handoffWindow: clockStartValid ? 0.006 : 0.45
    readonly property real clockHandoff: { var t = Math.max(0, Math.min(1, clockMorph / handoffWindow)); return t * t * (3 - 2 * t); }

    /**
     * The media bud, tray and calendar strip ride the pill's own rest→hover
     * growth (clockHop) instead of contentMorph, which is pinned at 1 the
     * moment hover mode begins and would pop them in at full strength while
     * the pill body is still mid-morph. The staggered windows give a
     * coordinated entrance — media first, then tray, then calendar — that
     * lands as the pill settles. Because clockHop clamps to 1 whenever the
     * pill is at or above hover height, a surface closing back into the pill
     * leaves the stagger at full strength too — the root faceArrive gate
     * then fades the whole face in with the pill's settle instead of popping
     * it over the dissolving surface.
     */
    readonly property real mediaMorph: { var t = Math.max(0, Math.min(1, (clockHop - 0.30) / 0.70)); var ease = t * t * (3 - 2 * t); return ease; }
    readonly property real calendarMorph: { var t = Math.max(0, Math.min(1, (clockHop - 0.72) / 0.28)); return t * t * (3 - 2 * t); }
    readonly property real trayMorph: { var t = Math.max(0, Math.min(1, (clockHop - 0.64) / 0.36)); return 1 - Math.pow(1 - t, 2.2); }

    /**
     * Zero for every part of the face the moment anything other than the hover
     * face and the rest pill owns the pill: an open surface, the OSD, a toast,
     * the quick-record chooser, game mode. The exit for those is a quick fade
     * of the *container*, and a fade still shows what is inside it - the clock,
     * the dates, the tray and the minimized row were all still at full strength
     * underneath, so opening a surface read as the hover face flashing over the
     * surface arriving in its place. The media bud has carried this guard on its
     * own (`* (host.surfaceOpen ? 0 : 1)`) since the same flash showed up there
     * as a second copy of the now-playing card; this is that guard for the rest
     * of the face.
     *
     * The rest<->hover pair is deliberately left out: the face has to stay up
     * through that collapse so the clock can fly back into the rest clock, and
     * the close path is unaffected either way, because by then the surface is
     * already gone (`surfaceOpen` false, mode back to hover or rest) and
     * faceArrive crossfades the whole face against the dissolving surface.
     */
    readonly property real faceHush: (host.mode === "hover" || host.mode === "rest") ? 1 : 0

    /**
     * The rest clock's centre, captured once the moment hover mode begins
     * (while the pill is still at rest geometry) so the flight is a clean
     * straight line instead of chasing a live mapToItem mid-morph — the old
     * binding re-mapped an invisible hover target every frame and jumped.
     * Measured in hoverClock's frame — the same frame the flight Translate
     * lives in — so start and end are directly comparable.
     */
    property real clockStartX: 0
    property real clockStartY: 0

    /**
     * Whether clockStart is a measurement the flight may use. A flight from an
     * unmeasured origin is not a mild error: the offset is at full strength
     * exactly when the pill is smallest, so at the end of a collapse the whole
     * difference between a zero capture and the clock's settled spot is applied
     * — roughly half the hover row's width up and to the left of the pill's
     * centre, which at rest (the pill is ~176px wide) puts the clock outside the
     * body, drawn over the desktop, because nothing clips the face. An invalid
     * capture therefore means no flight at all (see `flight`), which is a clock
     * that scales into place where it already is rather than one that flies in
     * from nowhere — and clockHandoff widens in that case so the swap is still a
     * dissolve rather than a one-frame cut.
     */
    property bool clockStartValid: false

    /** True only at rest geometry, where the capture is exact. */
    readonly property bool atRestGeometry: Math.abs(host.height - host.restH) <= 1.5

    /**
     * Only a measurement taken at rest geometry is usable. The mapping is into
     * the hover clock's frame, which *is* the pill, so a capture taken mid-morph
     * stores the rest clock's position against a size the flight does not end at
     * — hover again before the last collapse has finished and the next flight
     * starts from wherever that half-grown frame put it, which reads as the clock
     * flying in from off to one side instead of out of the rest pill. Skipping
     * keeps the previous capture, which was taken at rest geometry and is still
     * where the rest clock sits.
     */
    function captureClockStart() {
        if (!restClock || !atRestGeometry)
            return;
        const p = restClock.mapToItem(hoverClock, restClock.width / 2, restClock.height / 2);
        if (!isFinite(p.x) || !isFinite(p.y))
            return;
        clockStartX = p.x;
        clockStartY = p.y;
        clockStartValid = true;
    }

    /**
     * Called whenever the hover row re-cuts itself. hoverClock sits inside that
     * row, so every change to the row's width slides the frame the origin was
     * measured in and leaves the capture pointing at a spot the hover clock no
     * longer starts from — the tray icons and the minimized row land a beat
     * after the face opens, and the clock's own text widens on the minute. Half
     * of that shift is what the flight start is off by, which is how a clock
     * that was captured against an empty tray ends up flying in from beside the
     * pill.
     *
     * At rest the measurement is exact and cheap, so take it again right there.
     * Anywhere else the capture is left exactly as it is. It used to be dropped
     * (`clockStartValid = false`) so a stale value could not be used — but the
     * value is never stale for what the flight needs it for: it is where the
     * rest clock sits, and that is where the rest clock still is. The drop only
     * cost the next collapse its flight, and a collapse with no flight is a
     * clock that stays at its settled spot and then swaps to the rest clock's
     * spot in a single frame — the left-to-right flash. Keeping the capture
     * through the hover is what guarantees the collapse has somewhere to fly
     * back to.
     */
    function refreshClockStart() {
        if (atRestGeometry)
            captureClockStart();
    }

    /**
     * The collapse's last frames land the pill at rest geometry, which is the
     * first moment the rest clock's position can be read exactly again — the
     * row may have re-cut during the hover (tray icons, the minimized row, the
     * minute ticking the text wider) and moved the frame the capture is written
     * in. Re-taking it here means every hop starts from a measurement that is
     * true as of the moment it starts.
     */
    onAtRestGeometryChanged: if (atRestGeometry) captureClockStart()

    /**
     * Fires on every rest-to-hover hop. The pill is still at rest geometry
     * here (the height Behavior starts a tick later), so the capture is
     * exact. The onCompleted guard covers the one path where live is true
     * from birth — a monitor hotplug while its pill is peeked — so a
     * collapse then still flies from the rest clock's real position.
     *
     * Taken once, and never re-measured during the flight: the offset is fully
     * exposed exactly when the pill is smallest, so every jump in the
     * measurement — the rest row re-laying out, clockSlide, the width changing —
     * would be flung into the clock's own position instead of staying in the aim.
     */
    onLiveChanged: {
        if (live) {
            captureClockStart()
            /** First open sweeps from a week behind onto today; later opens
             *  snap the strip back to the current date. */
            calendarStyle.onFaceOpened()
        }
    }
    Component.onCompleted: {
        if (live) {
            captureClockStart()
            calendarStyle.onFaceOpened()
        }
    }

    /**
     * The hover clock's settled centre in hoverClock's frame: the clock
     * column's centre, offset by the same 20*s the clock is anchored with
     * (the clock is the column's first row, so its vertical centre is half
     * its own height down the column).
     */
    readonly property real clockEndX: hoverClock.width / 2 + 20 * host.s
    readonly property real clockEndY: hoverTime.height / 2

    /**
     * True when the pill entered hover mode by shrinking from an open surface
     * (or OSD/toast) rather than growing from rest; set by the pill's mode
     * handler. On that path clockHop already clamps to 1 (the pill is at or
     * above hover height), so every staggered widget would sit at full
     * strength the instant hover mode begins — the face would pop in at full
     * opacity while the closing surface is still dissolving and ghost over
     * it. faceArrive instead rides the pill's settle (morphCloseness) fade
     * gated by the dissolving surface itself: while the closing surface fades
     * out (host.closingOpacity) the face fades in against it 1:1, an exact
     * crossfade for surfaces whose close barely moves the pill (the media
     * card — there the pill sits at hover size the whole dissolve, so the
     * morphCloseness gate alone was already wide open). Once the surface is
     * gone the face rides the pill's descent as before. From a rest→hover hop
     * faceArrive stays 1 and the existing stagger plays unchanged.
     */
    readonly property bool closeArrive: host.closeArrive
    readonly property real faceArrive: closeArrive
        ? (1 - host.closingOpacity) * Math.pow(Math.max(0, (host.morphCloseness - 0.3) / 0.7), 1.3)
        : 1

    /**
     * The face stays up while the pill collapses from hover back to rest
     * (host.hoverHop is freshly true exactly for the rest↔hover pair), so the
     * clock visibly flies back to the rest spot and the stagger fades the
     * media, tray and dates out over the shrink — ending in the clock handoff
     * swap instead of a 40ms blink-and-reappear. Every other exit (surface,
     * OSD, toast) still drops the face on the fast fade.
     */
    opacity: live ? faceArrive : (host.hoverHop && host.mode === "rest" ? 1 : 0)
    visible: opacity > 0.01

    Behavior on opacity {
        /** The close arrival is already driven smoothly by the pill's morph; a Behavior would fight the per-frame settle. */
        enabled: !face.closeArrive
        NumberAnimation {
            duration: host.mode === "hover" ? Motion.fast : 40
            easing.type: Motion.easeStandard
        }
    }

    Row {
        id: hoverRow

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -20 * host.s

        spacing: 20 * host.s

        /**
         * `anchors.horizontalCenter` recentres the row, so every width change
         * moves the clock column by half of it — and the clock's flight origin
         * was measured inside that column. See refreshClockStart.
         */
        onImplicitWidthChanged: face.refreshClockStart()

        Row {
            id: statusRow

            anchors.verticalCenter: parent.verticalCenter

            spacing: 12 * host.s

            opacity: face.mediaMorph * face.faceHush

            transform: Translate {
                x: 56 * host.s * (1 - face.mediaMorph)
            }

            Loader {
                id: hoverMedia

                anchors.verticalCenter: parent.verticalCenter

                x: -72 * host.s * (1 - face.mediaMorph)

                /**
                 * The bud rides the face's shared hush (faceHush) rather than a
                 * guard of its own: it drops the instant a surface opens,
                 * before the hover face's own fade finishes, so the incoming
                 * surface never fades in over a second copy of the now-playing
                 * card. The close path is handled by faceArrive's crossfade
                 * above, which holds the whole hover face (bud included) until
                 * the closing surface has dissolved.
                 */
                opacity: face.mediaMorph * face.faceHush
                scale: 0.78 + 0.22 * face.mediaMorph

                /**
                 * `host.mediaBudIdle` is the flag the bud is closed by, set from
                 * the media surface and cleared by a new source or by entering
                 * hover (see Pill.mediaBudIdle). Read it instead of ever writing
                 * to this Loader's own `active`, which would drop the binding
                 * above and leave the bud gone for good.
                 *
                 * The idle cleaner no longer reclaims the bud: it is a child of
                 * hoverRow and the pill's hover width comes from that row, so a
                 * rebuild landed mid-morph and re-cut the row under the clock's
                 * flight. Kept built for as long as anything is loaded.
                 */
                active: host.hasMedia && !host.mediaBudIdle
                visible: active

                /**
                 * Build the Media widget (player lookups, cover art) in frame
                 * gaps instead of blocking the tick music starts; the bud's
                 * staggered mediaMorph entrance covers the brief build.
                 */
                asynchronous: true

                /**
                 * Collapse to 0×0 when nothing plays: an invisible-but-sized
                 * loader still counts toward hoverRow's implicitWidth, which
                 * would leave a gap inside the expanded host.
                 */
                width: host.hasMedia ? host.mediaW : 0
                height: host.hasMedia ? host.mediaH : 0

                sourceComponent: Media {
                    id: bud

                    s: host.s
                    open: true
                    morphCloseness: face.mediaMorph
                    shown: host.mode === "hover"

                    onRequestClose: host.mediaBudIdle = true
                }

                /**
                 * Keyboard ring around the focused media bud. It is declared
                 * inside the Loader rather than beside it because the Loader is
                 * a child of `statusRow`: an overlay summed by anchors cannot be
                 * a positioner's child at all — the Row refuses `fill` (and any
                 * other horizontal anchor) and stops positioning its children,
                 * which it reports the first time this ring is shown. Anchored to
                 * the Loader instead, the ring covers exactly the rect the old
                 * `anchors.fill: hoverMedia` asked for, and it rides the bud's own
                 * entrance morph, being one step further inside the same opacity
                 * and scale.
                 */
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3 * host.s
                    z: 1
                    visible: host.faceFocus >= 0 && host.faceFocus < host.faceCount
                        && host.faceTargets[host.faceFocus] === "media"
                    radius: 14 * host.s
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(Theme.vermLit, 0.65)
                }
            }

            /**
             * Live Firefox download chip, shown while anything is in progress.
             * Pure indicator (no pause/cancel — Firefox exposes none); rides
             * the same mediaMorph stagger as the media bud for entrance and
             * exit.
             */
            DownloadBud {
                anchors.verticalCenter: parent.verticalCenter

                s: host.s

                visible: Downloads.active
                opacity: face.mediaMorph * face.faceHush
                scale: 0.9 + 0.1 * face.mediaMorph
            }

            MinimizedTray {
                id: minimized

                anchors.verticalCenter: parent.verticalCenter

                s: host.s
                screenName: host.screenName

                enabled: face.live
                visible: count > 0

                opacity: face.trayMorph * face.faceHush
                scale: 0.9 + 0.1 * face.trayMorph

                faceActive: host.faceFocus >= 0 && host.faceFocus < host.faceCount
                    && host.faceTargets[host.faceFocus] === "minimized"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: minimized.count > 0 && SystemTray.items.values.length > 0
                width: 1
                height: 14 * host.s
                color: Theme.hair
                opacity: 0.7 * face.trayMorph * face.faceHush
            }

            Tray {
                id: tray
                anchors.verticalCenter: parent.verticalCenter

                s: host.s
                barWindow: host.barWindow

                enabled: face.live

                opacity: face.trayMorph * face.faceHush
                scale: 0.9 + 0.1 * face.trayMorph

                faceActive: host.faceFocus >= 0 && host.faceFocus < host.faceCount
                    && host.faceTargets[host.faceFocus] === "tray"
            }
        }

        Item {
            id: clockContainer

            anchors.verticalCenter: parent.verticalCenter

            implicitWidth: hoverClock.implicitWidth
            implicitHeight: hoverClock.implicitHeight

            Column {
                id: hoverClock

                anchors.centerIn: parent

                spacing: 8 * host.s

                Item {
                    /**
                     * The flight lives on this wrapper: a Translate declared
                     * on the scaled Text would itself be scaled (the
                     * transform list applies in the item's local frame), so
                     * the clock would sit short of the rest clock at the
                     * start of the hop. Here the offset is in the column's
                     * unscaled frame, and the Text below scales around its
                     * own centre — position and size stay independent.
                     */
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: 20 * host.s

                    implicitWidth: hoverTime.implicitWidth
                    implicitHeight: hoverTime.implicitHeight

                    transform: Translate {
                        x: (face.clockStartX - face.clockEndX) * face.flight
                        y: (face.clockStartY - face.clockEndY) * face.flight
                    }

                    Text {
                        id: hoverTime

                        anchors.centerIn: parent
                        text: face.timeText

                        color: Theme.cream

                        font.family: Theme.font
                        font.pixelSize: 28 * host.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }

                        opacity: face.clockHandoff * face.faceHush
                        /** 18px rest clock scaled up to 28px, tracking the pill's hop. */
                        scale: (18 / 28) + (1 - 18 / 28) * face.clockMorph
                    }
                }

                CalendarStyle {
                    id: calendarStyle

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: 20 * host.s

                    width: 220 * host.s
                    height: 48 * host.s

                    pillRef: host
                    ameEnabled: true

                    onOpenCalendar: (date) => host.openCalendarAt(date)

                    scale: host.s
                    opacity: face.calendarMorph * face.faceHush
                }
            }

            MouseArea {
                anchors.centerIn: parent

                width: hoverClock.implicitWidth + 22 * host.s
                height: hoverClock.implicitHeight + 10 * host.s

                /**
                 * While a day cell is hovered the strip's delegates own the
                 * click (they open the calendar focused on that day);
                 * anywhere else opens it on the current date.
                 */
                enabled: face.live && !calendarStyle.hovered

                cursorShape: Qt.PointingHandCursor

                onClicked: host.openCalendarAt(null)
            }

            /** Keyboard ring around the focused hover-face clock target. */
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4 * host.s
                visible: host.faceFocus >= 0 && host.faceFocus < host.faceCount
                    && host.faceTargets[host.faceFocus] === "clock"
                radius: 16 * host.s
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(Theme.vermLit, 0.65)
            }
        }
    }

}

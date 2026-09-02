import QtQuick
import QtQuick.Controls
import qs.services

/**
 * Hover date strip on the pill. A horizontal snapping wheel of days around today
 * where each delegate scales and brightens with its proximity to the center; the
 * centered day feeds the calendar surface's selected date.
 */

Item {
    id: root

    width: 320
    height: 64

    property bool ameEnabled: false
    property var pillRef: null

    /** Day under the pointer, -1 when the strip isn't hovered. Drives Ame. */
    property int hoveredIndex: -1

    /** True while a day cell is under the pointer; the pill uses it to hand
     *  clicks on the strip to the day delegates instead of the clock area. */
    readonly property bool hovered: hoveredIndex >= 0

    /** Emitted when a day cell is clicked, carrying that date. The pill opens
     *  the calendar focused on it rather than the current day. */
    signal openCalendar(var date)

    property int selectedIndex: 7
    property date selectedDate: new Date()

    /**
     * Ame anchor for the expanded pill, in widget-local coordinates (the pill
     * maps it into pill space). The wheel is centre-locked (StrictlyEnforceRange),
     * so the focused day sits at width/2 and every other day is exactly
     * (index - currentIndex) * slotWidth away from it. Ame rests just below the
     * strip: under the hovered day, or under the red-highlighted next-day when
     * nothing is hovered. The slot offset is lagged so the soul bead trails
     * behind the pointer instead of snapping to it.
     */
    readonly property real targetSlot:
        hoveredIndex >= 0
        ? hoveredIndex - wheel.currentIndex
        : root.nextSlot

    property real lagSlot: targetSlot

    Behavior on lagSlot {
        NumberAnimation {
            duration: Motion.glide
            easing.type: Motion.easeStandard
        }
    }

    readonly property point ameAnchor: Qt.point(
        width / 2 + lagSlot * wheel.slotWidth,
        height + 12
    )
    function lerpColor(from, to, amount) {
        const t = Math.max(0, Math.min(1, amount))

        return Qt.rgba(
            from.r + (to.r - from.r) * t,
            from.g + (to.g - from.g) * t,
            from.b + (to.b - from.b) * t,
            from.a + (to.a - from.a) * t
        )
    }

    ListModel {
        id: calendarModel
    }

    /** Days of history behind the window's anchored day. */
    property int trailDays: 7

    /** Days of lead ahead of the anchored day before the wheel re-anchors. */
    property int leadDays: 14

    /** Re-anchor the window when the centred day gets this close to an edge. */
    property int edgeRunway: 2

    /**
     * True while a re-anchor is repositioning the wheel (bypasses the glide
     * so the strip re-centres in one frame instead of sweeping past).
     */
    property bool _instant: false

    /**
     * Build the strip's day window so index 7 is `anchor`, with `trailDays`
     * of history behind and `leadDays` ahead. Called on creation, at midnight
     * rollover, and whenever the wheel is re-anchored so scrolling can keep
     * going past the original +leadDays window.
     *
     * The construction call passes `initial: true`: the wheel is parked on
     * the window's past edge — index 0, a week behind the real today —
     * instead of centred on today. That is the legacy opening state: the
     * first time the pill opens, the strip shows the past week and glides
     * onto today (playOpeningSweep). Every later rebuild keeps centring
     * instantly, and the deferred re-assert is skipped because the wheel is
     * deliberately parked where the refill's own drift would land anyway.
     */
    function rebuild(anchor, initial) {
        /**
         * Clearing and refilling the model makes the ListView re-derive its
         * current index mid-fill (the very first populate can yank it to 0
         * before we centre on 7). The re-anchor guard must not see any of that
         * drift, so latch the recentre before touching the model — not just
         * after centring.
         */
        root.recentering = true
        recenterLatch.restart()

        const days = [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday"
        ]

        let today = new Date(anchor)
        today.setHours(0, 0, 0, 0)

        calendarModel.clear()
        for (let i = -root.trailDays; i <= root.leadDays; ++i) {
            let d = new Date(today)
            d.setDate(today.getDate() + i)
            calendarModel.append({
                timestamp: d.getTime(),
                weekday: days[d.getDay()],
                day: d.getDate(),
                month: Qt.locale().monthName(
                    d.getMonth(),
                    Locale.ShortFormat
                )
            })
        }

        root.selectedIndex = 7
        root.selectedDate = new Date(calendarModel.get(7).timestamp)

        root._instant = true
        wheel.currentIndex = initial ? 0 : 7
        root._instant = false
        recenterLatch.restart()

        if (initial)
            return

        /**
         * The ListView can still re-derive currentIndex on its own schedule
         * after we return (the refilled model yanks it back to 0 even right
         * after centring on 7). Re-assert the centre once the model has
         * settled, but never fight a live scroll.
         */
        Qt.callLater(function() {
            if (wheel.dragging || wheel.flicking)
                return
            root.recentering = true
            root._instant = true
            wheel.currentIndex = 7
            root._instant = false
            recenterLatch.restart()
        })
    }

    /** Calendar-day key ("YYYY-M-D") of a date, for the rollover check below. */
    function dayKeyOf(d) {
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    /** Day key the strip's window is currently anchored to. */
    property string _lastDay: ""

    Component.onCompleted: {
        root._lastDay = root.dayKeyOf(new Date())
        /** Construction parks the wheel a week behind (legacy opening state);
         *  the first face open glides it onto today. */
        rebuild(new Date(), true)
    }

    property bool _openingPlayed: false

    /**
     * Called by the hover face every time the pill opens. First open of the
     * session plays the legacy entrance sweep (a week behind, gliding onto
     * today); every later open snaps the wheel back to the current date so
     * the strip never reopens parked on a scrolled day — the way it used to
     * come up centred on today.
     */
    function onFaceOpened() {
        if (!root._openingPlayed) {
            root.playOpeningSweep()
            return
        }
        if (root.recentering || wheel.dragging || wheel.flicking)
            return
        var t = root.todayIndex()
        if (t === wheel.currentIndex)
            return
        root.snapToToday()
    }

    /**
     * One-shot legacy entrance sweep: on the first face open of a session the
     * wheel glides from the window's past edge — a week behind the real
     * today — onto today, the strip's original opening move. The wheel was
     * already parked at the past edge by the initial rebuild, so there is
     * nothing to rewind: the glide itself is the sweep, and it is safe even
     * when the strip is already visible (a reload that comes up hovered),
     * because the wheel has sat a week behind since birth — no visible yank.
     *
     * `_openingPlayed` latches only once the glide actually fires, so a
     * transient guard — typically the construction-time rebuild latch, which
     * a first open right after a shell reload can land inside — defers and
     * retries instead of burning the sweep forever.
     */
    function playOpeningSweep() {
        if (root._openingPlayed)
            return
        if (wheel.dragging || wheel.flicking) {
            sweepRetry.restart()
            return
        }
        /** The wheel has already moved off the past edge — the user scrolled,
         *  a rollover centred today, or a far re-anchor dropped today out of
         *  the window. Either way there is nothing to sweep. */
        if (wheel.currentIndex > 0) {
            root._openingPlayed = true
            return
        }
        /** Window not built yet — the face's open hook can fire before this
         *  strip's own construction completes (parent-first onCompleted
         *  order), which a reload that comes up hovered trips. Retry on a
         *  short tick: this resolves the moment the model lands, or the
         *  branch above latches once the wheel settles anywhere but 0. */
        if (root.todayIndex() !== 7 || wheel.currentIndex < 0) {
            sweepRetry.restart()
            return
        }
        root._openingPlayed = true
        /** Pin the soul bead to tomorrow's settled slot while the spring runs
         *  (released when the glide stops). The glide passes the low indices
         *  the edge guard watches — shield it for the glide's duration (the
         *  latch outlasts the spring). The construction latch is left running
         *  underneath, so the model-fill drift stays covered without making
         *  the sweep itself wait on it. Never armed as an idle return. */
        root.recentering = true
        recenterLatch.restart()
        root.sweeping = true
        sweepGlide.start()
    }

    /**
     * Quick springy glide for the one-shot opening sweep — the legacy wheel
     * spin (a short OutBack with overshoot), even faster than the strip's
     * usual glide so the first hover lands on today in a snap. Animating
     * currentIndex directly bypasses the wheel's Behavior, so the sweep keeps
     * its own pace while the shared glide stays tuned for scrolling/snaps.
     */
    NumberAnimation {
        id: sweepGlide
        target: wheel
        property: "currentIndex"
        from: 0
        to: 7
        duration: Math.round(Motion.fast * 1.3)
        easing.type: Easing.OutBack
        easing.overshoot: 0.8
        onFinished: root.sweeping = false
        onStopped: root.sweeping = false
    }

    /** True while the one-shot opening sweep's spring is still running; the
     *  soul-bead anchor stays pinned to tomorrow's settled slot meanwhile. */
    property bool sweeping: false


    /** Retry the one-shot sweep on a short tick for the window-not-built case
     *  (the very first open can fire before this strip's construction
     *  completes); the sweep's own recenter latch shields the model-fill
     *  drift meanwhile, so no wait on it is needed. */
    Timer {
        id: sweepRetry
        interval: 120
        onTriggered: root.playOpeningSweep()
    }

    /**
     * If the wall clock has moved to a new calendar day since the strip was
     * last built, re-anchor the window on the new today and snap the wheel
     * back to it. Shared by the midnight timer and the suspend-wake hook.
     */
    function rolloverCheck() {
        var d = new Date()
        var key = root.dayKeyOf(d)
        if (key !== root._lastDay) {
            root._lastDay = key
            root.rebuild(d)
        }
    }

    /**
     * True while the strip is re-anchoring its own window (scroll re-anchors
     * and idle returns). Re-centering moves the wheel to index 7 mid-gesture;
     * the flag keeps the re-anchor guard and the idle timer from reacting to
     * our own repositioning, and disables the currentIndex glide so a
     * re-anchored window lands in the same frame instead of sweeping past.
     */
    property bool recentering: false

    /** Index of the real today inside the current window, or -1 if scrolled out. */
    function todayIndex() {
        var key = root.dayKeyOf(new Date())
        for (var i = 0; i < calendarModel.count; ++i)
            if (root.dayKeyOf(new Date(calendarModel.get(i).timestamp)) === key)
                return i
        return -1
    }

    /** True when a delegate's timestamp is the actual next calendar day (real
     *  tomorrow), so the red highlight stays pinned to tomorrow instead of
     *  following the wheel's centre while it scrolls. */
    function isRealTomorrow(ts) {
        var d = new Date(ts)
        var now = new Date()
        var tmr = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
        return d.getFullYear() === tmr.getFullYear()
            && d.getMonth() === tmr.getMonth()
            && d.getDate() === tmr.getDate()
    }

    /** Index of the real next calendar day inside the current window, or -1
     *  once the wheel has scrolled it out of it. */
    function tomorrowIndex() {
        for (var i = 0; i < calendarModel.count; ++i)
            if (root.isRealTomorrow(calendarModel.get(i).timestamp))
                return i
        return -1
    }

    /** Real tomorrow's slot offset while it's inside the window, or null once
     *  the wheel has scrolled it out. */
    readonly property var nextDaySlot:
        root.tomorrowIndex() < 0 ? null : root.tomorrowIndex() - wheel.currentIndex

    /**
     * Slot offset of the pinned red day (real tomorrow). Once the one-shot
     * sweep has happened, the anchor tracks tomorrow's live slot as the wheel
     * scrolls. Before and during the opening sweep — the wheel sits a week
     * behind (index 0) and then springs onto today — the anchor is pinned to
     * tomorrow's settled slot (the post-sweep centre, index 7), so the soul
     * bead holds still under where tomorrow is coming to rest instead of
     * darting across the strip and whipping back with the sweep spring. Park
     * at slot 1 — just right of centre, the classic rest spot — once
     * tomorrow has been scrolled out of the window.
     */
    readonly property real nextSlot:
        root.nextDaySlot === null
        ? 1
        : ((root.sweeping || !root._openingPlayed)
            ? root.tomorrowIndex() - 7
            : root.nextDaySlot)

    /**
     * Idle return to the real today. After `idleReturnMs` with nothing
     * touching the strip, the wheel glides back so today is centred again —
     * the hover dates always settle on the real day after a pause instead of
     * parking on whatever day the last scroll left behind. If the window has
     * been re-anchored past today it is rebuilt around the real today first.
     */
    property int idleReturnMs: 2000

    /**
     * True once the user has manually parked the wheel off today (a scroll
     * settle or a day-cell click) — only then is the idle return owed. Cleared
     * the moment the wheel is back on the real today. Keeping this separate
     * from mere pointer contact is what stops the countdown from ever being
     * armed — and the wheel from snapping — before the user actually scrolls,
     * so the very first scroll is never delayed or fought by it.
     */
    property bool _pendingReturn: false

    /** Park the wheel on a day: (re)arm the idle return when that day isn't
     *  the real today, else stand down. Called only from real scroll settles
     *  (wheel movement end) and day-cell clicks — never from hover contact,
     *  presses, or our own re-centring. */
    function parkOffToday() {
        var t = root.todayIndex()
        if (t === wheel.currentIndex) {
            root._pendingReturn = false
            returnTimer.stop()
            return
        }
        root._pendingReturn = true
        returnTimer.restart()
    }

    /** Re-arm the idle return only when a return is already owed (the wheel
     *  was parked off today and hasn't settled back); otherwise stay off. */
    function armIdleReturn() {
        if (!root._pendingReturn)
            return
        root.parkOffToday()
    }

    Timer {
        id: recenterLatch
        interval: Math.round(Motion.morph) + 150
        onTriggered: root.recentering = false
    }

    /**
     * Re-centre the wheel on the real today, rebuilding the window if needed.
     * The glide back is guarded by `recentering` so the strip never re-anchors
     * or idles mid-flight; the idle timer is re-armed by each index change the
     * glide passes and stops once today is centred.
     */
    function snapToToday() {
        if (root.recentering)
            return
        var t = root.todayIndex()
        if (t === wheel.currentIndex)
            return
        /** The return is happening now — no idle return is owed any more. */
        root._pendingReturn = false
        root.recentering = true
        root.hoveredIndex = -1
        if (t >= 0) {
            wheel.currentIndex = t
        } else {
            /** rebuild() centres the fresh window on the real today. */
            root.rebuild(new Date())
        }
        recenterLatch.restart()
    }

    /**
     * Re-anchor the window on the day currently centred when the wheel nears
     * an edge, so scrolling can keep going past the original lead. The centred
     * date is preserved (it becomes the new index 7) and the Behaviour glide
     * is bypassed so the strip re-positions in one frame.
     */
    function reanchorWindow() {
        if (root.recentering)
            return
        var idx = wheel.currentIndex
        if (idx < 0 || idx >= calendarModel.count)
            return
        root.recentering = true
        root.hoveredIndex = -1
        /** rebuild() centres the fresh window on the day we were on. */
        root.rebuild(new Date(calendarModel.get(idx).timestamp))
        recenterLatch.restart()
    }

    Timer {
        id: returnTimer
        interval: root.idleReturnMs
        onTriggered: {
            /**
             * A live drag or flick is still touching the strip — hold off
             * until the gesture settles.
             */
            if (wheel.dragging || wheel.flicking) {
                returnTimer.restart()
                return
            }
            /**
             * Our own re-centre is still latched — re-arm instead of dropping,
             * so the return to today still lands once the strip settles.
             */
            if (root.recentering) {
                returnTimer.restart()
                return
            }
            /**
             * A day cell is parked under the cursor — leave it alone. The
             * timer is re-armed when the pointer leaves, so the strip returns
             * to today two seconds after the pointer moves away.
             */
            if (root.hoveredIndex >= 0)
                return
            root.snapToToday()
        }
    }

    /**
     * The day window is anchored to "today" at index 7 and built once on
     * creation. Rebuild it when the calendar day rolls over at midnight, so
     * the strip centres the new today and the red next-day highlight lands on
     * the real tomorrow without a shell reload.
     */
    Timer {
        id: dayTimer
        interval: 1000
        repeat: true
        onTriggered: root.rolloverCheck()
    }

    /**
     * The shared logind wake monitor (one dbus-monitor for the whole shell,
     * not one per pill) fires `resumed` the moment the session wakes, so a
     * wall clock that jumped while suspended is re-anchored immediately
     * instead of waiting for the next timer tick. If the monitor is down, the
     * 1s timer alone still covers the rollover.
     */
    Connections {
        target: SuspendWatch
        function onResumed() { root.rolloverCheck() }
    }

    ListView {
        id: wheel

        anchors.left: parent.left
        anchors.right: parent.right
        y: 5
        height: parent.height
        z: 1

        orientation: ListView.Horizontal
        model: calendarModel

        spacing: 10

        readonly property real delegateWidth: 40
        readonly property real slotWidth: delegateWidth + spacing

        readonly property real centerPadding: (width - delegateWidth) / 2

        leftMargin: centerPadding
        rightMargin: centerPadding

        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange

        preferredHighlightBegin: centerPadding
        preferredHighlightEnd: centerPadding

        Behavior on currentIndex {
            /** Re-anchor sets bypass the glide so the strip re-centres in one frame. */
            enabled: !root._instant
            NumberAnimation {
                duration: Motion.morph
                easing.type: Motion.easeMorph
                easing.bezierCurve: Motion.morphCurve
            }
        }

        delegate: Item {
            id: dayDelegate

            width: wheel.delegateWidth
            height: wheel.height

            /** Actual physical position during scrolling. */
            readonly property real centerOffset:
                (x + width / 2) -
                (wheel.contentX + wheel.width / 2)

            readonly property real distance:
                Math.abs(
                    centerOffset / wheel.slotWidth
                )

            readonly property real proximity:
                Math.max(
                    0,
                    1 -
                    Math.min(distance, 1.5) / 1.5
                )

            /** Pinned to the actual next calendar day, not the day after the
             *  wheel's centre — the red highlight stays on real tomorrow while
             *  the strip scrolls. */
            readonly property bool nextDay:
                root.isRealTomorrow(model.timestamp)

            readonly property color baseTint:
                nextDay
                ? Theme.vermLit
                : Theme.dim

            /**
             * How far the full weekday name has faded in. Only ramps when the
             * day is essentially centred (distance < ~0.33 slot), so two
             * adjacent days can never both show full titles while the wheel
             * settles; the rest keep a single letter, cross-faded for a clean
             * pass.
             */
            readonly property real nameFocus:
                Math.max(
                    0,
                    Math.min(
                        1,
                        (dayDelegate.proximity - 0.78) / 0.22
                    )
                )

            scale:
                0.88 +
                (0.12 * proximity)

            Column {
                anchors.centerIn: parent

                anchors.verticalCenterOffset:
                    6 -
                    (6 * dayDelegate.proximity)

                opacity:
                    0.6 +
                    (0.4 * dayDelegate.proximity)

                spacing: 2

                /**
                 * Letter and full name overlay the same spot (a Column would
                 * stack them, shoving the day number down as the name fades in).
                 */
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter

                    width: wheel.delegateWidth
                    height: 14

                    Text {
                        anchors.centerIn: parent

                        text: model.weekday.charAt(0)

                        color:
                            root.lerpColor(
                                dayDelegate.baseTint,
                                Theme.cream,
                                dayDelegate.proximity
                            )

                        font.family: Theme.font

                        font.pixelSize:
                            10 +
                            dayDelegate.proximity

                        font.weight:
                            dayDelegate.proximity > 0.55
                            ? Font.Bold
                            : Font.Medium

                        horizontalAlignment:
                            Text.AlignHCenter

                        opacity: 1 - dayDelegate.nameFocus
                    }

                    Text {
                        anchors.centerIn: parent

                        text: model.weekday

                        color:
                            root.lerpColor(
                                dayDelegate.baseTint,
                                Theme.cream,
                                dayDelegate.proximity
                            )

                        font.family: Theme.font

                        font.pixelSize:
                            10 +
                            dayDelegate.proximity

                        font.weight: Font.Bold

                        horizontalAlignment:
                            Text.AlignHCenter

                        opacity: dayDelegate.nameFocus
                        scale: 0.92 + 0.08 * dayDelegate.nameFocus
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: model.day

                    color:
                        root.lerpColor(
                            dayDelegate.baseTint,
                            Theme.bright,
                            dayDelegate.proximity
                        )

                    font.family: Theme.font

                    font.pixelSize:
                        15 +
                        (3 * dayDelegate.proximity)

                    font.weight:
                        dayDelegate.proximity > 0.55
                        ? Font.Black
                        : Font.DemiBold

                    font.features: {
                        "tnum": 1
                    }

                    horizontalAlignment:
                        Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent

                hoverEnabled: true

                onContainsMouseChanged: {
                    if (containsMouse) {
                        root.hoveredIndex = index
                        if (root.pillRef && root.ameEnabled)
                            root.pillRef.soulTarget = "calendar"
                    } else if (root.hoveredIndex === index) {
                        root.hoveredIndex = -1
                        /**
                         * Leaving a hovered day restarts the return countdown
                         * only when a manual scroll or click parked the wheel
                         * off today — mere pointer contact never arms it, so
                         * the first scroll is never delayed by the idle return.
                         */
                        root.armIdleReturn()
                    }
                }

                onClicked: {
                    root.hoveredIndex = index
                    wheel.currentIndex = index
                    root.parkOffToday()
                    root.openCalendar(new Date(model.timestamp))
                }
            }
        }

        onCurrentIndexChanged: {
            if (currentIndex >= 0 &&
                currentIndex < calendarModel.count) {

                root.selectedIndex = currentIndex

                root.selectedDate =
                    new Date(
                        calendarModel.get(currentIndex).timestamp
                    )
            }
            /**
             * Near a window edge the wheel would otherwise stop: re-anchor the
             * window on the centred day so scrolling can keep going. Skipped
             * while we are re-centring ourselves or mid-gesture, so an active
             * drag or our own return glide never trips it.
             */
            if (!root.recentering && !wheel.dragging && !wheel.flicking) {
                if (currentIndex <= root.edgeRunway - 1
                    || currentIndex >= calendarModel.count - root.edgeRunway - 1)
                    root.reanchorWindow()
            }
        }

        /** A manual scroll that settles on a day is what parks the wheel: the
         *  idle return to today is armed from here — and only from here, plus
         *  day-cell clicks — never from hovering or pressing. */
        onMovementEnded: root.parkOffToday()
    }
}

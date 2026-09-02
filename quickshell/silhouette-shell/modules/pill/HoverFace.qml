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

    /** Exposed for the pill's idle cleaner (reclaims the media bud). */
    property alias mediaBud: hoverMedia

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
     * The clock grows out of the rest clock's spot and shrinks back into
     * it: one continuous scale+slide driven by clockMorph. clockMorph is
     * clockHop itself, so the flight rides the pill body's own morph easing
     * (Motion.morph's bezier): the clock travels to its settled spot above
     * the dates in exact sync with the pill's growth — same acceleration,
     * same settle, no lead and no overshoot. The rest-to-hover handoff is a
     * separate quick crossfade (clockHandoff) in the first moments, while
     * the hover clock still sits exactly on the rest clock at the same
     * size — so the swap is invisible and the growth reads as one clock
     * smoothly travelling to its place.
     */
    readonly property real clockProgress: Math.max(0, Math.min(1, clockHop))
    readonly property real clockMorph: clockProgress
    /**
     * Handoff tied to clockMorph: the hover clock is pixel-identical to the
     * rest clock at morph=0, so the swap completes in the final moments of the
     * flight while the two are still (within a couple of px of) coincident —
     * a wider window would crossfade a clock still sliding into place and
     * read as a shimmer at the settle.
     */
    readonly property real clockHandoff: { var t = Math.max(0, Math.min(1, clockMorph / 0.03)); return t * t * (3 - 2 * t); }

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
     * The rest clock's centre, captured once the moment hover mode begins
     * (while the pill is still at rest geometry) so the flight is a clean
     * straight line instead of chasing a live mapToItem mid-morph — the old
     * binding re-mapped an invisible hover target every frame and jumped.
     * Measured in hoverClock's frame — the same frame the flight Translate
     * lives in — so start and end are directly comparable.
     */
    property real clockStartX: 0
    property real clockStartY: 0

    function captureClockStart() {
        if (!restClock)
            return;
        const p = restClock.mapToItem(hoverClock, restClock.width / 2, restClock.height / 2);
        clockStartX = p.x;
        clockStartY = p.y;
    }

    /**
     * Fires on every rest-to-hover hop. The pill is still at rest geometry
     * here (the height Behavior starts a tick later), so the capture is
     * exact. The onCompleted guard covers the one path where live is true
     * from birth — a monitor hotplug while its pill is peeked — so a
     * collapse then still flies from the rest clock's real position.
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

        Row {
            id: statusRow

            anchors.verticalCenter: parent.verticalCenter

            spacing: 12 * host.s

            opacity: face.mediaMorph

            transform: Translate {
                x: 56 * host.s * (1 - face.mediaMorph)
            }

            Loader {
                id: hoverMedia

                anchors.verticalCenter: parent.verticalCenter

                x: -72 * host.s * (1 - face.mediaMorph)

                /**
                 * Drops the bud the instant any surface opens, before the
                 * hover face's own fade finishes, so the incoming surface
                 * never fades in over a second copy of the now-playing card.
                 * The close path is handled by faceArrive's crossfade above,
                 * which holds the whole hover face (bud included) until the
                 * closing surface has dissolved.
                 */
                opacity: face.mediaMorph * (host.surfaceOpen ? 0 : 1)
                scale: 0.78 + 0.22 * face.mediaMorph

                active: host.hasMedia
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

                    onRequestClose: {
                        hoverMedia.active = false
                    }
                }
            }

            /** Keyboard ring around the focused hover-face media bud. */
            Rectangle {
                anchors.fill: hoverMedia
                anchors.margins: -3 * host.s
                visible: host.faceFocus >= 0 && host.faceFocus < host.faceCount
                    && host.faceTargets[host.faceFocus] === "media"
                radius: 14 * host.s
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(Theme.vermLit, 0.65)
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
                opacity: face.mediaMorph
                scale: 0.9 + 0.1 * face.mediaMorph
            }

            MinimizedTray {
                id: minimized

                anchors.verticalCenter: parent.verticalCenter

                s: host.s
                screenName: host.screenName

                enabled: face.live
                visible: count > 0

                opacity: face.trayMorph
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
                opacity: 0.7 * face.trayMorph
            }

            Tray {
                id: tray
                anchors.verticalCenter: parent.verticalCenter

                s: host.s
                barWindow: host.barWindow

                enabled: face.live

                opacity: face.trayMorph
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
                        x: (face.clockStartX - face.clockEndX) * (1 - face.clockMorph)
                        y: (face.clockStartY - face.clockEndY) * (1 - face.clockMorph)
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

                        opacity: face.clockHandoff
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
                    opacity: face.calendarMorph
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

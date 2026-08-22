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
        hoveredIndex >= 0 ? hoveredIndex - wheel.currentIndex : 1

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

    /**
     * Build the strip's day window so index 7 is `anchor` (the real today),
     * with a week of history behind and two weeks ahead. Called once on
     * creation.
     */
    function rebuild(anchor) {
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
        for (let i = -7; i <= 14; ++i) {
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
    }

    Component.onCompleted: {
        rebuild(new Date())
        wheel.currentIndex = 7
    }

    ListView {
        id: wheel

        anchors.fill: parent
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

            readonly property bool nextDay:
                index > wheel.currentIndex &&
                index === wheel.currentIndex + 1

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
                    }
                }

                onClicked: {
                    root.hoveredIndex = index
                    wheel.currentIndex = index
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
        }
    }
}

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.animation

Item {
    id: root

    width: 320
    height: 64

    property bool ameEnabled: false
    property var pillRef: null

    property int selectedIndex: 7
    property date selectedDate: new Date()

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

        Component.onCompleted: {
            const days = [
                "Sunday",
                "Monday",
                "Tuesday",
                "Wednesday",
                "Thursday",
                "Friday",
                "Saturday"
            ]

            let today = new Date()
            today.setHours(0, 0, 0, 0)

            for (let i = -7; i <= 14; ++i) {
                let d = new Date(today)
                d.setDate(today.getDate() + i)

                append({
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
            root.selectedDate = new Date(
                get(7).timestamp
            )

            wheel.currentIndex = 7
        }
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
                duration: 450
                easing.type: Easing.OutBack
                easing.overshoot: 0.8
            }
        }

        delegate: Item {
            id: dayDelegate

            width: wheel.delegateWidth
            height: wheel.height

            // Actual physical position during scrolling.
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

            readonly property bool expanded:
                proximity > 0.5

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

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text:
                        dayDelegate.expanded
                        ? model.weekday
                        : model.weekday.charAt(0)

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
                    if (containsMouse && root.pillRef)
                        root.pillRef.soulTarget = "calendar"
                }

                onClicked: {
                    wheel.currentIndex = index
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

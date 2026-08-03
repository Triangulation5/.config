import QtQuick
import QtQuick.Controls
import "Singletons"

Item {
    id: root

    width: 320
    height: 64

    property int selectedIndex: 7
    property date selectedDate: new Date()

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

    Rectangle {
        anchors.left: parent.left
        width: 32
        height: parent.height
        z: 0

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.tileBg
            }

            GradientStop {
                position: 1
                color: Qt.alpha(Theme.tileBg, 0)
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        width: 32
        height: parent.height
        z: 0

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Theme.tileBg, 0)
            }

            GradientStop {
                position: 1
                color: Theme.tileBg
            }
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
        readonly property real centerPadding:
            (width - delegateWidth) / 2

        leftMargin: centerPadding
        rightMargin: centerPadding

        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange

        preferredHighlightBegin: centerPadding
        preferredHighlightEnd: centerPadding

        delegate: Item {
            id: dayDelegate

            width: wheel.delegateWidth
            height: wheel.height

            readonly property bool selected:
                index === wheel.currentIndex

            readonly property real distance:
                Math.abs(wheel.currentIndex - index)

            readonly property bool nextDay:
                index > wheel.currentIndex &&
                distance === 1

            scale: selected ? 1.0 : 0.9

            Behavior on scale {
                NumberAnimation {
                    duration: 150
                }
            }

            Column {
                anchors.centerIn: parent

                // Current date stays centered.
                // All side dates share the same lowered baseline.
                anchors.verticalCenterOffset:
                    dayDelegate.selected ? 0 : 6

                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: dayDelegate.selected
                          ? model.weekday
                          : model.weekday.charAt(0)

                    color: {
                        if (dayDelegate.selected)
                            return Theme.cream

                        if (dayDelegate.nextDay)
                            return Theme.vermLit

                        if (dayDelegate.distance === 1)
                            return Theme.subtle

                        return Theme.dim
                    }

                    font.family: Theme.font

                    font.pixelSize: dayDelegate.selected
                                     ? 11
                                     : 10

                    font.weight: dayDelegate.selected
                                  ? Font.Bold
                                  : Font.Medium

                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: model.day

                    color: {
                        if (dayDelegate.selected)
                            return Theme.bright

                        if (dayDelegate.nextDay)
                            return Theme.vermLit

                        if (dayDelegate.distance === 1)
                            return Theme.subtle

                        return Theme.dim
                    }

                    font.family: Theme.font

                    font.pixelSize: dayDelegate.selected
                                     ? 18
                                     : 15

                    font.weight: dayDelegate.selected
                                  ? Font.Black
                                  : Font.DemiBold

                    font.features: {
                        "tnum": 1
                    }

                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent

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

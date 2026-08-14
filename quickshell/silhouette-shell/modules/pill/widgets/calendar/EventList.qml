pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * The calendar editor's event list: the picked day's events as tappable rows
 * with a time meta line and a hover delete. Capped so a day stacked with
 * events scrolls instead of growing the surface. `surface` is the calendar
 * host, used for span formatting.
 */
Item {
    id: list

    property real s: 1.1
    property var surface: null
    property var events: []

    implicitHeight: edFlick.height

    Flickable {
        id: edFlick
        width: parent.width
        height: Math.min(edList.implicitHeight, 230 * list.s)
        contentHeight: edList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: edList
            width: edFlick.width
            spacing: 4 * list.s

            Text {
                visible: list.events.length === 0
                text: "Nothing yet"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * list.s
                font.weight: Font.Medium
                font.italic: true
            }

            Repeater {
                model: list.events

                Rectangle {
                    id: evRow
                    required property var modelData
                    width: edList.width
                    height: evBody.implicitHeight + 12 * list.s
                    radius: Motion.rSmall * list.s
                    color: evArea.hovered ? Theme.frameBg : "transparent"

                    /** "all day" or "09:00–10:00", a date span when multi-day, "every year" when recurring. */
                    readonly property string meta: {
                        var datePart = "";
                        if (evRow.modelData.endDate && evRow.modelData.endDate.length > 0)
                            datePart = list.surface.fmtSpan(evRow.modelData.date, evRow.modelData.endDate);
                        var t = evRow.modelData.time || "";
                        var e = evRow.modelData.endTime || "";
                        var timePart = t.length === 0 ? "all day"
                            : (e.length > 0 ? t + "–" + e : t);
                        var base = datePart.length > 0 ? datePart + " · " + timePart : timePart;
                        var r = evRow.modelData.recur;
                        if (r === "year") return "every year · " + base;
                        if (r === "month") return "every month · " + base;
                        return base;
                    }

                    HoverHandler { id: evArea }

                    Column {
                        id: evBody
                        anchors.left: parent.left
                        anchors.leftMargin: 8 * list.s
                        anchors.right: evDel.left
                        anchors.rightMargin: 6 * list.s
                        anchors.top: parent.top
                        anchors.topMargin: 6 * list.s
                        spacing: 2 * list.s

                        Text {
                            text: evRow.modelData.text
                            width: parent.width
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11 * list.s
                            font.weight: Font.Medium
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                        Text {
                            text: evRow.meta
                            width: parent.width
                            color: Theme.flameGlow
                            font.family: Theme.font
                            font.pixelSize: 9 * list.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: evDel
                        anchors.right: parent.right
                        anchors.rightMargin: 7 * list.s
                        anchors.top: parent.top
                        anchors.topMargin: 7 * list.s
                        width: 16 * list.s
                        height: 16 * list.s
                        opacity: evArea.hovered ? 1 : 0.32
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                        GlyphIcon {
                            anchors.fill: parent
                            name: "close"
                            color: delArea.containsMouse ? Theme.vermLit : Theme.iconDim
                            stroke: 1.6
                        }

                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            anchors.margins: -5 * list.s
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Events.remove(evRow.modelData.id)
                        }
                    }
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: parent
        s: list.s
        flick: edFlick
    }
}

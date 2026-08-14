pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * The calendar's month grid: header (kanji, month/year, prev/next nav),
 * weekday row and day cells sized to exactly the rows the month needs. All
 * date state and helpers live on the host surface (`host`); this view only
 * renders it and forwards picks and hovers.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    /**
     * Geometry the host surface needs for its Ame focus ring and implicit
     * height, exposed instead of reaching into internals.
     */
    readonly property real cellWidth: grid.width / 7
    readonly property real gridX: grid.x
    readonly property real gridY: grid.y
    readonly property real gridHeight: grid.y + host.rows * host.cellH + (host.rows - 1) * host.rowGap
    readonly property point glyphCenter: calGlyph.mapToItem(root, calGlyph.width / 2, -3 * s)
    readonly property point monthLabelCenter: monthLabel.mapToItem(root, -8 * s, monthLabel.height / 2)

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s

            Text {
                id: calGlyph
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "暦"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                id: monthLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.host.loc.standaloneMonthName(root.host.viewMonth, Locale.LongFormat)
                    + " " + root.host.viewYear
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.0 * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Repeater {
                model: [-1, 1]

                Rectangle {
                    id: nav
                    required property int modelData
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: Motion.rSmall * root.s
                    color: navArea.containsMouse ? Theme.frameBg : "transparent"
                    border.width: navArea.containsMouse ? 1 : 0
                    border.color: Theme.frameBorder

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 16 * root.s
                        height: 16 * root.s
                        name: nav.modelData < 0 ? "chevron-left" : "chevron-right"
                        color: navArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.8
                    }

                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.host.shiftMonth(nav.modelData)
                    }
                }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    Row {
        id: weekdays
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
            model: 7

            Item {
                id: wd
                required property int index
                readonly property bool weekend: index >= 5
                width: weekdays.width / 7
                height: 16 * root.s

                Text {
                    anchors.centerIn: parent
                    text: root.host.loc.standaloneDayName((wd.index + 1) % 7, Locale.NarrowFormat)
                    color: wd.weekend ? Theme.faint : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5 * root.s
                }
            }
        }
    }

    Grid {
        id: grid
        y: weekdays.y + weekdays.height + 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 7
        rowSpacing: root.host.rowGap
        columnSpacing: 0

        Repeater {
            model: root.host.rows * 7

            Item {
                id: cell
                required property int index
                readonly property int weekday: index % 7
                readonly property bool weekend: weekday >= 5
                width: grid.width / 7
                height: root.host.cellH

                readonly property int dayNum: index - root.host.offset + 1
                readonly property bool inMonth: dayNum >= 1 && dayNum <= root.host.monthLen
                readonly property bool current: inMonth && root.host.isToday(dayNum)
                readonly property string dayKey: inMonth ? root.host.dateKey(dayNum) : ""
                readonly property bool hasEvent: inMonth && Events.hasEvents(cell.dayKey)
                readonly property bool sel: inMonth && root.host.inRange(cell.dayKey)
                readonly property bool selEdge: cell.sel
                    && (cell.dayKey === root.host.rangeLo || cell.dayKey === root.host.rangeHi)
                readonly property int ghostNum: dayNum < 1
                    ? root.host.daysInMonth(root.host.viewYear, root.host.viewMonth - 1) + dayNum
                    : dayNum - root.host.monthLen

                Rectangle {
                    anchors.centerIn: parent
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: Motion.rSmall * root.s
                    color: cellArea.containsMouse && cell.inMonth && !cell.current
                        ? Qt.rgba(0.94, 0.88, 0.84, 0.04) : "transparent"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: Motion.rSmall * root.s
                    visible: cell.current || cell.sel
                    color: cell.sel && !cell.current ? Qt.alpha(Theme.vermLit, 0.12) : Theme.frameBg
                    border.width: 1
                    border.color: cell.selEdge ? Qt.alpha(Theme.vermLit, 0.55)
                        : (cell.sel ? Qt.alpha(Theme.vermLit, 0.22) : Theme.frameBorder)
                }

                /** Keyboard cursor ring: only on a plain day, so it never fights the sel / today frames. */
                Rectangle {
                    anchors.centerIn: parent
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: Motion.rSmall * root.s
                    visible: cell.inMonth && root.host.keyDay === cell.dayNum && !cell.current && !cell.sel
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(Theme.vermLit, 0.55)
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.inMonth ? cell.dayNum : cell.ghostNum
                    color: cell.inMonth
                        ? (cell.current ? Theme.todayWarm
                            : (cell.hasEvent ? Theme.flameGlow
                                : (cell.weekend ? Theme.subtle : Theme.cream)))
                        : Theme.ghost
                    opacity: cell.inMonth && !cell.current && !cell.weekend && !cell.hasEvent ? 0.85 : 1.0
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: cell.current || cell.hasEvent ? Font.DemiBold : Font.Normal
                    font.features: { "tnum": 1 }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 9 * root.s
                    visible: cell.hasEvent && !cell.current
                    width: 3 * root.s
                    height: 3 * root.s
                    radius: width / 2
                    color: Theme.flameGlow
                }

                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: cell.inMonth
                    cursorShape: cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (cell.inMonth) {
                        root.host.keyDay = cell.dayNum;
                        root.host.selectDay(cell.dayNum);
                    }
                    onContainsMouseChanged: if (root.host.pickingEnd && cell.inMonth && containsMouse)
                        root.host.hoverDay = cell.dayNum
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: grid.horizontalCenter
        anchors.top: grid.bottom
        anchors.topMargin: 6 * root.s
        visible: root.host.pickingEnd
        text: "click the end day"
        color: Theme.flameGlow
        font.family: Theme.font
        font.pixelSize: 9 * root.s
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4 * root.s
    }

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: grid.bottom
        anchors.bottom: parent.bottom
        enabled: root.host.editorShown && !root.host.pickingEnd
        onClicked: {
            root.host.selectedDate = "";
            root.host.selEndDate = "";
            root.host.pickingEnd = false;
        }
    }
}

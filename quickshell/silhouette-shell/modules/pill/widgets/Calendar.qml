pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import qs.modules.pill.widgets

/**
 * Calendar surface: a weather glance, the month grid, and an event editor that
 * grows out to the right when a day is picked.
 *
 * The centre is the month grid (header with month/year and prev/next nav, weekday
 * row, day cells sized to exactly the rows the month needs). Today keeps its warm
 * frame and the Ame ring; a day that holds a stored event marks its number warm
 * with a small ember dot. To the left, when Weather.ready, a slim panel shows the
 * current temperature, the condition kanji and city, and the next few hours. To
 * the right, selecting a day slides open an editor listing that day's events with
 * a delete tap and an add form (start, end, title).
 *
 * The date math (offset/monthLen/rows/today/shiftMonth/resetToday) is unchanged;
 * the grid is wrapped, not rewritten. implicitWidth sums the visible panels so the
 * pill morphs wider as the editor opens; implicitHeight still drives the height
 * down to the live row count. View date resets to the real today on every open,
 * and Ame keeps targeting today via ameForm/amePoint.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 18
    mRight: 18
    mBottom: 16

    readonly property var loc: Qt.locale("en_US")

    readonly property date today: sysClock.date
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    /**
     * Date the surface should open focused on (set by a hover-strip click), or
     * null to open on the real today. Applied on every open, including the very
     * first lazy creation where `active` never changes.
     */
    property var targetDate: null

    readonly property int offset: firstWeekdayOffset(viewYear, viewMonth)
    readonly property int monthLen: daysInMonth(viewYear, viewMonth)
    readonly property int rows: Math.ceil((offset + monthLen) / 7)

    readonly property real cellH: 24 * s
    readonly property real rowGap: 2 * s

    readonly property real gridW: 282 * s
    readonly property real weatherW: 152 * s
    readonly property real editorW: 196 * s
    readonly property real gutter: 16 * s

    readonly property bool weatherShown: Weather.ready
    readonly property bool editorShown: selectedDate.length > 0

    /**
     * Selection: selectedDate is the picked day (and a span's start), selEndDate
     * the span's last day or "" for a single day. pickingEnd arms the grid so the
     * next day click closes the span; hoverDay previews that span live while the
     * pointer moves. Keys are zero-padded "YYYY-MM-DD" so a string compare spans
     * them, even across months.
     */
    property string selectedDate: ""
    property string selEndDate: ""
    property bool pickingEnd: false
    property int hoverDay: 0

    /**
     * Keyboard-focused day in the viewed month (1..monthLen, 0 = none). Arrows
     * walk it inside the month, Return selects it; the grid's existing sel /
     * today frames still take precedence visually.
     */
    property int keyDay: 0
    readonly property bool keyed: keyDay > 0

    function kbMove(axis, dir) {
        if (keyDay < 1 || keyDay > monthLen)
            keyDay = focusDay > 0 ? focusDay : today.getDate();
        var next = axis === "h" ? keyDay + dir : keyDay + dir * 7;
        if (next >= 1 && next <= monthLen) {
            keyDay = next;
            return;
        }
        /** Crossed an edge: page the neighbouring month, keeping the column. */
        var d = new Date(viewYear, viewMonth, keyDay);
        d.setDate(d.getDate() + (axis === "h" ? dir : dir * 7));
        shiftMonth((d.getFullYear() - viewYear) * 12 + (d.getMonth() - viewMonth));
        keyDay = d.getDate();
    }

    /** Return on the grid: select (or toggle) the keyboard-focused day. */
    function kbActivate() {
        if (keyDay < 1 || keyDay > monthLen)
            keyDay = focusDay > 0 ? focusDay : today.getDate();
        selectDay(keyDay);
    }

    /** Dismiss the event editor and any pending span, for Backspace. */
    function closeEditor() {
        selectedDate = "";
        selEndDate = "";
        pickingEnd = false;
        hoverDay = 0;
    }

    /** Span end the grid paints: the live hover while arming, else the set end. */
    readonly property string rangeEndKey: pickingEnd && hoverDay > 0 ? dateKey(hoverDay) : selEndDate
    readonly property string rangeLo: {
        if (selectedDate.length === 0) return "";
        var b = rangeEndKey;
        if (b.length === 0) return selectedDate;
        return selectedDate < b ? selectedDate : b;
    }
    readonly property string rangeHi: {
        if (selectedDate.length === 0) return "";
        var b = rangeEndKey;
        if (b.length === 0) return selectedDate;
        return selectedDate < b ? b : selectedDate;
    }
    function inRange(key) {
        return key.length > 0 && rangeLo.length > 0 && key >= rangeLo && key <= rangeHi;
    }

    /** "ddd d MMM" for a single day, "d MMM" without the weekday. */
    function fmtDay(key, dow) {
        var p = key.split("-");
        var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        return loc.toString(d, dow ? "ddd d MMM" : "d MMM");
    }

    /** "22–25 Jun" within a month, "29 Jun – 2 Jul" across one. */
    function fmtSpan(loKey, hiKey) {
        var lp = loKey.split("-");
        var hp = hiKey.split("-");
        if (lp[0] === hp[0] && lp[1] === hp[1]) {
            var d = new Date(Number(lp[0]), Number(lp[1]) - 1, Number(lp[2]));
            return Number(lp[2]) + "–" + Number(hp[2]) + " " + loc.toString(d, "MMM");
        }
        return fmtDay(loKey, false) + " – " + fmtDay(hiKey, false);
    }

    readonly property real gridHeight: grid.y + rows * cellH + (rows - 1) * rowGap

    /** The weather panel and the editor each add their column plus a divider gutter only when visible. */
    implicitWidth: gridW
        + (weatherShown ? weatherW + gutter : 0)
        + (editorShown ? editorW + gutter : 0)

    implicitHeight: editorShown ? Math.max(gridHeight, editor.contentHeight) : gridHeight

    readonly property bool todayVisible: viewMonth === today.getMonth()
        && viewYear === today.getFullYear()

    /**
     * Ame is the focus cursor: it rings the picked day, or today when this month
     * is in view with nothing picked. Browsing another month with nothing picked
     * leaves no focus, so the bead parks as a soul ember on the 暦 header glyph
     * (the calendar's lantern, mirroring Sysmon) rather than floating over a
     * random date cell — which is what read as Ame jumping somewhere random.
     */
    readonly property bool selectedInView: selectedDate.length > 0
        && Number(selectedDate.split("-")[1]) === viewMonth + 1
        && Number(selectedDate.split("-")[0]) === viewYear
    readonly property int focusDay: selectedInView
        ? Number(selectedDate.split("-")[2])
        : (todayVisible ? today.getDate() : 0)
    readonly property bool focused: focusDay > 0
    readonly property int focusIndex: offset + focusDay - 1
    readonly property real cellW: grid.width / 7
    readonly property real focusX: gridPane.x + grid.x + (focusIndex % 7 + 0.5) * cellW
    readonly property real focusY: gridPane.y + grid.y + (Math.floor(focusIndex / 7) + 0.5) * (cellH + rowGap) - rowGap / 2

    readonly property point soulPoint: {
        void width;
        void height;
        if (Flags.showGlyphs)
            return calGlyph.mapToItem(root, calGlyph.width / 2, -3 * s);
        return monthLabel.mapToItem(root, -8 * s, monthLabel.height / 2);
    }

    ameForm: focused ? "ring" : "soul"
    amePoint: focused ? Qt.point(focusX, focusY) : soulPoint

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    function firstWeekdayOffset(year, month) {
        var d = new Date(year, month, 1).getDay();
        return (d + 6) % 7;
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function isToday(day) {
        return day === today.getDate()
            && viewMonth === today.getMonth()
            && viewYear === today.getFullYear();
    }

    /** "YYYY-MM-DD" for a day number in the viewed month, zero-padded for keys. */
    function dateKey(day) {
        var m = viewMonth + 1;
        var mm = m < 10 ? "0" + m : "" + m;
        var dd = day < 10 ? "0" + day : "" + day;
        return viewYear + "-" + mm + "-" + dd;
    }

    function shiftMonth(delta) {
        var m = viewMonth + delta;
        var y = viewYear;
        while (m < 0) { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        viewMonth = m;
        viewYear = y;
        hoverDay = 0;
        keyDay = 0;
        if (!pickingEnd) {
            selectedDate = "";
            selEndDate = "";
        }
    }

    function resetToday() {
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
        selectedDate = "";
        selEndDate = "";
        pickingEnd = false;
        hoverDay = 0;
        keyDay = 0;
    }

    /**
     * Click handling: while arming a span the next click sets its end (clicking
     * the start again drops the span); a click below the start swaps the two so
     * the earlier day stays the start. Otherwise it toggles a single day and
     * re-clicking the open day closes the editor.
     */
    function selectDay(day) {
        var key = dateKey(day);
        if (pickingEnd) {
            pickingEnd = false;
            hoverDay = 0;
            if (key === selectedDate)
                selEndDate = "";
            else if (key < selectedDate) {
                selEndDate = selectedDate;
                selectedDate = key;
            } else {
                selEndDate = key;
            }
            return;
        }
        if (selectedDate === key && selEndDate.length === 0) {
            selectedDate = "";
            return;
        }
        selectedDate = key;
        selEndDate = "";
    }

    /**
     * On open, reset to the real today; when a strip click supplied a target
     * date, jump to its month and select the day so Ame rings it and the editor
     * shows that date. Runs on every open — the onCompleted guard covers the
     * first lazy creation, where `active` is already true so the changed hook
     * never fires.
     */
    function applyFocusTarget() {
        resetToday();
        var t = targetDate;
        if (t) {
            viewYear = t.getFullYear();
            viewMonth = t.getMonth();
            selectDay(t.getDate());
            keyDay = t.getDate();
        }
    }

    onActiveChanged: if (active) applyFocusTarget()
    Component.onCompleted: if (active) applyFocusTarget()

    Item {
        id: weather
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.weatherShown ? root.weatherW : 0
        clip: true
        visible: width > 1
        opacity: root.weatherShown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        Column {
            id: wxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 6 * root.s
            spacing: 9 * root.s

            Row {
                spacing: 9 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.s
                    height: 32 * root.s
                    name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
                    color: Theme.todayWarm
                    stroke: 1.9
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: Weather.tempNow + "°"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 26 * root.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        text: Weather.labelFor(Weather.codeNow)
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Medium
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8 * root.s

                /**
                 * IP geolocation only ever resolves to the ISP city, so the town
                 * is editable in place: tap to type, which sets Flags.weatherCity
                 * and re-geocodes through Open-Meteo for the exact spot. Blank it
                 * to fall back to auto IP detection.
                 */
                Item {
                    id: cityBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - humidityRow.width - 8 * root.s
                    height: 14 * root.s

                    property bool editing: false

                    Text {
                        id: cityText
                        visible: !cityBox.editing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.city.length > 0 ? Weather.city : "set town"
                        color: cityArea.containsMouse ? Theme.subtle : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8 * root.s
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: cityArea
                        visible: !cityBox.editing
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cityField.text = Flags.weatherCity;
                            cityBox.editing = true;
                            cityField.forceActiveFocus();
                            cityField.selectAll();
                        }
                    }
                    TextField {
                        id: cityField
                        visible: cityBox.editing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        background: null
                        padding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8 * root.s
                        placeholderText: "town"
                        placeholderTextColor: Theme.faint
                        selectByMouse: true
                        selectionColor: Theme.verm
                        onAccepted: {
                            Flags.weatherCity = text.trim();
                            cityBox.editing = false;
                        }
                        Keys.onEscapePressed: cityBox.editing = false
                        onActiveFocusChanged: if (!activeFocus) cityBox.editing = false
                    }
                }
                Row {
                    id: humidityRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11 * root.s
                        height: 11 * root.s
                        name: "droplet"
                        color: Theme.faint
                        stroke: 1.6
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.humidity + "%"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle {
                width: wxCol.width
                height: 1
                color: Theme.hairSoft
            }

            Row {
                width: wxCol.width

                Repeater {
                    model: Weather.daily.slice(0, 4)

                    Column {
                        id: dayCol
                        required property var modelData
                        width: wxCol.width / 4
                        spacing: 5 * root.s

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCol.modelData.day
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9 * root.s
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.5 * root.s
                        }
                        GlyphIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 15 * root.s
                            height: 15 * root.s
                            name: Weather.glyphFor(dayCol.modelData.code, true)
                            color: Theme.subtle
                            stroke: 1.7
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCol.modelData.temp + "°"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2 * root.s

                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 9 * root.s
                                height: 9 * root.s
                                name: "droplet"
                                color: Theme.faint
                                stroke: 1.6
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dayCol.modelData.rh + "%"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 8.5 * root.s
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: weatherSeam
        anchors.left: weather.right
        anchors.leftMargin: root.gutter / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.hair
        visible: root.weatherShown
        opacity: weather.opacity
    }

    Item {
        id: gridPane
        anchors.left: root.weatherShown ? weather.right : parent.left
        anchors.leftMargin: root.weatherShown ? root.gutter : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.gridW

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
                    text: root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat)
                        + " " + root.viewYear
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
                            onClicked: root.shiftMonth(nav.modelData)
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
                        text: root.loc.standaloneDayName((wd.index + 1) % 7, Locale.NarrowFormat)
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
            rowSpacing: root.rowGap
            columnSpacing: 0

            Repeater {
                model: root.rows * 7

                Item {
                    id: cell
                    required property int index
                    readonly property int weekday: index % 7
                    readonly property bool weekend: weekday >= 5
                    width: grid.width / 7
                    height: root.cellH

                    readonly property int dayNum: index - root.offset + 1
                    readonly property bool inMonth: dayNum >= 1 && dayNum <= root.monthLen
                    readonly property bool current: inMonth && root.isToday(dayNum)
                    readonly property string dayKey: inMonth ? root.dateKey(dayNum) : ""
                    readonly property bool hasEvent: inMonth && Events.hasEvents(cell.dayKey)
                    readonly property bool sel: inMonth && root.inRange(cell.dayKey)
                    readonly property bool selEdge: cell.sel
                        && (cell.dayKey === root.rangeLo || cell.dayKey === root.rangeHi)
                    readonly property int ghostNum: dayNum < 1
                        ? root.daysInMonth(root.viewYear, root.viewMonth - 1) + dayNum
                        : dayNum - root.monthLen

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
                        visible: cell.inMonth && root.keyDay === cell.dayNum && !cell.current && !cell.sel
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
                            root.keyDay = cell.dayNum;
                            root.selectDay(cell.dayNum);
                        }
                        onContainsMouseChanged: if (root.pickingEnd && cell.inMonth && containsMouse)
                            root.hoverDay = cell.dayNum
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: grid.horizontalCenter
            anchors.top: grid.bottom
            anchors.topMargin: 6 * root.s
            visible: root.pickingEnd
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
            enabled: root.editorShown && !root.pickingEnd
            onClicked: {
                root.selectedDate = "";
                root.selEndDate = "";
                root.pickingEnd = false;
            }
        }
    }

    Rectangle {
        id: editorSeam
        anchors.left: gridPane.right
        anchors.leftMargin: root.gutter / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.hair
        visible: root.editorShown
        opacity: editor.opacity
    }

    CalendarEditor {
        id: editor
        anchors.left: gridPane.right
        anchors.leftMargin: root.gutter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.editorShown ? root.editorW : 0
        clip: true
        visible: width > 1
        opacity: root.editorShown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        surface: root
    }
}


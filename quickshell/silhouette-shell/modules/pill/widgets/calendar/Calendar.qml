pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.components.animation
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

    /** Forwards to the pill: the weather glance taps open the detail surface. */
    signal requestSurface(string name)

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
    readonly property real editorW: 196 * s
    readonly property real gutter: 16 * s

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

    readonly property real gridHeight: monthGrid.gridHeight

    /** The weather panel and the editor each add their column plus a divider gutter only when visible. */
    implicitWidth: gridW
        + (weatherPanel.shown ? weatherPanel.fullW + gutter : 0)
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
    readonly property real cellW: monthGrid.cellWidth
    readonly property real focusX: gridPane.x + monthGrid.gridX + (focusIndex % 7 + 0.5) * cellW
    readonly property real focusY: gridPane.y + monthGrid.gridY + (Math.floor(focusIndex / 7) + 0.5) * (cellH + rowGap) - rowGap / 2

    readonly property point soulPoint: {
        void width;
        void height;
        if (Flags.showGlyphs)
            return monthGrid.mapToItem(root, monthGrid.glyphCenter.x, monthGrid.glyphCenter.y);
        return monthGrid.mapToItem(root, monthGrid.monthLabelCenter.x, monthGrid.monthLabelCenter.y);
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

    WeatherPanel {
        id: weatherPanel
        s: root.s
        onOpenDetail: root.requestSurface("weather")
    }

    Rectangle {
        id: weatherSeam
        anchors.left: weatherPanel.right
        anchors.leftMargin: root.gutter / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.hair
        visible: weatherPanel.shown
        opacity: weatherPanel.opacity
    }


    Item {
        id: gridPane
        /**
         * Anchored to the weather panel's right edge even while it is
         * collapsed (width 0 puts it on the surface's left edge), so when
         * Weather.ready flips the grid is carried right by the panel's opening
         * glide instead of snapping. The gap follows the same liquid curve.
         */
        anchors.left: weatherPanel.right
        anchors.leftMargin: weatherPanel.shown ? root.gutter : 0
        Behavior on anchors.leftMargin {
            NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
        }
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.gridW

        MonthGrid {
            id: monthGrid
            anchors.fill: parent
            s: root.s
            host: root
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

    /** Content reveal latch: the editor text stays hidden until the shared 100ms delay after it grows out. */
    RevealLatch {
        id: editorReveal
        shown: root.editorShown
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
        opacity: (root.editorShown && editorReveal.ready) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        surface: root
    }
}

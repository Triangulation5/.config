pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import IslandBackend

FocusScope {
    id: root

    signal closeRequested()

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // Current navigation state
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property int selectedYear: new Date().getFullYear()
    property int selectedMonth: new Date().getMonth()
    property int selectedDay: new Date().getDate()

    // Fixed today references
    readonly property var todayDate: new Date()
    readonly property int todayYear: todayDate.getFullYear()
    readonly property int todayMonth: todayDate.getMonth()
    readonly property int todayDay: todayDate.getDate()

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    readonly property var monthNamesShort: [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    readonly property var weekdayNamesFull: [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ]

    readonly property bool isViewingCurrentMonth: viewYear === todayYear && viewMonth === todayMonth

    property var calendarCells: []

    readonly property string selectedDateFullText: {
        const d = new Date(root.selectedYear, root.selectedMonth, root.selectedDay);
        const dayName = root.weekdayNamesFull[d.getDay()];
        const monthName = root.monthNamesShort[root.selectedMonth];
        return dayName + ", " + root.selectedDay + " " + monthName + " " + root.selectedYear;
    }

    readonly property string relativeDateText: {
        const sel = new Date(root.selectedYear, root.selectedMonth, root.selectedDay);
        const tod = new Date(root.todayYear, root.todayMonth, root.todayDay);
        const diffMs = sel.getTime() - tod.getTime();
        const diffDays = Math.round(diffMs / 86400000);

        if (diffDays === 0) return "Today";
        if (diffDays === 1) return "Tomorrow";
        if (diffDays === -1) return "Yesterday";
        if (diffDays > 1) return "In " + diffDays + " days";
        return Math.abs(diffDays) + " days ago";
    }

    readonly property int selectedWeekNumber: {
        return root.getWeekNumber(root.selectedYear, root.selectedMonth, root.selectedDay);
    }

    focus: root.showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    clip: true

    opacity: root.showCondition ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: StyleTokens.durationStandard
            easing.type: Easing.InOutQuad
        }
    }

    Keys.onEscapePressed: function(event) {
        root.closeRequested();
        event.accepted = true;
    }

    Keys.onLeftPressed: function(event) {
        root.prevMonth();
        event.accepted = true;
    }

    Keys.onRightPressed: function(event) {
        root.nextMonth();
        event.accepted = true;
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) {
            root.goToToday();
            event.accepted = true;
        }
    }

    WheelHandler {
        orientation: Qt.Vertical
        onWheel: event => {
            if (event.angleDelta.y > 0) {
                root.prevMonth();
            } else if (event.angleDelta.y < 0) {
                root.nextMonth();
            }
        }
    }

    onShowConditionChanged: {
        if (root.showCondition) {
            root.forceActiveFocus();
            root.goToToday();
        }
    }

    Component.onCompleted: {
        root.updateCalendarModel();
    }

    function daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate();
    }

    function daysInPrevMonth(y, m) {
        return new Date(y, m, 0).getDate();
    }

    // Monday-based first day of week: 0 = Monday, ..., 6 = Sunday
    function firstDayOfWeek(y, m) {
        const day = new Date(y, m, 1).getDay();
        return (day + 6) % 7;
    }

    function updateCalendarModel() {
        const cells = [];
        const firstDay = root.firstDayOfWeek(root.viewYear, root.viewMonth);
        const daysCur = root.daysInMonth(root.viewYear, root.viewMonth);
        const daysPrev = root.daysInPrevMonth(root.viewYear, root.viewMonth);

        for (let i = 0; i < 42; i++) {
            let d, m, y, isCur = false;
            if (i < firstDay) {
                d = daysPrev - firstDay + i + 1;
                m = (root.viewMonth === 0 ? 11 : root.viewMonth - 1);
                y = (root.viewMonth === 0 ? root.viewYear - 1 : root.viewYear);
            } else if (i < firstDay + daysCur) {
                d = i - firstDay + 1;
                m = root.viewMonth;
                y = root.viewYear;
                isCur = true;
            } else {
                d = i - (firstDay + daysCur) + 1;
                m = (root.viewMonth === 11 ? 0 : root.viewMonth + 1);
                y = (root.viewMonth === 11 ? root.viewYear + 1 : root.viewYear);
            }

            cells.push({
                day: d,
                month: m,
                year: y,
                isCurMonth: isCur
            });
        }
        root.calendarCells = cells;
    }

    function prevMonth() {
        if (viewMonth === 0) {
            viewMonth = 11;
            viewYear -= 1;
        } else {
            viewMonth -= 1;
        }
        root.updateCalendarModel();
    }

    function nextMonth() {
        if (viewMonth === 11) {
            viewMonth = 0;
            viewYear += 1;
        } else {
            viewMonth += 1;
        }
        root.updateCalendarModel();
    }

    function goToToday() {
        const now = new Date();
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
        selectedYear = now.getFullYear();
        selectedMonth = now.getMonth();
        selectedDay = now.getDate();
        root.updateCalendarModel();
    }

    function selectDate(y, m, d) {
        const target = new Date(y, m, d);
        const targetY = target.getFullYear();
        const targetM = target.getMonth();
        const targetD = target.getDate();

        const monthChanged = (targetY !== root.viewYear || targetM !== root.viewMonth);
        root.selectedYear = targetY;
        root.selectedMonth = targetM;
        root.selectedDay = targetD;
        root.viewYear = targetY;
        root.viewMonth = targetM;

        if (monthChanged) {
            root.updateCalendarModel();
        }
    }

    function getWeekNumber(y, m, d) {
        const target = new Date(Date.UTC(y, m, d));
        target.setUTCDate(target.getUTCDate() + 4 - (target.getUTCDay() || 7));
        const yearStart = new Date(Date.UTC(target.getUTCFullYear(), 0, 1));
        return Math.ceil((((target.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // ──────────────────────────────────────────
        // 1. TOP HEADER BAR
        // ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 8

            // Calendar Vector Icon
            Shape {
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                preferredRendererType: Shape.CurveRenderer
                Layout.alignment: Qt.AlignVCenter

                ShapePath {
                    fillColor: StyleTokens.transparent
                    strokeColor: StyleTokens.accent
                    strokeWidth: 1.4
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: "M3 4a1.5 1.5 0 0 1 1.5-1.5h6A1.5 1.5 0 0 1 12 4v8a1.5 1.5 0 0 1-1.5 1.5h-6A1.5 1.5 0 0 1 3 12V4zm0 2.5h9M5 1.5v2M10 1.5v2"
                    }
                }
            }

            // Month & Year Label
            Text {
                text: root.monthNames[root.viewMonth] + " " + root.viewYear
                color: StyleTokens.textPrimaryBright
                font.family: root.textFontFamily
                font.pixelSize: 15
                font.weight: Font.Bold
                font.letterSpacing: -0.2
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // "Today" Button
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: todayLabel.implicitWidth + 16
                radius: 11
                color: todayMouse.containsMouse
                    ? StyleTokens.moduleHover
                    : (root.isViewingCurrentMonth ? "#1c2230" : StyleTokens.module)
                border.width: 1
                border.color: root.isViewingCurrentMonth ? "#2e4873" : StyleTokens.transparent

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: "Today"
                    color: root.isViewingCurrentMonth ? StyleTokens.accent : StyleTokens.textSecondary
                    font.family: root.textFontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: todayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToToday()
                }
            }

            // Previous Month Button
            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Shape {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    scale: prevMouse.pressed ? 0.85 : (prevMouse.containsMouse ? 1.08 : 1.0)
                    preferredRendererType: Shape.CurveRenderer
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    ShapePath {
                        fillColor: StyleTokens.transparent
                        strokeColor: prevMouse.containsMouse ? StyleTokens.textPrimaryBright : StyleTokens.textDim
                        strokeWidth: 1.5
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M9 3L4 7.5L9 12"
                        }
                    }
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.prevMonth()
                }
            }

            // Next Month Button
            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Shape {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    scale: nextMouse.pressed ? 0.85 : (nextMouse.containsMouse ? 1.08 : 1.0)
                    preferredRendererType: Shape.CurveRenderer
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    ShapePath {
                        fillColor: StyleTokens.transparent
                        strokeColor: nextMouse.containsMouse ? StyleTokens.textPrimaryBright : StyleTokens.textDim
                        strokeWidth: 1.5
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M5 3L10 7.5L5 12"
                        }
                    }
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.nextMonth()
                }
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#22252e"
        }

        // ──────────────────────────────────────────
        // 2. DAY NAMES HEADER (Mo, Tu, We, Th, Fr, Sa, Su)
        // ──────────────────────────────────────────
        Grid {
            id: dayNamesGrid
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            columns: 7
            columnSpacing: 4

            readonly property real colWidth: Math.max(0, (width - 6 * columnSpacing) / 7)

            Repeater {
                model: root.dayNames

                delegate: Item {
                    id: dayHeaderItem
                    required property string modelData
                    required property int index

                    width: dayNamesGrid.colWidth
                    height: dayNamesGrid.height

                    Text {
                        anchors.centerIn: parent
                        text: dayHeaderItem.modelData
                        color: (dayHeaderItem.index >= 5) ? StyleTokens.accentSoft : StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        // ──────────────────────────────────────────
        // 3. 42-CELL DAYS GRID (6 rows x 7 cols)
        // ──────────────────────────────────────────
        Grid {
            id: daysGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            columnSpacing: 4
            rowSpacing: 3

            readonly property real cellWidth: Math.max(0, (width - 6 * columnSpacing) / 7)
            readonly property real cellHeight: Math.max(0, (height - 5 * rowSpacing) / 6)

            Repeater {
                model: root.calendarCells

                delegate: Rectangle {
                    id: cellRect
                    required property var modelData
                    required property int index

                    width: daysGrid.cellWidth
                    height: daysGrid.cellHeight
                    radius: 7

                    readonly property int cellDay: modelData.day
                    readonly property int cellMonth: modelData.month
                    readonly property int cellYear: modelData.year
                    readonly property bool isCurMonth: modelData.isCurMonth

                    readonly property bool isToday: cellYear === root.todayYear
                        && cellMonth === root.todayMonth
                        && cellDay === root.todayDay

                    readonly property bool isSelected: cellYear === root.selectedYear
                        && cellMonth === root.selectedMonth
                        && cellDay === root.selectedDay

                    // Styling
                    color: isToday
                        ? StyleTokens.accent
                        : (isSelected
                            ? "#1e2433"
                            : (cellMouse.containsMouse ? "#1c1f28" : StyleTokens.transparent))

                    border.width: (isSelected && !isToday) ? 1 : 0
                    border.color: (isSelected && !isToday) ? StyleTokens.accent : StyleTokens.transparent

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: String(cellRect.cellDay)
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        font.weight: (cellRect.isToday || cellRect.isSelected) ? Font.Bold : Font.Normal
                        color: {
                            if (cellRect.isToday) return "#ffffff";
                            if (cellRect.isSelected) return StyleTokens.accent;
                            if (cellRect.isCurMonth) return StyleTokens.textPrimaryBright;
                            return "#424552"; // Dimmed for other months
                        }
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectDate(cellRect.cellYear, cellRect.cellMonth, cellRect.cellDay);
                        }
                    }
                }
            }
        }

        // ──────────────────────────────────────────
        // 4. FOOTER DETAILS STRIP
        // ──────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: "#161820"
            border.width: 1
            border.color: "#21242e"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // Selected date readable string
                Text {
                    text: root.selectedDateFullText
                    color: StyleTokens.textPrimaryBright
                    font.family: root.textFontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // Relative day badge (e.g. "Today", "In 3 days")
                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: relativeText.implicitWidth + 12
                    radius: 9
                    color: root.relativeDateText === "Today" ? "#192842" : "#1e2129"
                    border.width: 1
                    border.color: root.relativeDateText === "Today" ? "#2b4570" : "#282c37"

                    Text {
                        id: relativeText
                        anchors.centerIn: parent
                        text: root.relativeDateText
                        color: root.relativeDateText === "Today" ? StyleTokens.accent : StyleTokens.textSecondary
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                // Week Number badge
                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: weekText.implicitWidth + 10
                    radius: 4
                    color: "#181a22"

                    Text {
                        id: weekText
                        anchors.centerIn: parent
                        text: "W" + root.selectedWeekNumber
                        color: StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}

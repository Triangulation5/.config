import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.pill.widgets
import qs.modules.settings
import qs.components.icons
import qs.components.controls

/**
 * Event editor panel for the calendar surface: the picked day's events with a
 * delete tap, plus an add form (title, all-day/timed times, repeat, and an
 * optional multi-day span armed from the grid). The host (Calendar.qml)
 * slides it out beside the grid and reads the panel's state through its
 * properties.
 */
Item {
    id: editor

    /** The calendar surface this panel belongs to: date state, formatting
     *  helpers and scale. */
    property var surface: null

    /** Height of the day-list column, so the host can size itself to it. */
    readonly property real contentHeight: edCol.implicitHeight

    /** Events covering the picked day (a span's start), empty until a day is picked. */
    readonly property var dayEvents: surface.selectedDate.length > 0
        ? Events.forDate(surface.selectedDate) : []

    /** Single day reads "Mon 9 Jun"; a span reads its range. */
    readonly property string heading: {
        if (surface.selectedDate.length === 0)
            return "";
        if (surface.selEndDate.length === 0)
            return surface.fmtDay(surface.selectedDate, true);
        return surface.fmtSpan(surface.rangeLo, surface.rangeHi);
    }

    readonly property string spanLabel: surface.selEndDate.length === 0
        ? surface.fmtDay(surface.selectedDate, false)
        : surface.fmtSpan(surface.rangeLo, surface.rangeHi)

    /** "allday" (default) hides the time fields; "timed" reveals start/end. */
    property string mode: "allday"
    property string startVal: ""
    property string endVal: ""
    property string titleVal: ""

    /**
     * recur is "" / "month" / "year". It suggests yearly by itself once the
     * title reads like a birthday and then stays as the user left it after they
     * work the Repeat toggle by hand (recurManual).
     */
    property string recur: ""
    property bool recurManual: false

    /** Suggest yearly for a birthday title, unless the user already chose. */
    function autoRecur() {
        if (!recurManual)
            recur = Events.isBirthday(titleVal) ? "year" : "";
    }

    function clearForm() {
        startVal = "";
        endVal = "";
        titleVal = "";
        recur = "";
        recurManual = false;
        startField.text = "";
        endField.text = "";
        titleField.text = "";
    }

    /** A time is kept only when it reads as HH:MM, otherwise it drops to an all-day blank. */
    function cleanTime(t) {
        var v = t.trim();
        return /^\d{1,2}:\d{2}$/.test(v) ? v : "";
    }

    /** Add the form's event when a title is set, then reset the inputs. */
    function commit() {
        if (titleVal.trim().length === 0)
            return;
        var t = editor.mode === "timed" ? editor.cleanTime(startVal) : "";
        var e = editor.mode === "timed" ? editor.cleanTime(endVal) : "";
        Events.add(surface.selectedDate, editor.recur !== "" ? "" : surface.selEndDate,
                   t, e, titleVal.trim(), editor.recur);
        clearForm();
        titleField.forceActiveFocus();
    }

    onWidthChanged: if (width < 1) { clearForm(); mode = "allday"; }

    Column {
        id: edCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8 * surface.s

        Text {
            width: parent.width
            text: editor.heading
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12 * surface.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.8 * surface.s
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }        /** Capped so a day stacked with events scrolls instead of growing the surface. */
        EventList {
            width: parent.width
            s: surface ? surface.s : 0
            surface: surface
            events: editor.dayEvents
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Row {
            width: parent.width
            spacing: 8 * surface.s

            Item {
                width: parent.width - addBtn.width - 8 * surface.s
                height: 28 * surface.s

                TextField {
                    id: titleField
                    anchors.fill: parent
                    background: null
                    padding: 0
                    leftPadding: 2 * surface.s
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * surface.s
                    placeholderText: "what's on"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    onTextChanged: { editor.titleVal = text; editor.autoRecur(); }
                    Keys.onReturnPressed: editor.commit()
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.faint
                    opacity: titleField.activeFocus ? 0.7 : 0.2
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }
            }

            Rectangle {
                id: addBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 28 * surface.s
                height: 28 * surface.s
                radius: Motion.rSmall * surface.s
                readonly property bool armed: editor.titleVal.trim().length > 0
                color: addArea.containsMouse && armed ? Qt.alpha(Theme.vermLit, 0.22)
                    : (armed ? Qt.alpha(Theme.vermLit, 0.12) : Theme.frameBg)
                border.width: 1
                border.color: armed ? Qt.alpha(Theme.vermLit, 0.5) : Theme.frameBorder
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: addBtn.armed ? Theme.vermLit : Theme.iconDim
                    font.family: Theme.font
                    font.pixelSize: 18 * surface.s
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.commit()
                }
            }
        }

        SettingsSeg {
            s: surface.s
            options: [
                { label: "All day", value: "allday" },
                { label: "Timed", value: "timed" }
            ]
            value: editor.mode
            onPicked: (v) => editor.mode = v
        }

        Row {
            width: parent.width
            spacing: 8 * surface.s
            visible: editor.mode === "timed"

            Item {
                width: (parent.width - 8 * surface.s) / 2
                height: 26 * surface.s

                TextField {
                    id: startField
                    anchors.fill: parent
                    background: null
                    padding: 0
                    leftPadding: 2 * surface.s
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * surface.s
                    font.features: { "tnum": 1 }
                    placeholderText: "09:00"
                    placeholderTextColor: Theme.faint
                    inputMethodHints: Qt.ImhPreferNumbers
                    selectByMouse: true
                    selectionColor: Theme.verm
                    onTextChanged: editor.startVal = text
                    Keys.onReturnPressed: editor.commit()
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.faint
                    opacity: startField.activeFocus ? 0.7 : 0.2
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }
            }

            Item {
                width: (parent.width - 8 * surface.s) / 2
                height: 26 * surface.s

                TextField {
                    id: endField
                    anchors.fill: parent
                    background: null
                    padding: 0
                    leftPadding: 2 * surface.s
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * surface.s
                    font.features: { "tnum": 1 }
                    placeholderText: "until"
                    placeholderTextColor: Theme.faint
                    inputMethodHints: Qt.ImhPreferNumbers
                    selectByMouse: true
                    selectionColor: Theme.verm
                    onTextChanged: editor.endVal = text
                    Keys.onReturnPressed: editor.commit()
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.faint
                    opacity: endField.activeFocus ? 0.7 : 0.2
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }
            }
        }

        SettingsSeg {
            s: surface.s
            options: [
                { label: "Once", value: "" },
                { label: "Monthly", value: "month" },
                { label: "Yearly", value: "year" }
            ]
            value: editor.recur
            onPicked: (v) => {
                editor.recurManual = true;
                editor.recur = v;
                if (v !== "") {
                    surface.selEndDate = "";
                    surface.pickingEnd = false;
                }
            }
        }

        /**
         * Span control: the chip shows the day or range, the button arms the
         * grid so the next day click closes a span (the under-grid hint and
         * range tint guide it), and ✕ drops a set span back to a single day.
         * Hidden for a recurring entry, which is a single repeating day.
         */
        Row {
            width: parent.width
            spacing: 8 * surface.s
            visible: editor.recur === ""

            Rectangle {
                id: spanChip
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - extendBtn.width - clearSpan.width - 16 * surface.s
                height: 28 * surface.s
                radius: Motion.rSmall * surface.s
                color: Theme.frameBg
                border.width: 1
                border.color: Theme.frameBorder

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * surface.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7 * surface.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * surface.s
                        height: 9 * surface.s
                        radius: 3 * surface.s
                        color: Theme.flameGlow
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: editor.spanLabel
                        color: surface.selEndDate.length > 0 ? Theme.cream : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 11 * surface.s
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle {
                id: extendBtn
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool armed: surface.pickingEnd
                width: extendLabel.implicitWidth + 18 * surface.s
                height: 28 * surface.s
                radius: Motion.rSmall * surface.s
                color: armed ? Qt.alpha(Theme.vermLit, 0.14) : Theme.frameBg
                border.width: 1
                border.color: armed ? Qt.alpha(Theme.vermLit, 0.5) : Theme.frameBorder
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: extendLabel
                    anchors.centerIn: parent
                    text: surface.pickingEnd ? "pick…" : (surface.selEndDate.length > 0 ? "edit" : "+ days")
                    color: extendBtn.armed ? Theme.vermLit : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * surface.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * surface.s
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (surface.pickingEnd) {
                            surface.pickingEnd = false;
                            surface.hoverDay = 0;
                        } else {
                            surface.selEndDate = "";
                            surface.pickingEnd = true;
                        }
                    }
                }
            }

            Item {
                id: clearSpan
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 16 * surface.s : 0
                height: 16 * surface.s
                visible: surface.selEndDate.length > 0 && !surface.pickingEnd

                GlyphIcon {
                    anchors.fill: parent
                    name: "close"
                    color: clearArea.containsMouse ? Theme.vermLit : Theme.iconDim
                    stroke: 1.6
                }
                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    anchors.margins: -5 * surface.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: surface.selEndDate = ""
                }
            }
        }
    }
}

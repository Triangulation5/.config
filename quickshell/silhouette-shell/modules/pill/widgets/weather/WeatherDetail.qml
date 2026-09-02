pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.animation

/**
 * Weather detail surface: the deep-dive view behind the calendar's weather
 * glance. Opens like a curtain — the pill grows to this face and the content
 * spills down from the top edge as the morph settles (see the clip + curtain
 * translate below). Carries the next 24h as a scrollable hourly strip, a
 * sunrise/sunset row, today's moon phase, and a city field that re-geocodes
 * through the same Weather chain as the glance (set a town to pin the exact
 * spot, blank it to fall back to IP).
 *
 * All data comes from the shared Weather singleton; nothing here fetches.
 * `Weather.ready` gates the whole face, so the surface can be opened before
 * the first forecast lands and fills in the moment it does.
 */
PillSurface {
    id: root

    mTop: 18
    mLeft: 18
    mRight: 18
    mBottom: 18

    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    /** Curtain reveal: how far the content has spilled down from the top, 0 → full on open. */
    readonly property real curtain: Math.pow(root.morphCloseness, 0.8)

    /**
     * Section cascade: once the curtain has finished pulling (the morph has
     * settled), the bands peel in top-down — header, hours, sun, moon — each
     * fading up and rising a touch after its predecessor. Driven by the shared
     * Cascade driver (see components/animation/Cascade.qml), which other
     * surfaces reuse.
     */
    Cascade {
        id: cascade
        morphCloseness: root.morphCloseness
        duration: 700
        count: 4
    }
    readonly property real sHeader: cascade.section(0.0)
    readonly property real sHours: cascade.section(0.22)
    readonly property real sSun: cascade.section(0.44)
    readonly property real sMoon: cascade.section(0.6)

    /** Per-chip pop: each hourly chip scales and fades in after its neighbour. */
    function chip(t, i) {
        var x = Math.max(0, Math.min(1, (t - 0.15) * 2.0 - i * 0.05));
        return x * x * (3 - 2 * x);
    }

    /** Soft pulse on the temperature whenever a fresh forecast lands. */
    property real tempPulse: 0
    Connections {
        target: Weather
        function onTempNowChanged() {
            if (root.open)
                tempPulseAnim.restart();
        }
    }
    SequentialAnimation {
        id: tempPulseAnim
        NumberAnimation { target: root; property: "tempPulse"; to: 1; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "tempPulse"; to: 0; duration: 360; easing.type: Easing.InQuad }
    }

    /**
     * Format an API hour ("14") for the hourly strip, honouring the shell's
     * clock preference: "14:00" in 24h, "2 PM" in 12h.
     */
    function fmtHour(hh) {
        if (!Flags.time12h)
            return hh + ":00";
        var h24 = parseInt(hh, 10);
        var h = h24 % 12;
        if (h === 0)
            h = 12;
        return h + " " + (h24 < 12 ? "AM" : "PM");
    }

    /**
     * Format an API "HH:MM" time (sunrise/sunset) per the clock preference:
     * "06:42" stays as-is in 24h, becomes "6:42 AM" in 12h.
     */
    function fmtTime(hhmm) {
        if (!Flags.time12h || !hhmm || hhmm.length < 5)
            return hhmm;
        var h24 = parseInt(hhmm.slice(0, 2), 10);
        var ap = h24 < 12 ? "AM" : "PM";
        var h = h24 % 12;
        if (h === 0)
            h = 12;
        return h + ":" + hhmm.slice(3, 5) + " " + ap;
    }

    /**
     * Curtain pull. The surface fills the grown pill, but its content hangs
     * above the visible window and rides down as the pill settles — read as
     * one cloth being pulled over the opening instead of a fade. The hairline
     * seam at the top of the window softens the clip edge while pulling.
     */
    Item {
        id: window
        anchors.fill: parent
        clip: true            Column {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 15 * root.s

            transform: Translate {
                y: -contentColumn.height * (1 - root.curtain)
            }

            /* Header: city (tap to edit) + current conditions. */
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 14 * root.s
                opacity: root.sHeader
                transform: Translate { y: 16 * root.s * (1 - root.sHeader) }

                Item {
                    id: cityBox
                    anchors.verticalCenter: parent.verticalCenter
                    /** Stretch to the conditions row so the city sits flush left while the conditions sit flush right. */
                    width: Math.max(140 * root.s, parent.width - condRow.implicitWidth - 14 * root.s)
                    height: 24 * root.s

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
                        font.pixelSize: 13 * root.s
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
                        font.pixelSize: 13 * root.s
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
                    id: condRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        height: 30 * root.s
                        name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
                        color: Theme.mix(Theme.todayWarm, Theme.cream, root.tempPulse)
                        stroke: 1.9
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.s
                        Text {
                            text: Weather.tempNow + "°"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 27 * root.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            scale: 1 + 0.07 * root.tempPulse
                        }
                        Text {
                            text: Weather.labelFor(Weather.codeNow) + " · " + Weather.humidity + "%"
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft
                opacity: root.sHeader
            }

            /**
             * Hourly strip: the next 24 hours as chips (hour, kanji, temp) in a
             * scrollable row. Weather.hourly comes pre-parsed from the shared
             * fetch; each entry is { hour, temp, code }.
             */
            Text {
                text: "Next 24 hours"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8 * root.s
                opacity: root.sHours
                transform: Translate { y: 14 * root.s * (1 - root.sHours) }
            }

            Flickable {
                id: hourFlick
                width: parent.width
                height: 106 * root.s
                contentWidth: hourRow.width
                clip: true
                interactive: true
                contentX: 0
                opacity: root.sHours
                transform: Translate { y: 14 * root.s * (1 - root.sHours) }

                Row {
                    id: hourRow
                    spacing: 8 * root.s
                    /** Centre the chips vertically so the strip has no dead band under them. */
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: Weather.hourly

                        Column {
                            required property var modelData
                            required property int index
                            width: 50 * root.s
                            spacing: 5 * root.s
                            opacity: root.chip(cascade.settle, index)
                            scale: 0.85 + 0.15 * root.chip(cascade.settle, index)

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.fmtHour(modelData.hour)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                                font.features: { "tnum": 1 }
                            }
                            GlyphIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 18 * root.s
                                height: 18 * root.s
                                name: Weather.glyphFor(modelData.code, true)
                                color: Theme.subtle
                                stroke: 1.7
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.temp + "°"
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }

            /**
             * Subtle side fades on the hourly strip so scrolling chips sink
             * into the surface instead of clipping hard: soft alpha, short
             * band, and only while the strip actually overflows.
             */
            EdgeFade {
                anchors.top: hourFlick.top
                anchors.bottom: hourFlick.bottom
                anchors.left: hourFlick.left
                fadeWidth: 20 * root.s
                fadeColor: Qt.alpha(Theme.cardTop, 0.55)
                active: hourRow.width > hourFlick.width
            }
            EdgeFade {
                anchors.top: hourFlick.top
                anchors.bottom: hourFlick.bottom
                anchors.right: hourFlick.right
                fadeWidth: 20 * root.s
                fadeColor: Qt.alpha(Theme.cardTop, 0.55)
                mirrored: true
                active: hourRow.width > hourFlick.width
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft
                opacity: root.sSun
            }

            /* Sunrise / sunset row. */
            Row {
                width: parent.width
                spacing: 8 * root.s
                opacity: root.sSun
                transform: Translate { y: 12 * root.s * (1 - root.sSun) }

                Row {
                    id: sunriseRow
                    spacing: 9 * root.s
                    width: (parent.width - 8 * root.s) / 2

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * root.s
                        height: 20 * root.s
                        name: "sun"
                        color: Theme.subtle
                        stroke: 1.7
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.s
                        Text {
                            text: "Sunrise"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            font.weight: Font.Medium
                        }
                        Text {
                            text: Weather.sunrise.length > 0 ? root.fmtTime(Weather.sunrise) : "—"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 16 * root.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Row {
                    spacing: 9 * root.s
                    width: (parent.width - 8 * root.s) / 2

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * root.s
                        height: 20 * root.s
                        name: "moon"
                        color: Theme.subtle
                        stroke: 1.7
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.s
                        Text {
                            text: "Sunset"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            font.weight: Font.Medium
                        }
                        Text {
                            text: Weather.sunset.length > 0 ? root.fmtTime(Weather.sunset) : "—"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 16 * root.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            /* Moon phase row. */
            Row {
                width: parent.width
                spacing: 9 * root.s
                opacity: root.sMoon
                transform: Translate { y: 12 * root.s * (1 - root.sMoon) }

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20 * root.s
                    height: 20 * root.s
                    name: "moon"
                    color: Theme.subtle
                    stroke: 1.7
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * root.s
                    Text {
                        text: "Moon"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Medium
                    }
                    Text {
                        text: Weather.moonPhase
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 16 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        /**
         * Soft hairline along the pull edge, so the growing surface seam reads
         * as a cloth fold instead of a hard clip. Rides the curtain.
         */
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.hair
            visible: root.curtain < 0.99
        }
    }

    /** The weather face isn't navigable; Escape/back closes it. */
    ameForm: "off"
}
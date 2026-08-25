pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons

/**
 * Weather glance panel for the calendar surface, extracted from Calendar.qml:
 * current conditions (kanji glyph, temp, label), an in-place editable city
 * name (sets Flags.weatherCity and re-geocodes) and a 4-day forecast strip.
 * Collapses to zero width while the Weather service isn't ready; the host
 * calendar folds its column and divider around `shown`/`fullW`.
 */
Item {
    id: panel

    property real s: 1

    /** True once live weather data has arrived. */
    readonly property bool shown: Weather.ready

    /**
     * Content reveal latch: the weather text stays invisible until the same
     * delay the calendar's event editor uses after its panel shows, so it
     * doesn't pop in while the surface is still settling.
     */
    property bool _ready: false
    Timer {
        id: readyDelay
        interval: 100
        onTriggered: panel._ready = true
    }
    onShownChanged: {
        if (shown) {
            panel._ready = false;
            readyDelay.restart();
        } else {
            readyDelay.stop();
            panel._ready = true;
        }
    }
    /** Weather may already be ready when the panel is first created. */
    Component.onCompleted: if (panel.shown) readyDelay.restart()

    /** Width the panel occupies when shown. */
    readonly property real fullW: 152 * s

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: shown ? fullW : 0
        clip: true
        visible: width > 1
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        /**
         * The panel glides open on the same liquid morph curve the pill uses
         * for its own width, so the calendar grid it carries is pushed along
         * smoothly instead of snapping when the weather arrives after the
         * surface is already open.
         */
        Behavior on width {
            NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
        }

    Column {
        id: wxCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6 * s
        spacing: 9 * s
        opacity: (panel.shown && panel._ready) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Row {
            spacing: 9 * s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 32 * s
                height: 32 * s
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
                    font.pixelSize: 26 * s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: Weather.labelFor(Weather.codeNow)
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * s
                    font.weight: Font.Medium
                }
            }
        }

        Row {
            width: parent.width
            spacing: 8 * s

            /**
             * IP geolocation only ever resolves to the ISP city, so the town
             * is editable in place: tap to type, which sets Flags.weatherCity
             * and re-geocodes through Open-Meteo for the exact spot. Blank it
             * to fall back to auto IP detection.
             */
            Item {
                id: cityBox
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - humidityRow.width - 8 * s
                height: 14 * s

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
                    font.pixelSize: 9 * s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8 * s
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
                    font.pixelSize: 9 * s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8 * s
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
                spacing: 3 * s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * s
                    height: 11 * s
                    name: "droplet"
                    color: Theme.faint
                    stroke: 1.6
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.humidity + "%"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * s
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
                    spacing: 5 * s

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCol.modelData.day
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 9 * s
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.5 * s
                    }
                    GlyphIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 15 * s
                        height: 15 * s
                        name: Weather.glyphFor(dayCol.modelData.code, true)
                        color: Theme.subtle
                        stroke: 1.7
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCol.modelData.temp + "°"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11 * s
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2 * s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9 * s
                            height: 9 * s
                            name: "droplet"
                            color: Theme.faint
                            stroke: 1.6
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dayCol.modelData.rh + "%"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 8.5 * s
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }
}
}

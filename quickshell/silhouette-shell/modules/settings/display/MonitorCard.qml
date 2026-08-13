pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.settings
import qs.modules.controlcenter

/**
 * Settings card for the selected output in the Display surface: resolution,
 * refresh and scale pickers, a Set-as-main toggle on non-main outputs, and the
 * Apply / Keep flow with its revert countdown. Pure view plus local picker
 * state — the host owns the monitor data, the monitors.lua rewrites, the
 * helper processes and the countdown. The picker row ids are exposed as
 * aliases because the host's row registry drives their keyboard focus.
 */
Rectangle {
    id: card

    required property var host

    visible: host.selMon !== null
    width: parent.width
    radius: Motion.rTile * host.s
    color: Theme.cardTop
    border.width: 1
    border.color: card.pending ? Qt.alpha(Theme.vermLit, 0.55) : Theme.hairSoft
    implicitHeight: cardCol.implicitHeight + 22 * host.s
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    property int resIndex: 0
    property int rateIndex: 0
    property real pickScale: 1
    property bool pendingMain: false
    property alias resRow: resRow
    property alias rateRow: rateRow
    property alias scaleRow: scaleRow
    property alias mainRow: mainRow

    readonly property var resolutions: host.selMon ? host.resolutionsFor(host.selMon) : []
    readonly property var rates: resolutions.length > 0 ? resolutions[Math.min(resIndex, resolutions.length - 1)].rates : []
    readonly property bool pending: host.selMon !== null && host.pendingOut === host.selMon.name

    /** Anything the helper flow would change: mode, scale or a dragged move. */
    readonly property bool dirty: {
        var mon = host.selMon;
        if (!mon || card.resolutions.length === 0)
            return false;
        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
        var hz = res.rates[Math.min(card.rateIndex, res.rates.length - 1)];
        if (res.w !== mon.width || res.h !== mon.height || hz !== mon.refresh)
            return true;
        if (card.pickScale !== mon.scale)
            return true;
        var p = host.pendingXY(mon);
        return p !== null && (p.x !== mon.x || p.y !== mon.y);
    }
    readonly property bool applyReady: dirty || (pendingMain && !host.selIsMain)

    /**
     * Seed the pickers from the selected monitor's live mode: the resolution
     * whose WxH matches the current width/height, then the Hz nearest the
     * current refresh within that resolution. Switching selection lands here
     * too, dropping any un-applied edits.
     *
     * Seeds from locally computed lists, never from `card.rates`: inside
     * onSelMonChanged the dependent bindings can still hold the previous
     * monitor's values (handler order vs binding invalidation), which seeded
     * HDMI's rate index against DP-1's rate list.
     */
    function syncToCurrent() {
        var mon = host.selMon;
        if (!mon)
            return;
        var resos = host.resolutionsFor(mon);
        var ri = 0;
        for (var i = 0; i < resos.length; i++) {
            if (resos[i].w === mon.width && resos[i].h === mon.height) {
                ri = i;
                break;
            }
        }
        card.resIndex = ri;
        card.rateIndex = card.nearestIn(resos.length > 0 ? resos[ri].rates : [], mon.refresh);
        card.pickScale = mon.scale;
        card.pendingMain = false;
        if (host.pendingMove)
            host.pendingMove = null;
        host.openPicker = "";
    }

    function nearestIn(rates, hz) {
        var best = 0;
        var bestDiff = 1e9;
        for (var i = 0; i < rates.length; i++) {
            var d = Math.abs(rates[i] - hz);
            if (d < bestDiff) { bestDiff = d; best = i; }
        }
        return best;
    }

    function nearestRateIndex(hz) {
        return nearestIn(card.rates, hz);
    }

    function bumpRes(d) {
        var i = Math.max(0, Math.min(card.resolutions.length - 1, card.resIndex + d));
        if (i === card.resIndex)
            return;
        card.resIndex = i;
        card.rateIndex = card.nearestRateIndex(card.rates.length > 0 ? card.rates[0] : 60);
    }

    function bumpRate(d) {
        var cur = Math.min(card.rateIndex, Math.max(0, card.rates.length - 1));
        card.rateIndex = Math.max(0, Math.min(card.rates.length - 1, cur + d));
    }

    Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 13 * host.s
        anchors.rightMargin: 13 * host.s
        anchors.topMargin: 11 * host.s
        spacing: 9 * host.s

        Text {
            text: host.selMon ? host.selMon.name + (host.selIsMain ? "  ·  Main" : "") : ""
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * host.s
            font.weight: Font.Bold
            font.letterSpacing: 0.3 * host.s
        }

        CardRow {
            surface: host
            id: resRow
            icon: "monitor"

            DisplayPicker {
                width: parent.width
                s: host.s
                label: "Resolution"
                options: card.resolutions.map(function (r, i) { return { label: r.w + "×" + r.h, value: i }; })
                value: card.resIndex
                open: host.openPicker === host.selName + ":res"
                onRequestToggle: host.openPicker = (host.openPicker === host.selName + ":res" ? "" : host.selName + ":res")
                onPicked: (v) => {
                    card.resIndex = v;
                    card.rateIndex = card.nearestRateIndex(card.rates.length > 0 ? card.rates[0] : 60);
                    host.openPicker = "";
                }
            }
        }

        CardRow {
            surface: host
            id: rateRow
            icon: "reboot"

            DisplayPicker {
                width: parent.width
                s: host.s
                label: "Refresh"
                options: card.rates.map(function (hz, i) { return { label: hz + "Hz", value: i }; })
                value: Math.min(card.rateIndex, Math.max(0, card.rates.length - 1))
                open: host.openPicker === host.selName + ":rate"
                onRequestToggle: host.openPicker = (host.openPicker === host.selName + ":rate" ? "" : host.selName + ":rate")
                onPicked: (v) => {
                    card.rateIndex = v;
                    host.openPicker = "";
                }
            }
        }

        CardRow {
            surface: host
            id: scaleRow
            icon: "scaling"

            Row {
                width: parent.width
                spacing: 8 * host.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64 * host.s
                    text: "Scale"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * host.s
                    font.weight: Font.Medium
                }

                SettingsSeg {
                    anchors.verticalCenter: parent.verticalCenter
                    s: host.s
                    options: host.scaleOptions
                    value: card.pickScale
                    onPicked: (v) => card.pickScale = v
                }
            }
        }

        CardRow {
            surface: host
            id: mainRow
            glyphText: "★"
            visible: host.selMon !== null && !host.selIsMain

            Item {
                width: parent.width
                height: 26 * host.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Set as main"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * host.s
                    font.weight: Font.DemiBold
                }

                LinkToggle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    s: host.s
                    on: card.pendingMain
                    onToggled: card.pendingMain = !card.pendingMain
                }
            }
        }

        Item {
            width: parent.width
            height: 30 * host.s

            Rectangle {
                id: applyBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !card.pending && host.pendingOut.length === 0
                width: applyLabel.implicitWidth + 28 * host.s
                height: 28 * host.s
                radius: 9 * host.s
                color: !card.applyReady ? Qt.alpha(Theme.onGlow, 0.10)
                    : (applyArea.containsMouse ? Qt.alpha(Theme.onGlow, 0.34) : Qt.alpha(Theme.onGlow, 0.20))
                border.width: 1
                border.color: Qt.alpha(Theme.onGlow, !card.applyReady ? 0.22 : (applyArea.containsMouse ? 0.6 : 0.4))
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: applyLabel
                    anchors.centerIn: parent
                    text: "Apply"
                    color: card.applyReady ? Theme.cream : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * host.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3 * host.s
                }

                MouseArea {
                    id: applyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: card.applyReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (card.applyReady) host.apply()
                }
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: card.pending
                spacing: 9 * host.s

                Rectangle {
                    id: keepBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: keepLabel.implicitWidth + 28 * host.s
                    height: 28 * host.s
                    radius: 9 * host.s
                    color: keepArea.containsMouse ? Theme.vermLit : Theme.verm
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: keepLabel
                        anchors.centerIn: parent
                        text: "Keep (" + host.countdown + ")"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 10.5 * host.s
                        font.weight: Font.Bold
                        font.letterSpacing: 0.3 * host.s
                    }

                    MouseArea {
                        id: keepArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: host.keep()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "reverts automatically if not kept"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * host.s
                    font.weight: Font.Medium
                }
            }
        }
    }
}

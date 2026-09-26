pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.layout

/**
 * 蓄 BATTERY surface: a typographic read-out for the laptop battery. The
 * percentage is the hero, set over a time-to-empty/full subline, with a thin
 * charge meter and an adaptive stat list (Rate / Health / Capacity) beneath a
 * hairline. Health drops when UPower can't report it and the time line drops
 * when no estimate exists; on AC-full the subline reads "Plugged in", and on a
 * pack held at a charge threshold it says so instead of claiming to be full.
 * Charging warms the percentage, subline and meter to the flame tones, as does
 * being plugged in and holding. A laptop with more than one pack gets a row per
 * pack under the hairline (Rate / Health / Capacity / BAT0 / BAT1), since the
 * percentage above is UPower's aggregate and cannot say which pack is doing
 * what. Exposes `implicitHeight` from its content and docks Ame as a seam at the
 * charge head.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 19
    mRight: 19
    mBottom: 16

    implicitHeight: content.implicitHeight

    /**
     * Where the seam docks: the head of the charge meter, mirroring the
     * seek-stroke head on the media card. Sits clear of the hero number and
     * tracks the charge level. mapToItem isn't reactive, so the void reads
     * force re-eval across the morph and on charge changes.
     */
    readonly property point chargeHead: {
        void root.width;
        void root.height;
        void Battery.frac;
        void meter.width;
        return meter.mapToItem(root, meter.width * Battery.frac, meter.height / 2);
    }

    ameForm: "seam"
    amePoint: chargeHead

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SurfaceHeader {
            kanji: "蓄"
            label: "BATTERY"
            badge: Battery.stateLabel
            badgeColor: (Battery.charging || Battery.pending) ? Theme.flameGlow : Theme.dim
            s: root.s
        }

        Column {
            width: parent.width
            topPadding: 16 * root.s
            bottomPadding: 14 * root.s
            spacing: 9 * root.s

            Text {
                id: pctText
                text: Battery.pct + "%"
                color: Battery.low ? Theme.vermLit
                    : ((Battery.charging || Battery.pending) ? Theme.flameGlow : Theme.cream)
                font.family: Theme.font
                font.pixelSize: 46 * root.s
                font.weight: Font.Bold
                font.letterSpacing: -1 * root.s
                font.features: { "tnum": 1 }
            }

            Text {
                readonly property string body: Battery.pending
                    ? "Held at its charge limit"
                    : (Battery.full
                        ? "Plugged in"
                        : (Battery.hasTime
                            ? Battery.timeStr + (Battery.charging ? " to full" : " remaining")
                            : ""))
                visible: body.length > 0
                text: body
                color: (Battery.charging || Battery.pending) ? Theme.flameCore : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            id: meter
            width: parent.width
            height: 3 * root.s
            radius: 1.5 * root.s
            color: Theme.threadBg

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Battery.frac
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: (Battery.charging || Battery.pending) ? Theme.vermLit : Theme.vermDeep }
                    GradientStop { position: 1.0; color: (Battery.charging || Battery.pending) ? Theme.flameGlow : Theme.vermLit }
                }
            }
        }

        Column {
            width: parent.width
            topPadding: 16 * root.s
            spacing: 10 * root.s

            StatRow {
                visible: Math.abs(Battery.rateW) >= 0.05
                label: "Rate"
                value: (Battery.rateW > 0 ? "+" : "−") + Math.abs(Battery.rateW).toFixed(1) + " W"
                warm: Battery.charging || Battery.pending
                s: root.s
            }

            StatRow {
                visible: Battery.healthSupported
                label: "Health"
                value: Battery.health + "%"
                warm: true
                s: root.s
            }

            StatRow {
                visible: Battery.capacityWh >= 1
                label: "Capacity"
                value: Battery.capacityWh.toFixed(1) + " Wh"
                s: root.s
            }

            /**
             * A row per pack, only when there is more than one. The hero
             * percentage is UPower's aggregate of these, so without them a
             * two-pack machine cannot show that one pack is held at a threshold
             * while the other is full — the case that reads as "Fully Charged"
             * from the aggregate alone.
             */
            Repeater {
                model: Battery.packInfo

                StatRow {
                    required property var modelData
                    visible: Battery.packInfo.length > 1
                    label: modelData.name
                    value: modelData.value
                    warm: Battery.charging || Battery.pending
                    s: root.s
                }
            }
        }
    }
}

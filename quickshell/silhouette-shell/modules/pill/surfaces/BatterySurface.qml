pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.layout

/**
 * 蓄 BATTERY surface: a typographic read-out for the laptop battery. The
 * percentage is the hero, set over a time-to-empty/full subline, with a thin
 * charge meter and an adaptive stat list (Rate / Health / Capacity) beneath a
 * hairline. Health drops when UPower can't report it and the time line drops
 * when no estimate exists; on AC-full the subline reads "Plugged in". Charging
 * warms the percentage, subline and meter to the flame tones. Exposes
 * `implicitHeight` from its content and docks Ame as a seam at the charge head.
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
            badgeColor: Battery.charging ? Theme.flameGlow : Theme.dim
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
                color: Battery.low ? Theme.vermLit : (Battery.charging ? Theme.flameGlow : Theme.cream)
                font.family: Theme.font
                font.pixelSize: 46 * root.s
                font.weight: Font.Bold
                font.letterSpacing: -1 * root.s
                font.features: { "tnum": 1 }
            }

            Text {
                readonly property string body: Battery.full
                    ? "Plugged in"
                    : (Battery.hasTime
                        ? Battery.timeStr + (Battery.charging ? " to full" : " remaining")
                        : "")
                visible: body.length > 0
                text: body
                color: Battery.charging ? Theme.flameCore : Theme.subtle
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
                    GradientStop { position: 0.0; color: Battery.charging ? Theme.vermLit : Theme.vermDeep }
                    GradientStop { position: 1.0; color: Battery.charging ? Theme.flameGlow : Theme.vermLit }
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
                warm: Battery.charging
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
        }
    }
}

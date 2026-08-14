pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * The updates status badge: a tinted circular glyph (spinning while a check or
 * apply runs) beside the headline, subline and version readout. Pure
 * presentation — the state comes in as props.
 */
Row {
    id: root

    property real s: 1.1
    property color badgeTint: Theme.dim
    property string badgeIcon: ""
    property string headline: ""
    property string subline: ""

    spacing: 12 * root.s

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 34 * root.s
        height: 34 * root.s
        radius: width / 2
        color: Qt.alpha(root.badgeTint, 0.16)

        GlyphIcon {
            anchors.centerIn: parent
            visible: !Updates.spinning
            width: 17 * root.s
            height: 17 * root.s
            name: root.badgeIcon
            color: root.badgeTint
            stroke: 2.2
        }

        GlyphIcon {
            anchors.centerIn: parent
            visible: Updates.spinning
            width: 16 * root.s
            height: 16 * root.s
            name: "reboot"
            color: root.badgeTint
            stroke: 2

            RotationAnimation on rotation {
                running: Updates.spinning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 34 * root.s - 12 * root.s
        spacing: 3 * root.s

        Text {
            text: root.headline
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 14.5 * root.s
            font.weight: Font.Bold
        }

        Text {
            width: parent.width
            visible: root.subline.length > 0
            text: root.subline
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            font.features: { "tnum": 1 }
        }

        Text {
            visible: Updates.version.length > 0
            text: Updates.behind && Updates.installedShort.length > 0 && Updates.installedShort !== Updates.targetShort
                ? Updates.installedShort + " → " + Updates.targetShort
                : Updates.version.replace(" ", " · ")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }
}

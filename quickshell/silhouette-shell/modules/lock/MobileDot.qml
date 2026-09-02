pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * "Mobile" lock-screen password bead: pops in with a scale overshoot and no
 * vertical motion, the Android/iOS lock pattern. Picked by PasswordDots when
 * the LOCKSCREEN dots animation is "mobile".
 */
Rectangle {
    id: dot

    property real s: 1.1
    /** True for the newest bead. Mobile keeps the landing flat, so unused. */
    property bool last: false

    width: 9 * dot.s
    height: width
    radius: width / 2
    color: Theme.bright

    antialiasing: true
    smooth: true

    /** Entrance seeds: scale from nothing with a quick fade, then spring to rest. */
    property real lift: 0
    property real dotScale: 0
    property real dotOpacity: 0
    property real slideX: 0

    opacity: dotOpacity
    scale: dotScale

    transform: Translate {
        x: dot.slideX
        y: dot.lift
    }

    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.55
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
        shadowColor: Qt.rgba(0, 0, 0, 0.16)
    }

    Behavior on lift {
        SpringAnimation {
            spring: 4.8
            damping: 0.34
        }
    }

    Behavior on dotScale {
        SpringAnimation {
            spring: 5.5
            damping: 0.36
        }
    }

    Behavior on dotOpacity {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    Behavior on slideX {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Component.onCompleted: {
        dotOpacity = 1;
        dotScale = 1;
        lift = 0;
    }
}
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * "Drop" lock-screen password bead: springs in from above with a bounce and,
 * when it's the newest bead, slides into line with a little tail. Picked by
 * PasswordDots when the LOCKSCREEN dots animation is "drop".
 */
Rectangle {
    id: dot

    property real s: 1.1
    /** True for the newest bead, which gets the landing slide. */
    property bool last: false

    width: 9 * dot.s
    height: width
    radius: width / 2
    color: Theme.bright

    antialiasing: true
    smooth: true

    /** Entrance seeds: start above, undersized and clear, then rest. */
    property real lift: -16 * dot.s
    property real dotScale: 0.6
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

        if (dot.last) {
            slideX = 8 * dot.s;

            Qt.callLater(function() {
                slideX = 0;
            });
        }
    }
}
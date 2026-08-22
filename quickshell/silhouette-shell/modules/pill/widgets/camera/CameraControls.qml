pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * CameraControls: the overlaid control capsules pinned to the bottom of the
 * island. Mirror flips the feed, Effects toggles the effects layer, and the
 * gear is the future settings entry point. Active capsules warm to the flame
 * tone so state reads at a glance. Pure presentation: it emits signals and
 * reflects state, never mutating it.
 */
Row {
    id: root

    spacing: 12 * root.s

    property real s: 1.1
    property bool mirrored: true
    property bool effectsOn: true

    signal mirrorRequested()
    signal effectsRequested()
    signal settingsRequested()

    component Capsule: Rectangle {
        id: capsule

        property string glyph: ""
        property bool lit: false
        property var onTap: function() {}

        width: 42 * root.s
        height: 42 * root.s
        radius: width / 2

        color: lit ? Theme.flameGlow : Qt.alpha(Theme.capsule, 0.6)
        border.width: 1
        border.color: lit ? Theme.flameGlow : Theme.capsuleBorder

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        GlyphIcon {
            anchors.centerIn: parent
            width: 20 * root.s
            height: 20 * root.s
            name: capsule.glyph
            color: lit ? "#1c1c24" : Theme.cream
            stroke: 1.8
        }

        TapHandler {
            onTapped: capsule.onTap()
        }
    }

    Capsule {
        glyph: "mirror"
        lit: root.mirrored
        onTap: () => root.mirrorRequested()
    }

    Capsule {
        glyph: "sparkles"
        lit: root.effectsOn
        onTap: () => root.effectsRequested()
    }

    Capsule {
        glyph: "cog"
        lit: false
        onTap: () => root.settingsRequested()
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Lockscreen music ribbon: a flowing band orbiting the profile icon while a
 * player is active. It runs its own cava process so the lock glow
 * (Cava.lockLevels / GlowField) stays independent and unchanged.
 *
 * The ribbon is drawn in a square viewport whose centre is the orbit centre and
 * whose outer edge is the ring radius, so the host can scale/reposition it
 * around the profile tile without the math knowing anything about profile size.
 *
 * Visible only while a player is actually playing and the lock surface is
 * active; idle rooms fade the ribbon to zero quickly, and a long absence from
 * rest drops the hidden capture the same way the pill string visualizer does.
 */

Item {
    id: ring

    property real s: 1
    property real radius: 92 * s
    property int segments: 14
    property real dotRadius: 2.6 * s
    property real amplitude: 10 * s

    property bool surfaceActive: false
    readonly property bool hasPlayer: Players.has && Players.playing
    readonly property bool shown: ring.hasPlayer && ring.surfaceActive

    readonly property bool shouldRender: ring.shown && !ring._down

    readonly property string config:
        "[general]\n"
        + "framerate=" + Flags.vizFps + "\n"
        + "bars=" + segments + "\n"
        + "[output]\n"
        + "method=raw\n"
        + "raw_target=/dev/stdout\n"
        + "data_format=ascii\n"
        + "ascii_max_range=1000\n"
        + "[smoothing]\n"
        + "integral=0\n"
        + "waves=0\n"
        + "gravity=10000000\n"
        + "[input]\n"
        + "method=pulse\n"
        + "source=auto\n"

    readonly property bool cavaAvailable: ring._cavaOk
    property var levels: Array(ring.segments).fill(0)
    property bool active: false
    property bool debugLog: false

    readonly property real angleStep: 360 / ring.segments
    readonly property real baseAngle: -90

    readonly property real ribbonAmplitude: ring.amplitude * 0.85

    function colorMix(a, b, w) {
        return Qt.rgba(
            a.r + (b.r - a.r) * w,
            a.g + (b.g - a.g) * w,
            a.b + (b.b - a.b) * w,
            1
        )
    }

    function getColor(index, level) {
        var t = Math.max(0, Math.min(1, level || 0))
        var pos = ring.segments > 1 ? index / (ring.segments - 1) : 0
        var cool = Theme.mix(Theme.vermLit, Theme.verm, 0.32)
        var warm = Theme.mix(Theme.flameGlow, Theme.vermLit, 0.18)
        var hue = Theme.mix(cool, warm, pos)
        return Theme.mix(hue, Theme.flameGlow, t * 0.55)
    }

    function ribbonPoint(index, baseR) {
        var angleDeg = ring.baseAngle + index * ring.angleStep
        var rad = Math.PI * angleDeg / 180
        var c = Math.cos(rad)
        var s = Math.sin(rad)
        var inner = Math.max(6, baseR - ring.ribbonAmplitude * (ring.levels[index] || 0))
        return { x: ring.radius + inner * c, y: ring.radius + inner * s }
    }

    readonly property real ribbonAlpha: ring.shouldRender && ring.cavaAvailable
        ? (ring.active ? 0.95 : 0.12) : 0

    readonly property var ribbonPts: (function() {
        var pts = []
        if (ring.segments < 2) return pts
        var base = ring.radius - ring.ribbonAmplitude * 0.4
        for (var i = 0; i < ring.segments; i++) {
            pts.push(ring.ribbonPoint(i, base))
        }
        return pts
    })()

    Component.onCompleted: {
        ring.levels = Array(ring.segments).fill(0)
    }

    Connections {
        target: Players
        function onPlayingChanged() { if (!Players.playing) ring._idleRunning = true }
        function onHasChanged()     { if (!Players.has)     ring._idleRunning = true }
    }

    Timer {
        id: idle
        interval: 300
        running: ring._idleRunning
        onTriggered: {
            ring.active = false
            ring.levels = Array(ring.segments).fill(0)
            ring._idleRunning = false
        }
    }

    Process {
        id: cavaProbe

        command: ["/bin/bash", "-c",
            "command -v cava >/dev/null 2>&1"
        ]

        onExited: (code) => {
            ring._cavaOk = code === 0
            if (!ring._cavaOk) {
                ring.active = false
                ring.levels = Array(ring.segments).fill(0)
            }
        }

        Component.onCompleted: running = true
    }

    Process {
        id: cava

        running: ring.shouldRender && ring.cavaAvailable && !ring._down
        command: ["/bin/bash", "-c",
            "exec cava -p /dev/stdin <<< \"$1\"", "_", ring.config
        ]

        stdout: SplitParser {
            onRead: data => {
                if (!ring.shouldRender)
                    return
                var parts = data.trim().split(";")
                var out = new Array(ring.segments).fill(0)
                var peak = 0
                for (var i = 0; i < out.length; i++) {
                    if (i < parts.length) {
                        out[i] = Math.max(0, Math.min(1, parseFloat(parts[i]) / 1000 || 0))
                    }
                    if (out[i] > peak) peak = out[i]
                }
                ring.levels = out
                if (peak > 0.02) {
                    ring.active = true
                    ring._idleRunning = true
                }
            }
        }

        onExited: if (ring.shouldRender && ring.cavaAvailable) ring.relaunch.running = true
    }

    Timer {
        id: relaunch
        interval: 1500
        running: ring.shouldRender && !cava.running && ring.cavaAvailable && !ring._down
        onTriggered: cava.running = true
    }

    Timer {
        id: expandKill
        interval: 5000
        running: ring.shouldRender && ring._resting < 1
        repeat: false
        onTriggered: ring._down = true
    }

    property bool _down: false
    property real _resting: 0
    property bool _cavaOk: false
    property bool _idleRunning: false

    Shape {
        id: ribbon

        width: ring.radius * 2
        height: width
        anchors.centerIn: parent
        opacity: ring.ribbonAlpha
        antialiasing: true
        smooth: true

        property color ribbonColor: ring.active
            ? ring.getColor(0, (ring.levels[0] || 0))
            : Qt.rgba(0.61, 0.77, 1.0, 0.10)

        preferredRendererType: Shape.CurveRenderer

        Instantiator {
            id: ribbonPaths
            model: ring.segments
            onObjectAdded: (index, path) => {
                if (!path || !ring.ribbonPts || ring.ribbonPts.length < 2) return
                path.startX = ring.ribbonPts[index].x
                path.startY = ring.ribbonPts[index].y
                path.strokeColor = ribbon.ribbonColor
                path.strokeWidth = ring.active ? 3 : 1
                path.fillColor = "transparent"
                path.antialiasing = true
                var next = ring.ribbonPts[(index + 1) % ring.segments]
                var line = Qt.createQmlObject(
                    "import QtQuick.Shapes; PathLine { " +
                    "x: " + next.x.toFixed(2) + "; y: " + next.y.toFixed(2) + " }",
                    path,
                    "ribbonSeg" + index
                )
                if (line) line.parent = path
            }
            onObjectRemoved: (index, path) => {
                if (!path) return
                while (path.children.length > 0) path.children[0].destroy()
            }
        }
    }

    Repeater {
        model: ring.segments

        property real lvl: ring.levels[index] || 0
        property var pt: ring.ribbonPts[index]
        property real dotScale: 0.6 + 0.4 * lvl

        delegate: Rectangle {
            visible: ring.shouldRender && ring.cavaAvailable && lvl > 0.02
            x: pt.x - ring.dotRadius * dotScale
            y: pt.y - ring.dotRadius * dotScale
            width: ring.dotRadius * 2 * dotScale
            height: width
            radius: width / 2
            color: ring.getColor(index, lvl)
            opacity: ring.ribbonAlpha
            antialiasing: true
        }
    }
}

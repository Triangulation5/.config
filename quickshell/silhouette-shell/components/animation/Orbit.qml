pragma ComponentBehavior: Bound

import QtQuick

/**
 * Orbit: a reusable ring of particles rotating around a centre. Drive it with
 * `radius`, `speed` (revolutions per second), `count`, `direction` (+1
 * clockwise, -1 counter-clockwise), `particleSize` and `color`. Animating
 * `radius` (the caller puts a Behavior on the value it binds here) moves the
 * particles radially, so the same component serves Face ID scanning rings,
 * music particles, loading spinners and radar sweeps.
 */
Item {
    id: root

    property real radius: 30
    property real speed: 1.5
    property int count: 8
    property int direction: 1
    property real particleSize: 5
    property color color: "#ffffff"
    property bool running: true

    width: 2 * root.radius
    height: 2 * root.radius

    /** Sweeps 0..360 forever; `direction` flips it without restarting the loop. */
    property real spin: 0
    NumberAnimation on spin {
        from: 0
        to: 360
        duration: root.speed > 0 ? Math.round(1000 / root.speed) : 0
        loops: Animation.Infinite
        running: root.running && root.count > 0 && root.speed > 0
    }

    Item {
        id: rotor
        anchors.fill: parent
        rotation: root.spin * root.direction

        Repeater {
            model: root.count

            delegate: Rectangle {
                required property int index

                readonly property real angle: index * (360 / root.count) * Math.PI / 180

                x: rotor.width / 2 + root.radius * Math.cos(angle) - width / 2
                y: rotor.height / 2 + root.radius * Math.sin(angle) - height / 2
                width: root.particleSize
                height: root.particleSize
                radius: width / 2
                color: root.color
            }
        }
    }
}

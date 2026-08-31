import QtQuick

/**
 * Content reveal latch for morphing pill content: `ready` stays false until
 * `delay` ms after `shown` becomes true, then latches true. Bind content
 * opacity to (shown && ready) so a surface's header, tiles or panels don't
 * pop in while the pill is still settling into its new size. `ready` drops
 * the moment `shown` goes false, so every reveal starts hidden again, and the
 * already-shown-at-creation case (lazy surfaces born open) is covered.
 */
Item {
    id: root

    visible: false

    property bool shown: false
    property int delay: 100
    property bool ready: false

    Timer {
        id: latch
        interval: root.delay
        onTriggered: root.ready = true
    }

    onShownChanged: {
        if (shown) {
            root.ready = false;
            latch.restart();
        } else {
            latch.stop();
            root.ready = true;
        }
    }

    Component.onCompleted: if (root.shown) latch.restart()
}

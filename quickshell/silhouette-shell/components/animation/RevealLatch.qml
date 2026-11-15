import QtQuick

/**
 * Content reveal latch for morphing pill content: `ready` stays false until
 * `delay` ms after `shown` becomes true, then latches true. Bind content
 * opacity to `revealed` so a surface's header, tiles or panels don't
 * pop in while the pill is still settling into its new size. `revealed` drops
 * immediately when `shown` goes false, and `ready` resets for the next reveal.
 * The already-shown-at-creation case (lazy surfaces born open) is covered. Each
 * instance can override `delay` and `jitter`; omitted values keep the defaults.
 * `revealed` combines the requested visibility with readiness for consumers.
 *
 * The reveal delay can include a small randomized jitter to avoid perfectly
 * mechanical timing between repeated reveals. With the default values this
 * resolves to a delay between 100ms and 200ms.
 */
Item {
    id: root

    visible: false

    property bool shown: false
    property int delay: 100
    property int jitter: 100
    property bool ready: false
    readonly property bool revealed: root.shown && root.ready

    Timer {
        id: latch

        interval: root.delay + Math.floor(Math.random() * (root.jitter + 1))

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

    Component.onCompleted: {
        if (root.shown)
            latch.restart();
        else
            root.ready = true;
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.lock

/**
 * Lock screen password dots: one bead per typed character, synced to the
 * field's text length. The entrance style is driven by the LOCKSCREEN setting
 * (Flags.lockDotsMode) and each style lives in its own component - DropDot
 * springs beads in from above with a bounce, MobileDot pops them in with a
 * scale overshoot, and PulseDot makes the freshest bead breathe like a wick
 * tip. `field` is
 * the password TextInput and `host` the lock surface (for `revealPassword`).
 */
Item {
    id: root

    property real s: 1.1
    property var host: null
    property var field: null
    /** Entrance style for new beads, driven by the shared LOCKSCREEN setting. */
    readonly property string mode: Flags.lockDotsMode

    Component {
        id: dropDot
        DropDot {}
    }
    Component {
        id: mobileDot
        MobileDot {}
    }
    Component {
        id: pulseDot
        PulseDot {}
    }

    Row {
        anchors.centerIn: parent
        spacing: 7 * root.s
        visible: field.text.length > 0 && !host.revealPassword

        ListModel {
            id: passwordDots
        }

        Connections {
            target: field

            property int previousLength: 0

            function onTextChanged() {
                var current = field.text.length;

                if (current > previousLength) {
                    for (var i = previousLength; i < current; ++i)
                        passwordDots.append({});
                } else if (current < previousLength) {
                    for (var j = previousLength; j > current; --j)
                        passwordDots.remove(passwordDots.count - 1);
                }

                previousLength = current;
            }
        }

        Repeater {
            model: passwordDots

            Loader {
                required property int index

                sourceComponent: root.mode === "drop" ? dropDot
                    : (root.mode === "mobile" ? mobileDot : pulseDot)

                onLoaded: {
                    item.s = Qt.binding(() => root.s);
                    item.last = Qt.binding(() => index === passwordDots.count - 1);
                    /** Pulse beads cycle a small palette per slot, fixed at creation. */
                    if (root.mode === "pulse")
                        item.tone = index % 4;
                }
            }
        }
    }
}
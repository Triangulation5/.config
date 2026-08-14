pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * Lock screen password dots: one spring-popped bead per typed character,
 * synced to the field's text length. The last bead slides out and back as it
 * lands, giving each keystroke a little tail. `field` is the password TextInput
 * and `host` the lock surface (for `revealPassword`).
 */
Item {
    id: root

    property real s: 1.1
    property var host: null
    property var field: null

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

            Rectangle {
                id: dot

                width: 9 * root.s
                height: width
                radius: width / 2
                color: Theme.bright

                antialiasing: true
                smooth: true

                property real lift: -4 * root.s
                property real dotScale: 0.72
                property real dotOpacity: 0
                property real slideX: 0
                /** Declared so `index` resolves inside the compiled onCompleted handler. */
                required property int index

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

                    if (index === passwordDots.count - 1) {
                        slideX = 8 * root.s;

                        Qt.callLater(function() {
                            slideX = 0;
                        });
                    }
                }
            }
        }
    }
}

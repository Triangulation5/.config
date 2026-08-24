pragma ComponentBehavior: Bound

import QtQuick

/**
 * Base for the OSD faces: an item that fades in and out with the `active` flag.
 * Every face (level, mic, record, track, workspace) shares the same opacity
 * fade, so the boilerplate lives here instead of in each face. Faces extend
 * this and add their own props and content.
 */
Item {
    id: face

    property real s: 1.1
    property bool active: false

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }
}

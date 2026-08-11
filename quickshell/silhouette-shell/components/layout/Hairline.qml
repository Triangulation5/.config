pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * One-pixel hairline divider. Used between sections on every pill surface.
 */
Rectangle {
    property real s: 1.1
    width: parent ? parent.width : 0
    height: 1
    color: Theme.hair
}

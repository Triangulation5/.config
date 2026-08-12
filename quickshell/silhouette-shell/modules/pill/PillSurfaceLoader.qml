pragma ComponentBehavior: Bound

import QtQuick

/**
 * Lazy surface loader for the pill. Extends Loader with the two properties
 * every pill surface loader shares — anchors.fill: parent and active: false —
 * so the Loader block is about half as tall. The sourceComponent still carries
 * its own s/open/morphCloseness bindings inline so they are live from the
 * moment the component is created, with no onLoaded timing gap.
 */
Loader {
    active: false
    anchors.fill: parent
}

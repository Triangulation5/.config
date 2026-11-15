import QtQuick

/**
 * Shared timer choreography for a compact glance that expands into a panel.
 * The host supplies its expanded state and timing; visuals stay in the host.
 */
Item {
    id: root

    visible: false

    property bool expanded: false
    property bool hideCompactOnExpand: true
    property int openDelay: 160
    property int closeDelay: 240
    property int compactReturnDelay: 300

    property bool panelOpen: false
    property bool compactShown: true

    onExpandedChanged: {
        if (root.expanded) {
            closeTimer.stop();
            compactTimer.stop();
            if (root.hideCompactOnExpand)
                root.compactShown = false;
            if (!root.panelOpen)
                openTimer.restart();
        } else {
            openTimer.stop();
            compactTimer.stop();
            if (root.panelOpen)
                closeTimer.restart();
            else
                root.compactShown = true;
        }
    }

    Timer {
        id: openTimer
        interval: root.openDelay
        onTriggered: if (root.expanded) root.panelOpen = true
    }

    Timer {
        id: closeTimer
        interval: root.closeDelay
        onTriggered: {
            if (root.expanded)
                return;
            root.panelOpen = false;
            compactTimer.restart();
        }
    }

    Timer {
        id: compactTimer
        interval: root.compactReturnDelay
        onTriggered: if (!root.expanded && !root.panelOpen)
            root.compactShown = true
    }
}

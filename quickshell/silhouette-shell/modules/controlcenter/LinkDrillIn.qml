pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls

/**
 * Shared skeleton for the link surface's drill-in panels (wifi, bluetooth):
 * the back-chevron header with title, status caption and the panel's own
 * right-side controls, the divider, and the entire keyboard scaffold — the
 * kbIndex walk, expanded-row confirm focus, Backspace-to-collapse, the scan
 * timer and the deactivation reset. The two panels previously carried this
 * block twice; everything domain-specific stays in the deriving panel.
 *
 * The panel supplies the parts that differ as configuration and a few small
 * hooks the scaffold calls instead of re-implementing the walk:
 *  - `title` / `caption` / `captionColor` — header text (caption hidden when empty)
 *  - `scanInterval`, `scanning`, `startScan()` / `stopScan()` — the scan timer
 *  - `rowCount()`, `confirmCount(i)`, `activateAt(i)`, `adjustExtra(dir)` —
 *    what the keyboard walk operates on (see each hook below)
 *  - `scanStarted()` / `scanStopped()`, `onActivated()` / `onDeactivated()`,
 *    `onExpandedChanged()` — panel-side side effects
 *
 * The header's right side and the row list are laid out by the panel as
 * ordinary children anchored to `headerBar` and `dividerBar`, so the panel
 * keeps full control of its own body (wifi's hotspot footer, its hidden
 * HotspotControl). The keyboard API (kbMove/kbActivate/kbAdjust/kbBack)
 * matches the old per-panel functions, so Link.qml's subview routing is
 * untouched.
 */
Item {
    id: root

    property real s: 1.1
    property bool active: false

    signal back()

    /** Header title, status caption (empty = hidden) and caption color. */
    property string title: ""
    property string caption: ""
    property color captionColor: Theme.faint

    /** Scan state + auto-stop timer; interval overridden per panel (bt: 25s). */
    property bool scanning: false
    property int scanInterval: 10000

    /** Keyboard state shared by every drill-in list. */
    property int kbIndex: -1
    property int confirmFocus: -1
    property string expandedRow: ""

    /** The header bar and divider, for the panel's own children to anchor to. */
    property alias headerBar: header
    property alias dividerBar: divider

    BackHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        title: root.title
        caption: root.caption
        captionColor: root.captionColor
        onBack: root.back()
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    /**
     * Focusable rows in the panel's list (list rows plus any extra rows, e.g.
     * wifi's hotspot block). Drives kbMove's wrap-around walk.
     */
    function rowCount() { return 0; }

    /**
     * Confirm buttons on the expanded row at `i`: 2 or 3 when that row is
     * expanded and has confirm actions, 0 otherwise. Drives kbAdjust's cycle.
     */
    function confirmCount(i) { return 0; }

    /** Activation for one focusable row; true when the panel consumed it. */
    function activateAt(i) { return false; }

    /**
     * Horizontal adjust for rows with no confirm row (wifi's hotspot toggle);
     * kbAdjust falls through to this when confirmCount returns 0.
     */
    function adjustExtra(dir) { return false; }

    /**
     * Runs the `confirmFocus`-th action of `actions` (each a function(item))
     * for `item`; true when one fired. The panel's activateAt builds the
     * action list from its row's state, so the dispatch stays shared.
     */
    function confirmFire(item, actions) {
        if (root.confirmFocus < 0)
            return false;
        var f = actions[root.confirmFocus];
        if (f) {
            f(item);
            return true;
        }
        return false;
    }

    function kbMove(dir) {
        var total = root.rowCount();
        if (total === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= total)
            kbIndex = 0;
        else
            kbIndex = (kbIndex + dir + total) % total;
        return true;
    }

    function kbActivate() {
        var total = root.rowCount();
        if (total === 0)
            return false;
        if (kbIndex < 0 || kbIndex >= total)
            kbIndex = 0;
        return root.activateAt(kbIndex);
    }

    function kbAdjust(dir) {
        if (kbIndex < 0 || kbIndex >= root.rowCount())
            return false;
        var n = root.confirmCount(kbIndex);
        if (n > 0) {
            if (confirmFocus < 0)
                confirmFocus = 0;
            else
                confirmFocus = (confirmFocus + dir + n) % n;
            return true;
        }
        return root.adjustExtra(dir);
    }

    function kbBack() {
        if (root.expandedRow.length) {
            root.expandedRow = "";
            return true;
        }
        return false;
    }

    /** Panel-side side-effect hooks (no-ops by default). */
    function onExpandedChanged() {}
    function onActivated() {}
    function onDeactivated() {}
    function scanStarted() {}
    function scanStopped() {}

    onExpandedRowChanged: {
        root.confirmFocus = -1;
        root.onExpandedChanged();
    }

    onActiveChanged: {
        if (root.active) {
            root.onActivated();
        } else {
            root.stopScan();
            root.kbIndex = -1;
            root.confirmFocus = -1;
            root.expandedRow = "";
            root.onDeactivated();
        }
    }

    function startScan() {
        root.scanning = true;
        scanTimer.restart();
        root.scanStarted();
    }

    function stopScan() {
        root.scanning = false;
        scanTimer.stop();
        root.scanStopped();
    }

    Timer {
        id: scanTimer
        interval: root.scanInterval
        onTriggered: root.stopScan()
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

/**
 * Workspace dots for one monitor. No numbers, no icons. Active one is a larger
 * filled vermillion dot; the rest are small and dim, brightening on hover.
 * Clicking a dot focuses that workspace via the Hyprland-lua dispatcher. Active
 * marker tracks the monitor's live active workspace name from the Hyprland
 * model.
 *
 * The range comes from [[Workspacerules]].byMonitor for this monitor — the union
 * of the workspace rules assigned to it and the workspaces Hyprland currently
 * has there — plus this monitor's active workspace, filled out so the strip is
 * contiguous from its first workspace to its last. Jumping to a workspace that
 * is not configured (9 on a 1-5 setup) therefore shows a dot per slot up to it
 * with the active one lit, instead of a gapped strip that grew a dot at a time.
 * That list is built from hyprctl, deliberately not from Quickshell's
 * `Hyprland.workspaces` model: on Hyprland 0.56 that model collapses every
 * workspace onto id 0 (the compositor no longer sends `id` in `hyprctl
 * workspaces -j`) and leaves `monitor` null, so ranging over it showed a
 * different, short number of dots on each workspace with the active dot never
 * landing.
 *
 * The row is a fixed pool of slots instead of one delegate per workspace, and a
 * slot collapses to zero width (with its own gap) when its workspace is off the
 * end of the range. Growing or shrinking the strip therefore animates through
 * the slots' own Behaviors rather than rebuilding the Repeater — a jump past
 * the rules used to reset the model mid-flash, which is what flickered. `range`
 * is assigned imperatively and only when it actually changes, so the hyprctl
 * refresh that follows a switch leaves an unchanged strip alone.
 *
 * The strip's size is computed from the range rather than read back from the
 * row. An OSD face is invisible until its flash begins, a positioner only lays
 * its children out on polish, and the OSD sizes its morph from this strip's
 * implicit width — so a row-derived width stayed 0 until the flash was already
 * running, and the pill then snapped to a new width mid-morph. That snap plus
 * the model re-read was the flicker. The slots use explicit widths in a plain
 * `Row` (a GridLayout would derive its column count from its own width, which
 * is circular here).
 */
Item {
    id: workspaces

    property string screenName: ""
    property real s: 1.1
    property real stickW: 17 * s
    property real dotW: 5 * s
    property real gap: 4 * s

    /** Contiguous workspace numbers for this monitor, ascending. */
    property var range: []

    /**
     * Slots in the row. It only ever grows, and only past the initial 20 when
     * the range needs more, so switching — including to a workspace well past
     * the rules — never resizes (and so never rebuilds) the row.
     */
    property int pool: 20

    readonly property int first: range.length ? range[0] : 1
    readonly property int last: range.length ? range[range.length - 1] : 0

    readonly property string activeName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }

    property int hoverIndex: -1

    /** Slot index of the active workspace, or -1 when it is off the strip. */
    readonly property int activeSlot: {
        var a = parseInt(activeName);
        return a >= first && a <= last ? a - first : -1;
    }

    /** Ascending run of every workspace number from the first to the last. */
    function spanOf(set) {
        if (!set || set.length === 0)
            return [];
        var sorted = set.slice().sort(function (x, y) { return x - y; });
        var out = [];
        for (var n = sorted[0]; n <= sorted[sorted.length - 1]; n++)
            out.push(n);
        return out;
    }

    function computeRange() {
        var set = [];
        var seen = ({});
        var listed = Workspacerules.byMonitor[screenName];
        if (listed) {
            for (var i = 0; i < listed.length; i++) {
                if (!seen[listed[i]]) {
                    seen[listed[i]] = true;
                    set.push(listed[i]);
                }
            }
        }
        var a = parseInt(activeName);
        if (a >= 1 && !seen[a])
            set.push(a);
        return spanOf(set);
    }

    /**
     * Recompute the range, and only assign it when the numbers actually change.
     * A fresh array with the same contents still resets the Repeater, which
     * restarts every slot's width Behavior — the hyprctl refresh landing just
     * after a switch would visibly re-run the strip.
     */
    function rebuild() {
        var next = computeRange();
        if (next.length === range.length) {
            var same = true;
            for (var i = 0; i < next.length; i++) {
                if (next[i] !== range[i]) {
                    same = false;
                    break;
                }
            }
            if (same)
                return;
        }
        range = next;
        if (next.length > pool)
            pool = next.length;
    }

    /**
     * Centre x of a slot's dot from target layout widths (the active stick is
     * wider). Uses the animation end values, so a focus marker aimed here lands
     * where the dot settles and doesn't chase the width Behavior.
     */
    function slotCenterX(idx) {
        let x = 0;
        for (let i = 0; i < idx; i++)
            x += gap + (i === activeSlot ? stickW : dotW);
        return x + (idx === activeSlot ? stickW : dotW) / 2;
    }

    readonly property point activeDotPoint: {
        void workspaces.activeName;
        void workspaces.width;
        return Qt.point(slotCenterX(Math.max(0, activeSlot)), height / 2);
    }

    /**
     * Width of the visible dots plus the gaps between them, trailing gap
     * trimmed, from the range rather than from the row (see above). Each slot
     * carries the gap in front of its dot so a collapsing slot takes its gap
     * with it, and the row is pulled left by one gap to cancel the first slot's
     * leading one.
     */
    readonly property real contentWidth: {
        var n = Math.max(0, last - first + 1);
        if (n === 0)
            return 0;
        return n * gap - gap + (n - 1) * dotW + (activeSlot >= 0 ? stickW : dotW);
    }

    implicitWidth: contentWidth
    implicitHeight: 22 * s

    onActiveNameChanged: rebuild()
    onScreenNameChanged: rebuild()
    Component.onCompleted: rebuild()

    Connections {
        target: Workspacerules
        function onByMonitorChanged() { workspaces.rebuild(); }
    }

    Row {
        id: row

        anchors.left: parent.left
        anchors.leftMargin: -workspaces.gap
        anchors.verticalCenter: parent.verticalCenter

        spacing: 0

        Repeater {
            model: workspaces.pool

            delegate: Item {
                id: slot

                required property int index

                readonly property int wsNumber: workspaces.first + index
                readonly property string wsName: String(wsNumber)
                /** Collapsed while its workspace is off the end of the range. */
                readonly property bool present: wsNumber <= workspaces.last
                readonly property bool isActive: workspaces.activeName === wsName
                readonly property real slotW: isActive ? workspaces.stickW : workspaces.dotW

                width: present ? slotW + workspaces.gap : 0
                height: 22 * workspaces.s
                Behavior on width {
                    NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - workspaces.gap)
                    height: workspaces.dotW
                    radius: height / 2
                    color: slot.isActive ? Theme.vermLit : Theme.cream
                    opacity: !slot.present ? 0
                        : (slot.isActive ? 1.0 : (area.containsMouse ? 0.7 : 0.3))
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.topMargin: -8 * workspaces.s
                    anchors.bottomMargin: -8 * workspaces.s
                    hoverEnabled: true
                    enabled: slot.present
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch('hl.dsp.focus({workspace="' + slot.wsName + '"})')
                    onContainsMouseChanged: {
                        if (containsMouse)
                            workspaces.hoverIndex = slot.index;
                        else if (workspaces.hoverIndex === slot.index)
                            workspaces.hoverIndex = -1;
                    }
                }
            }
        }
    }
}

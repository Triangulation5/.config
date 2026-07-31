pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

/**
 * Lockscreen Settings Surface: Morphs from the collapsed bottom-right button position
 * into a screen-connected notch style surface attached flush to the bottom-right
 * screen corner using RoundCorner.qml notch ears.
 *
 * Fully keyboard navigable (Arrow keys, Return, Space, Escape) and mouse interactive.
 */
Rectangle {
    id: root

    property real s: 1.1
    property bool open: false
    readonly property real progress: animProgress.value
    readonly property bool animating: animProgress.running

    property string backSurface: ""
    signal requestSurface(string name)
    signal closeRequested()

    property Item focusRowItem: null
    property int kbIndex: -1
    property var rows: []

    default property alias contentData: contentArea.data

    // Target dimensions
    readonly property real targetWidth: 340 * root.s
    readonly property real targetHeight: Math.min(540 * root.s, Math.max(180 * root.s, contentArea.childrenRect.height + 36 * root.s))

    // Collapsed size matching SettingsButton.qml
    readonly property real collapsedSize: 42 * root.s

    // Anchors & positioning: shifts flush to bottom-right corner when expanding
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined

    anchors.rightMargin: (1 - progress) * (parent ? parent.width * 0.045 : 24 * root.s)
    anchors.bottomMargin: (1 - progress) * (parent ? parent.height * 0.055 : 24 * root.s)

    width: collapsedSize + progress * (targetWidth - collapsedSize)
    height: collapsedSize + progress * (targetHeight - collapsedSize)

    // Main surface corner rounding
    topLeftRadius: (collapsedSize / 2) * (1 - progress) + (22 * root.s) * progress
    topRightRadius: 0
    bottomLeftRadius: (collapsedSize / 2) * (1 - progress) + (22 * root.s) * progress
    bottomRightRadius: 0

    color: Theme.capsule
    border.width: 1
    border.color: Theme.capsuleBorder
    clip: false

    visible: open || progress > 0
    focus: open

    QtObject {
        id: animProgress
        property real value: root.open ? 1.0 : 0.0

        Behavior on value {
            NumberAnimation {
                duration: 380
                easing.type: root.open ? Easing.OutCubic : Easing.BezierSpline
                easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
            }
        }
    }

    onOpenChanged: {
        if (open) {
            root.forceActiveFocus();
            if (rows.length > 0 && kbIndex < 0) {
                kbIndex = 0;
                focusRowItem = rows[0].item;
            }
        } else {
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    // --- KEYBOARD NAVIGATION ---
    Keys.onPressed: event => {
        if (!open)
            return;

        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            kbMove(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            kbMove(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            kbAdjust(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            kbAdjust(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            kbActivate();
            event.accepted = true;
        }
    }

    function reportRowHover(item, hovered) {
        if (hovered) {
            focusRowItem = item;
            kbIndex = rowIndexOf(item);
        }
    }

    function rowIndexOf(item) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].item === item)
                return i;
        return -1;
    }

    function kbMove(dir) {
        if (!rows || !rows.length)
            return;
        var next = kbIndex < 0 ? 0 : kbIndex + dir;
        kbIndex = Math.max(0, Math.min(rows.length - 1, next));
        focusRowItem = rows[kbIndex].item;
    }

    function kbAdjust(dir) {
        if (!rows || !rows.length)
            return;
        if (kbIndex < 0) {
            kbIndex = 0;
            focusRowItem = rows[0].item;
        }
        var r = rows[kbIndex];
        if (!r)
            return;
        if (r.kind === "seg") {
            var n = r.vals.length;
            var cur = r.get();
            var idx = r.vals.indexOf(cur);
            var nextIdx = (((idx < 0 ? 0 : idx) + dir) % n + n) % n;
            r.set(r.vals[nextIdx]);
        } else if (r.kind === "toggle") {
            r.set(dir > 0);
        } else if (r.kind === "scrub") {
            r.bump(dir);
        }
    }

    function kbActivate() {
        if (!rows || !rows.length || kbIndex < 0)
            return;
        var r = rows[kbIndex];
        if (!r)
            return;
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "seg") {
            var n = r.vals.length;
            var cur = r.get();
            var idx = r.vals.indexOf(cur);
            var nextIdx = (idx + 1) % n;
            r.set(r.vals[nextIdx]);
        } else if (r.kind === "action")
            r.run();
        else if (r.kind === "nav")
            root.requestSurface(r.surface);
    }

    function activateRow(item) {
        var idx = rowIndexOf(item);
        if (idx < 0)
            return;
        kbIndex = idx;
        focusRowItem = item;
        var r = rows[idx];
        if (!r)
            return;
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "seg") {
            var n = r.vals.length;
            var cur = r.get();
            var i = r.vals.indexOf(cur);
            r.set(r.vals[(i + 1) % n]);
        } else if (r.kind === "action")
            r.run();
        else if (r.kind === "nav")
            root.requestSurface(r.surface);
    }

    readonly property bool rowFocused: focusRowItem !== null && open

    // --- SCREENCORNER NOTCH EARS (Top-Right & Bottom-Left Junctions) ---
    // Top-Right Ear Border (junction with right screen edge)
    RoundCorner {
        visible: root.progress > 0.05
        anchors.left: root.right
        anchors.top: root.top
        anchors.leftMargin: -1
        size: Math.round(16 * root.s * root.progress) + 1
        corner: RoundCorner.CornerEnum.BottomRight
        color: Theme.capsuleBorder
        z: 0
    }

    // Top-Right Ear Fill
    RoundCorner {
        visible: root.progress > 0.05
        anchors.left: root.right
        anchors.top: root.top
        anchors.leftMargin: -1
        size: Math.round(16 * root.s * root.progress)
        corner: RoundCorner.CornerEnum.BottomRight
        color: Theme.capsule
        z: 1
    }

    // Bottom-Left Ear Border (junction with bottom screen edge)
    RoundCorner {
        visible: root.progress > 0.05
        anchors.right: root.left
        anchors.bottom: root.bottom
        anchors.bottomMargin: -1
        size: Math.round(16 * root.s * root.progress) + 1
        corner: RoundCorner.CornerEnum.BottomRight
        color: Theme.capsuleBorder
        z: 0
    }

    // Bottom-Left Ear Fill
    RoundCorner {
        visible: root.progress > 0.05
        anchors.right: root.left
        anchors.bottom: root.bottom
        anchors.bottomMargin: -1
        size: Math.round(16 * root.s * root.progress)
        corner: RoundCorner.CornerEnum.BottomRight
        color: Theme.capsule
        z: 1
    }

    // Content container fading and sliding smoothly during notch expansion
    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: 18 * root.s

        opacity: Math.max(0, (progress - 0.20) / 0.80)

        transform: Translate {
            y: (1 - progress) * 14 * root.s
        }
    }
}

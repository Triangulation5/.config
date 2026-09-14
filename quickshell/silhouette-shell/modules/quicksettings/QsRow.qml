pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons
import qs.components.controls
import qs.modules.settings
import qs.modules.controlcenter

/**
 * One result row of the standalone settings panel. `row` is a registry entry;
 * the editor on the right follows `type`: a pill toggle for booleans, a
 * segmented control for fixed value ladders, a compact -/+ scrubber for
 * numbers, and a text field for free-form values. Hover and click report back
 * to the panel so the highlight tracks the focused row; the panel drives
 * `bump`/`activate` over the keyboard protocol.
 *
 * The row is stateless: every control binds straight to Flags through the
 * entry's `key`, so a change persists through the shared flags file the same
 * instant the older settings surfaces commit theirs.
 */
SettingsRow {
    id: qrow

    required property var row
    readonly property real s: qrow.surface ? qrow.surface.s : 1
    readonly property var currentValue: qrow.row ? Flags[qrow.row.key] : undefined

    icon: ""
    name: qrow.row ? qrow.row.label : ""
    sub: qrow.row ? (qrow.row.caption || "") : ""
    captionOnFocus: true

    /** Whether the inline text editor is open for this row. */
    property bool editing: false

    function displayValue() {
        var v = qrow.currentValue;
        var r = qrow.row;
        if (!r)
            return "";
        if (r.type === "toggle")
            return v ? "On" : "Off";
        if (r.type === "seg") {
            var i = r.vals.indexOf(v);
            return (r.names && i >= 0) ? r.names[i] : String(v);
        }
        if (r.type === "int") {
            var shown = (r.scale !== undefined) ? v * r.scale : v;
            return Math.round(shown) + (r.unit ? " " + r.unit : "");
        }
        return String(v).length > 0 ? String(v) : (r.placeholder || "—");
    }

    /**
     * Keyboard/click adjustment: toggles flip, segs cycle in `dir`, ints step
     * by `step` clamped to the registry bounds. The single writer for the row.
     */
    function bump(dir) {
        var r = qrow.row;
        if (!r)
            return;
        if (r.type === "toggle")
            Flags[r.key] = !Flags[r.key];
        else if (r.type === "seg") {
            var n = r.vals.length;
            var i = r.vals.indexOf(qrow.currentValue);
            Flags[r.key] = r.vals[(((i < 0 ? 0 : i) + dir) % n + n) % n];
        } else if (r.type === "int") {
            var v = qrow.currentValue + dir * r.step;
            v = Math.max(r.min, Math.min(r.max, v));
            v = Math.round(v / r.step) * r.step;
            Flags[r.key] = Math.round(v * 1000) / 1000;
        }
    }

    /** Return on the row: toggle flips in place, text opens the inline field. */
    function activate() {
        if (!qrow.row)
            return;
        if (qrow.row.type === "toggle") {
            qrow.bump(1);
            return;
        }
        if (qrow.row.type === "text") {
            qrow.editing = true;
            Qt.callLater(editField.forceActiveFocus);
        }
    }

    control: Item {
        id: editorSlot

        readonly property real s: qrow.s
        width: childrenRect.width
        height: 22 * s

        LinkToggle {
            visible: qrow.row && qrow.row.type === "toggle"
            s: editorSlot.s
            on: qrow.currentValue === true
            onToggled: { if (qrow.row) Flags[qrow.row.key] = !Flags[qrow.row.key]; }
        }

        SettingsSeg {
            visible: qrow.row && qrow.row.type === "seg"
            s: editorSlot.s
            options: {
                var out = [];
                var r = qrow.row;
                if (!r || r.vals === undefined)
                    return out;
                for (var i = 0; i < r.vals.length; i++)
                    out.push({ label: (r.names && r.names[i]) ? r.names[i] : String(r.vals[i]), value: r.vals[i] });
                return out;
            }
            value: qrow.currentValue
            onPicked: (v) => { if (qrow.row) Flags[qrow.row.key] = v; }
        }

        Scrubber {
            visible: qrow.row && qrow.row.type === "int"
            s: editorSlot.s
            text: qrow.displayValue()
            onNudge: (dir) => qrow.bump(dir)
        }

        TextField {
            id: textField
            visible: qrow.row && qrow.row.type === "text" && !qrow.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(120 * editorSlot.s, implicitWidth + 8 * editorSlot.s)
            readOnly: true
            text: qrow.displayValue()
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * editorSlot.s
            font.italic: qrow.currentValue !== undefined && String(qrow.currentValue).length === 0
            background: null
            padding: 0
        }

        TextField {
            id: editField
            visible: qrow.row && qrow.row.type === "text" && qrow.editing
            anchors.verticalCenter: parent.verticalCenter
            width: 130 * editorSlot.s
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * editorSlot.s
            selectByMouse: true
            selectionColor: Theme.verm
            background: null
            padding: 0
            text: qrow.currentValue !== undefined ? String(qrow.currentValue) : ""

            onActiveFocusChanged: if (!activeFocus) qrow.commitEdit()
            onAccepted: qrow.commitEdit()
            Keys.onEscapePressed: {
                qrow.editing = false;
                if (qrow.surface)
                    qrow.surface.focusRowItem = null;
            }
        }
    }

    /** Commit the inline text editor back into Flags. */
    function commitEdit() {
        if (!qrow.editing || !qrow.row)
            return;
        qrow.editing = false;
        if (qrow.row.type === "text")
            Flags[qrow.row.key] = editField.text.trim();
    }
}

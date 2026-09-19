pragma Singleton

import QtQuick

/**
 * The hover hint behind every option's caption, as data only.
 *
 * A row used to print its caption as a second line under the label, which put
 * two lines of prose under every option on every page. The biggest page in this
 * window has forty-five rows, so most of its height was explanation — and most
 * of that explanation was the row's own label said again in a sentence ("Cursor
 * size" over "Cursor size in pixels").
 *
 * The caption is not gone: some of what it carries exists nowhere else (what a
 * 3600K white point is for, what "0 tucks them flush underneath" means), and it
 * is the text the rail's search matches a row by. It is now shown when the row
 * is hovered, by one bubble shared by the whole window instead of one per row.
 *
 * This singleton is the bus between the two halves: a row reports its hover, its
 * caption and the pointer's position here (see SettingRow), and the content
 * area's hint layer shows it through the shell's own `Tooltip` (see HintLayer).
 * Keeping that state off the rows is what makes one bubble enough — and what
 * keeps a page of forty-five rows from paying for forty-five tooltips.
 */
QtObject {
    id: hint

    /**
     * The caption to show. It outlives the hover that set it by a fade — see
     * `leave` — so this is "the last row's caption" at rest, not "".
     */
    property string text: ""

    /** The hovered row, as the identity token `leave` checks an older signal against. */
    property var anchor: null

    /**
     * The pointer itself, in scene coordinates, so the bubble can centre on the
     * cursor instead of on the row's middle. Like `text` it is left standing
     * when the pointer leaves, which is what lets the bubble fade out where the
     * cursor was rather than jumping to a corner.
     */
    property point pointer: Qt.point(0, 0)

    /** True while a row with a caption is hovered. */
    property bool hovering: false

    /**
     * Latched on the first hover of a row that has a caption to show. The bubble
     * is built then — never at startup, and never for a row that has nothing to
     * say — and kept afterwards, so the window's rows share the one item and its
     * QML file is only compiled when it is first needed.
     */
    property bool used: false

    /** A row's pointer arrived, at `spot` in scene coordinates. Rows without a caption are ignored. */
    function enter(row, caption, spot) {
        if (!caption || caption.length === 0)
            return;
        hint.anchor = row;
        hint.text = caption;
        hint.pointer = spot;
        hint.hovering = true;
        hint.used = true;
    }

    /** The pointer moved within the hovered row: the bubble rides the cursor. */
    function move(row, spot) {
        if (hint.anchor !== row)
            return;
        hint.pointer = spot;
    }

    /**
     * A row's pointer left. The row is checked so the older of two overlapping
     * signals cannot clear the row that just took over: hover arrives in both
     * orders, and a leave that fired after an enter would blank the bubble while
     * the pointer is still on a row.
     *
     * The text is deliberately left standing: the bubble fades out over a beat,
     * and one whose words were cleared first would shrink as it went. The next
     * hover overwrites it.
     */
    function leave(row) {
        if (hint.anchor !== row)
            return;
        hint.hovering = false;
        hint.anchor = null;
    }
}

pragma Singleton

import QtQuick

/**
 * The settings index, and the only thing in the app that knows what exists.
 * One `pages/` singleton per page (see the neighbours) and this file's `pages`
 * array in rail order; everything else — the rail, its search, the content
 * column, Reset — reads this index rather than keeping a list of its own.
 *
 * A page is `{ name, icon, groups }` (plus an optional `keywords` and an
 * optional `view`, for the pages whose controls are not rows — see below), a
 * group is `{ card, rows }` and a row is the flat descriptor its editor reads:
 * the field it edits, its label and caption, and the fields of that editor's
 * type. Where a row's value lives (a shell flag, a Hyprland config field) is the
 * row's `source`; see Sources.
 *
 * A page carries no summary line of its own. It used to: a `caption` the content
 * header printed beside the page's name, which the rows underneath then said
 * again one by one. The header now prints the name alone. `keywords` is the
 * searched extra, for the pages (mostly the ones with a `view`) that have no row
 * labels for the rail to match on.
 *
 * Adding a page is a new singleton in this directory, one line in qmldir and
 * one entry in `pages`; nothing else in the app changes.
 */
QtObject {
    id: index

    /**
     * Every page, in rail order. The array position *is* the page index the host
     * navigates by, so this order is the rail's order and nothing else. Pages are
     * addressed by index everywhere: an element read out of a `var` array is
     * handed back through a JS copy, so comparing two pages by identity
     * (`indexOf`) silently fails.
     *
     * The order runs from what the shell looks like to what the machine does:
     * how it is drawn (Appearance, Look, Pill shape, Corners, Motion, Timers),
     * then the bar itself (Bar & Island, Clock & Date, Notifications, Control
     * Center, Launcher), then the input and outputs it is attached to (Input,
     * Displays, Workspaces), then the session and its upkeep (Lock Screen,
     * System, Updates, Backups). Pages used to be appended as they were written,
     * which left the newer ones — Pill shape, Backups, Corners, Timers — in a
     * pile at the end, unrelated to anything next to them.
     */
    readonly property var pages: [
        Appearance,
        Look,
        PillShape,
        Corners,
        Motion,
        Timers,
        BarIsland,
        ClockDate,
        Notifications,
        ControlCenter,
        Launcher,
        Input,
        Displays,
        Workspaces,
        LockScreen,
        System,
        Updates,
        Backups
    ]

    /**
     * Every row of `page`, flattened across its groups — what Reset walks and
     * what an audit of the model counts. A page with a custom `view` has no rows.
     */
    function pageRows(page) {
        var out = [];
        if (!page || !page.groups)
            return out;
        for (var g = 0; g < page.groups.length; g++) {
            var rows = page.groups[g].rows;
            for (var r = 0; r < rows.length; r++)
                out.push(rows[r]);
        }
        return out;
    }

    /**
     * The rail's model: `{ index, page, hits, nameMatch }` per page that
     * matches, where `hits` are the rows of that page that match the whole
     * query — that is what lets the rail list individual settings under their
     * page rather than only the page. An empty query is "no filter": every page
     * comes back, with no hits to show.
     */
    function navEntries(query) {
        var tokens = query.trim().toLowerCase().split(/\s+/);
        var filtered = !(tokens.length === 1 && tokens[0] === "");
        var out = [];
        for (var p = 0; p < pages.length; p++) {
            var nameMatch = !filtered || matchesAll(headline(pages[p]), tokens);
            var hits = filtered ? matchingRows(pages[p], tokens) : [];
            if (!filtered || nameMatch || hits.length > 0)
                out.push({ index: p, page: pages[p], hits: hits, nameMatch: nameMatch });
        }
        return out;
    }

    /**
     * What a page's name is searched by: its name plus its `keywords`, for the
     * pages whose controls are not rows and so cannot be found by their labels
     * (Displays builds one card per monitor at runtime).
     */
    function headline(page) {
        return (page.name + " " + (page.keywords || "")).toLowerCase();
    }

    /** True when `hay` contains every token as a word start. */
    function matchesAll(hay, tokens) {
        for (var t = 0; t < tokens.length; t++)
            if (!matchesToken(hay, tokens[t]))
                return false;
        return true;
    }

    /** The page's rows matching every token of the query, in page order. */
    function matchingRows(page, tokens) {
        var rows = pageRows(page);
        var out = [];
        for (var r = 0; r < rows.length; r++)
            if (matchesAll(searchHaystack(rows[r]), tokens))
                out.push(rows[r]);
        return out;
    }

    /**
     * The value a row edits — its flag key, or the config field of a row that
     * does not live in flags.json. It is how a row is named across the app: the
     * rail's hits carry it and the content area reveals the row that answers to
     * it, so nothing has to compare two row objects (which would fail: a row
     * read back out of the model is a copy).
     */
    function rowKey(row) {
        if (!row)
            return "";
        return row.key !== undefined ? row.key : (row.field || "");
    }

    /** True when `row` is the row `key` names. */
    function isRow(row, key) {
        return key.length > 0 && rowKey(row) === key;
    }

    /**
     * True when `token` begins a word in the lowercase `hay` — matching on word
     * starts rather than anywhere, so "city" finds the weather row without also
     * dragging in "Pill opa-city".
     */
    function matchesToken(hay, token) {
        var escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        return new RegExp("(^|[^a-z0-9])" + escaped).test(hay);
    }

    /**
     * The lowercase text a row is searched by: its two visible lines plus its
     * field, written twice — once camelCase and once split on the capitals, so
     * `gapsIn` is reachable by typing "gaps in" or "gapsIn".
     */
    function searchHaystack(row) {
        var name = row.key !== undefined ? row.key : (row.field || "");
        return (row.label + " " + (row.caption || "") + " " + name + " "
                + name.replace(/([a-z0-9])([A-Z])/g, "$1 $2")).toLowerCase();
    }
}

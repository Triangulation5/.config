pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.launcher
import qs.components.animation
import qs.components.icons
import qs.modules.pill.surfaces

/**
 * Wallpaper surface: a filmstrip over the wallpaper directory, rendered as one
 * of the pill's surfaces. Thumbs come from the Walls singleton snapshot, newest
 * first. The focused thumb is large and fully lit; neighbours shrink, dim and
 * desaturate as they slide under it, so the strip reads as depth. Arrow keys
 * and wheel move focus, clicking a neighbour glides to it, Enter or a tap on
 * the focused thumb applies it via wallpaper.sh (strip stays open so you can
 * keep trying picks). Hold Enter (or press-and-hold the focused thumb) for the
 * heat duration to trash the file; progress sweeps along the thumb's lower edge
 * and drains on early release.
 *
 * Typing any printable character while the strip is open drops it into a remote
 * search: a search field reveals at the top, the strip swaps its model from
 * local files to results (debounced fetch through wallpaper-search.sh) and
 * selecting a result downloads it, applies it and returns to the local strip.
 * Escape, an emptied query or a finished pick all fall back to the local view.
 *
 * The web search is the primary source, as it always was: Bing images, the
 * personal GitHub wallpaper repo (`gh:` prefix, handled inside the script, and
 * every word of a query has to match) and moewalls for motion. Wallhaven is the
 * second source, reached two ways — a
 * `wh:` prefix asks it directly with the tag that follows, and an empty web
 * result hands the same query over once, because image endpoints refuse heavy
 * use and an empty strip is a poor answer when a wallpaper API is sitting
 * right there. Exactly one hop is allowed in either direction, so the two can
 * never bounce a query back and forth.
 *
 * Wallhaven thumbs are never handed to QML's `Image`: hotlinking the CDN per
 * tile fired an unbounded request burst and is what trips its Cloudflare rule.
 * They are pulled into a local cache through the script's shared pace gate, one
 * at a time, and only for the tiles around the focus — a whole page of them at
 * once spends the gate's minute-long budget and starves the next search. Web
 * thumbs are hotlinked as they always were.
 */
PillSurface {
    id: root

    property int focusIndex: 0

    /**
     * Search mode. While off the strip browses local files and bare keys are
     * watched for the first printable character; while on the search field is
     * shown, holds focus and the strip renders remote results for `query`.
     */
    property bool searching: false
    property string query: ""
    property var remoteResults: []

    /**
     * Active model and its select handler. The strip, navigation and empty
     * states all read these so the local and search views share one code path:
     * a populated query in search mode shows remote results, anything else the
     * local snapshot.
     */
    readonly property var items: (searching && query.length > 0) ? remoteResults : Walls.entries
    readonly property int itemCount: items.length

    /**
     * Gesture hint visibility. Hidden while the focus is moving so paging
     * through wallpapers stays clean; the dwell timer reveals it only once the
     * pick has been held still, so it reads as a quiet caption, not a nag.
     */
    property bool hintShown: false

    onFocusIndexChanged: {
        hintShown = false;
        hintDwell.restart();
        /** Walking the strip warms the tiles it walks into. */
        if (searching)
            enqueueThumbs();
    }

    onItemsChanged: if (focusIndex >= itemCount) focusIndex = Math.max(0, itemCount - 1);

    Timer {
        id: hintDwell
        interval: 600
        onTriggered: root.hintShown = true
    }

    /**
     * Continuous view position chasing focusIndex. The strip renders from this
     * single value, so any input rate (40Hz key autorepeat, wheel bursts) stays
     * coherent: lag is bounded by the chase time constant, not piled up across
     * per-tile retargeting animations.
     */
    property real pos: 0

    clip: true

    readonly property var slotW:      [196, 126, 104, 88, 74]
    readonly property var slotH:      [110, 71, 59, 50, 42]
    readonly property var slotCX:     [0, 143, 244, 326, 393]
    readonly property var slotBright: [1, 0.56, 0.42, 0.30, 0.22]
    readonly property var slotSat:    [1, 0.65, 0.55, 0.45, 0.40]

    function slotLerp(arr, ao) {
        if (ao >= 4)
            return arr[4];
        var i = Math.floor(ao);
        var f = ao - i;
        return arr[i] + (arr[i + 1] - arr[i]) * f;
    }

    function offsetX(off) {
        var ao = Math.abs(off);
        var cx = ao <= 4 ? slotLerp(slotCX, ao) : slotCX[4] + (ao - 4) * 60;
        return (off < 0 ? -cx : cx) * s;
    }

    function move(delta) {
        if (itemCount === 0)
            return;
        focusIndex = Math.max(0, Math.min(itemCount - 1, focusIndex + delta));
    }

    FrameAnimation {
        running: root.active && root.pos !== root.focusIndex
        onTriggered: {
            var k = 1 - Math.exp(-frameTime / 0.07);
            var next = root.pos + (root.focusIndex - root.pos) * k;
            root.pos = Math.abs(next - root.focusIndex) < 0.001 ? root.focusIndex : next;
        }
    }

    function activate() {
        if (focusIndex < 0 || focusIndex >= itemCount)
            return;
        var entry = items[focusIndex];
        if (entry.image !== undefined) {
            if (dlProc.running)
                return;
            dlProc.target = entry.image;
            dlProc.command = ["bash", root.searchScript, "download", entry.image];
            dlProc.running = true;
        } else {
            Walls.apply(entry.path);
        }
    }

    /** Trigger the focused tile's HeatHold from a held Enter key. */
    function holdPress() {
        if (focusIndex < 0 || focusIndex >= itemCount) return;
        var tile = tileRepeater.itemAt(focusIndex);
        if (tile && tile.trashHeat) tile.trashHeat.press();
    }

    function centerOnCurrent() {
        var idx = 0;
        for (var i = 0; i < Walls.entries.length; i++)
            if (Walls.entries[i].path === Walls.current) {
                idx = i;
                break;
            }
        focusIndex = idx;
        pos = idx;
    }

    /**
     * Leave search mode and fall back to the local strip, re-centring on the
     * wallpaper currently on screen. Used by Escape, an emptied query and a
     * completed download.
     */
    /** True while either source is in flight, for the strip's one search spinner. */
    readonly property bool searchBusy: webProc.running || whProc.running

    function exitSearch() {
        searching = false;
        query = "";
        remoteResults = [];
        thumbQueue = [];
        searchHops = 0;
        searchField.text = "";
        centerOnCurrent();
    }

    /**
     * Begin a search seeded with the first typed character and move keyboard
     * focus to the field so the rest of the query lands there. shell.qml routes
     * the opening keystroke here and hands focus back when the search ends.
     */
    function startSearch(ch) {
        searching = true;
        focusIndex = 0;
        pos = 0;
        searchField.text = ch;
        Qt.callLater(searchField.input.forceActiveFocus);
    }

    /**
     * Open (or refocus) the search field for a forward-slash keypress. Unlike
     * startSearch no character is seeded, so the field starts clean and ready
     * to type.
     */
    function focusSearch() {
        if (!root.searching) {
            searching = true;
            focusIndex = 0;
            pos = 0;
            searchField.text = "";
            Qt.callLater(searchField.input.forceActiveFocus);
        } else {
            searchField.input.forceActiveFocus();
        }
    }

    onActiveChanged: if (active) {
        searching = false;
        query = "";
        remoteResults = [];
        thumbQueue = [];
        searchHops = 0;
        searchField.text = "";
        Walls.refresh();
        centerOnCurrent();
        hintShown = false;
        hintDwell.restart();
    }

    Connections {
        target: Walls
        function onEntriesChanged() {
            if (!root.searching && root.focusIndex >= Walls.count)
                root.focusIndex = Math.max(0, Walls.count - 1);
        }
    }

    readonly property string searchScript: Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper-search.sh"

    /**
     * The folder name for the empty state, home-relative so the caption stays
     * short. Read off the singleton rather than hardcoded, since the folder is
     * whatever the settings app's Folder field resolved to (~/Pictures when it
     * is blank).
     */
    readonly property string dirLabel: Walls.wpDir.replace(Quickshell.env("HOME"), "~")

    /**
     * Wallhaven sort bucket handed to the script's whsearch, used for `wh:`
     * queries: hot is the default feed (a typed tag still implies most-favorited,
     * see whsearch in wallpaper-search.sh) and the script also serves latest, top,
     * random and favorites for the day a chip row wants them.
     */
    property string whSort: "hot"

    /**
     * Hops between the two sources for the current query, capped at one.
     * Whichever source the query started on may fall back to the other exactly
     * once, so the pair can never bounce a query back and forth; it resets on
     * every new keystroke.
     */
    property int searchHops: 0

    Timer {
        id: debounce
        interval: 350
        onTriggered: {
            var q = root.query.trim();
            root.searchHops = 0;
            if (q.length === 0) {
                root.remoteResults = [];
                return;
            }
            /**
             * `wh:` asks wallhaven directly, with the tag after the prefix as the
             * query. Everything else — including the script's own `gh:` prefix for
             * the personal GitHub wallpaper repo — goes to the web search first,
             * which is what it was before wallhaven was ever wired in.
             */
            if (q.indexOf("wh:") === 0)
                root.wallhavenSearch(q.slice(3).trim());
            else
                root.webSearch(q);
        }
    }

    /** The web source: Bing images, the personal GitHub repo, moewalls. */
    Process {
        id: webProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                try {
                    var parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed))
                        out = parsed;
                } catch (e) {
                    out = [];
                }
                root.remoteResults = out;
                root.focusIndex = 0;
                root.pos = 0;
                /**
                 * Nothing from the web means either no results or a refused
                 * request (the image endpoint blocks heavy use), and a wallpaper
                 * picker that shows an empty strip while a wallpaper API is
                 * sitting right there is the worse outcome — so the same query
                 * goes to wallhaven once. `gh:` is exempt: it names one repo on
                 * purpose, and answering it with wallhaven thumbnails would be
                 * nonsense.
                 */
                if (out.length === 0 && root.searchHops === 0 && root.query.indexOf("gh:") !== 0) {
                    root.searchHops = 1;
                    root.wallhavenSearch(root.query.trim());
                    return;
                }
                /** New results drop the previous query's pending thumb work. */
                root.thumbQueue = [];
                root.enqueueThumbs();
            }
        }
    }

    /**
     * The wallhaven source, reached by a `wh:` query or as the web's fallback.
     * Its blocked marker means the script's pace gate refused to wait — the
     * budget was spent by some page's thumbnails — and the same query is handed
     * back to the web search once, which is the reverse of the hop above and
     * equally one-way.
     */
    Process {
        id: whProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = null;
                try {
                    parsed = JSON.parse(this.text);
                } catch (e) {
                    parsed = null;
                }
                var blocked = parsed && !Array.isArray(parsed) && parsed.wallhaven === "blocked";
                var out = Array.isArray(parsed) ? parsed : [];
                if ((blocked || out.length === 0) && root.searchHops === 0 && root.query.length > 0) {
                    var q = root.query.trim();
                    root.searchHops = 1;
                    root.webSearch(q.indexOf("wh:") === 0 ? q.slice(3).trim() : q);
                    return;
                }
                root.remoteResults = out;
                root.focusIndex = 0;
                root.pos = 0;
                root.thumbQueue = [];
                root.enqueueThumbs();
            }
        }
    }

    function webSearch(q) {
        webProc.command = ["bash", root.searchScript, "search", q];
        webProc.running = true;
    }

    function wallhavenSearch(q) {
        whProc.command = ["bash", root.searchScript, "whsearch", q, "1", root.whSort];
        whProc.running = true;
    }

    /**
     * Paced thumb pump for wallhaven results. Remote thumbs are never handed to
     * QML's Image directly any more: that fired an unbounded burst of CDN
     * requests per scroll, which is what tripped wallhaven's Cloudflare rate
     * rule in the first place. Each one is pulled into a local cache one at a
     * time by the script's `thumbget` (paced by the same shared gate), and tiles
     * render from the cache path; a tile whose turn has not come shows its
     * placeholder instead of hitting the CDN. The cache also keeps a page
     * browsable while wallhaven is blocking us.
     */
    property var thumbLocal: ({})
    property var thumbQueue: []
    property bool thumbBusy: false

    /** True for wallhaven CDN thumbs: the only ones that must go through the pace gate. */
    function pacedThumb(url) {
        return typeof url === "string" && url.indexOf("wallhaven.cc/") >= 0;
    }

    /**
     * Tiles either side of the focus to warm. A whole page queued at once is 24
     * gated requests against a 30-per-minute wallhaven budget, which spends the
     * minute on one page and leaves the next query with none; warming only what is
     * about to be looked at keeps a page scrollable and the budget alive.
     */
    readonly property int thumbWindow: 5

    /** Queue the focused tile's neighbourhood, keeping anything already queued. */
    function enqueueThumbs() {
        if (root.remoteResults.length === 0)
            return;
        var lo = Math.max(0, root.focusIndex - root.thumbWindow);
        var hi = Math.min(root.remoteResults.length - 1, root.focusIndex + root.thumbWindow);
        for (var i = lo; i <= hi; i++) {
            var t = root.remoteResults[i] ? root.remoteResults[i].thumb : undefined;
            if (!root.pacedThumb(t) || root.thumbLocal[t] !== undefined)
                continue;
            if (root.thumbQueue.indexOf(t) < 0)
                root.thumbQueue.push(t);
        }
        root.pumpThumb();
    }

    function pumpThumb() {
        if (root.thumbBusy)
            return;
        while (root.thumbQueue.length > 0) {
            var u = root.thumbQueue.shift();
            if (root.thumbLocal[u] !== undefined)
                continue;
            thumbProc.thumbUrl = u;
            thumbProc.command = ["bash", root.searchScript, "thumbget", u];
            root.thumbBusy = true;
            thumbProc.running = true;
            return;
        }
    }

    Process {
        id: thumbProc
        property string thumbUrl: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim();
                if (p.length) {
                    /**
                     * Reassigned, not mutated: the tiles bind to the map
                     * property itself, so handing over a fresh object is what
                     * rebinds them to the newly cached path.
                     */
                    var next = {};
                    for (var k in root.thumbLocal)
                        next[k] = root.thumbLocal[k];
                    next[thumbProc.thumbUrl] = p;
                    root.thumbLocal = next;
                } else {
                    /**
                     * Fetch failed (network blip, still blocked, thumb gone):
                     * abandon the rest of this chunk instead of pacing through
                     * futile requests. The next search re-queues the page.
                     */
                    root.thumbQueue = [];
                }
                root.thumbBusy = false;
                thumbProc.thumbUrl = "";
                root.pumpThumb();
            }
        }
    }

    Timer {
        id: thumbPump
        interval: 200
        repeat: true
        running: root.searching && root.thumbQueue.length > 0
        onTriggered: root.pumpThumb()
    }

    Process {
        id: dlProc
        property string target: ""
        property string failed: ""
        property string savedPath: ""
        stdout: StdioCollector {
            onStreamFinished: dlProc.savedPath = this.text.trim()
        }
        onExited: function(exitCode) {
            if (exitCode === 0 && savedPath.length) {
                failed = "";
                Walls.refresh();
                Walls.apply(savedPath);
                root.exitSearch();
            } else {
                failed = target;
            }
            savedPath = "";
        }
    }

    SearchField {
        id: searchField
        anchors.top: parent.top
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.s
        anchors.right: parent.right
        anchors.rightMargin: 20 * root.s
        s: root.s
        kanji: "探"
        placeholder: "Search wallpapers"
        visible: root.searching
        enabled: root.searching
        horizontalNav: true
        z: 30
        onTextChanged: {
            root.query = text;
            debounce.restart();
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.exitSearch()
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_Backspace && root.query.length <= 1 && searchField.input.selectedText.length === 0) {
                root.exitSearch();
                e.accepted = true;
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.s
        anchors.verticalCenter: parent.verticalCenter
        z: 0
        visible: Flags.showGlyphs && !root.searching
        text: "壁"
        color: Theme.ghost
        opacity: 0.55
        font.family: Theme.fontJp
        font.weight: Font.Medium
        font.pixelSize: 30 * root.s
    }

    Repeater {
        id: tileRepeater
        model: root.items

        delegate: Item {
            id: tile

            required property int index
            required property var modelData

            readonly property string thumb: modelData.thumb !== undefined ? modelData.thumb : ""
            readonly property bool remote: modelData.image !== undefined
            /**
             * Wallhaven thumbs render only from the paced local cache, so an
             * uncached tile shows its placeholder rather than reaching for the
             * CDN; web-search thumbs are hotlinked (they are not the API being
             * held to a request budget).
             */
            readonly property string thumbSource: {
                if (!remote)
                    return "file://" + thumb;
                if (!root.pacedThumb(thumb))
                    return thumb;
                return root.thumbLocal[thumb] !== undefined ? "file://" + root.thumbLocal[thumb] : "";
            }

            readonly property real off: index - root.pos
            readonly property real ao: Math.abs(off)
            readonly property bool focused: index === root.focusIndex
            readonly property real bright: root.slotLerp(root.slotBright, ao)
            readonly property real sat: root.slotLerp(root.slotSat, ao)
            readonly property real corner: (8 + 2 * Math.max(0, 1 - ao)) * root.s

            property alias trashHeat: trashHeat
            readonly property real hold: trashHeat.hold
            readonly property bool committing: hold >= trashHeat.tapThreshold
            readonly property real commitProgress: Math.max(0, (hold - trashHeat.tapThreshold) / (1 - trashHeat.tapThreshold))

            /**
             * Fade a tile out as its outer edge nears the clipped strip
             * boundary, so the strip ends soften instead of getting hard-cut by
             * the pill's clip.
             */
            readonly property real edgeFade: {
                var soft = 70 * root.s;
                var gap = Math.min(x, root.width - (x + width));
                return Math.max(0, Math.min(1, gap / soft));
            }

            width: root.slotLerp(root.slotW, ao) * root.s
            height: root.slotLerp(root.slotH, ao) * root.s
            x: root.width / 2 + root.offsetX(off) - width / 2
            y: (root.height - height) / 2
            z: 10 - ao
            visible: ao <= 5
            opacity: edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao))

            onFocusedChanged: if (!focused) trashHeat.cancel()

            ClippingRectangle {
                id: card
                anchors.fill: parent
                radius: tile.corner
                color: Theme.tileBg

                layer.enabled: true
                layer.effect: MultiEffect {
                    saturation: tile.sat - 1
                    shadowEnabled: tile.focused
                    shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 4 * root.s
                }

                Image {
                    id: thumbImage
                    anchors.fill: parent
                    source: tile.ao <= 6 ? tile.thumbSource : ""
                    sourceSize.width: 512
                    sourceSize.height: 220
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.tileBg
                    visible: thumbImage.status === Image.Error
                }

                /** Fallback rung: a dim glyph over the tile when the thumb is missing. */
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 22 * root.s
                    height: 22 * root.s
                    name: "monitor"
                    color: Theme.faint
                    visible: thumbImage.status === Image.Error
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 1)
                    opacity: 1 - tile.bright
                }

                Rectangle {
                    id: consume
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: card.height * tile.commitProgress
                    visible: tile.committing
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(Theme.vermBurn, 0.66) }
                        GradientStop { position: 0.74; color: Qt.alpha(Theme.vermLit, 0.30) }
                        GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 2 * root.s
                        opacity: Math.min(1, tile.commitProgress * 3)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                            GradientStop { position: 0.5; color: Theme.flameGlow }
                            GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: tile.focused && tile.remote && dlProc.running && dlProc.target === tile.modelData.image
                    text: "saving…"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 6 * root.s
                    visible: tile.focused && tile.remote && tile.modelData.w > 0 && !(dlProc.running && dlProc.target === tile.modelData.image)
                    width: resText.implicitWidth + 12 * root.s
                    height: resText.implicitHeight + 5 * root.s
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text {
                        id: resText
                        anchors.centerIn: parent
                        text: tile.modelData.w + "×" + tile.modelData.h
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: tile.corner
                color: "transparent"
                border.width: 1
                border.color: {
                    if (tile.remote && dlProc.failed.length && dlProc.failed === tile.modelData.image)
                        return Theme.vermLit;
                    return tile.committing ? Theme.vermLit : Theme.border;
                }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            }

            HeatHold {
                id: trashHeat
                tapThreshold: 0.25
                enabled: !tile.remote
                onConfirmed: if (!tile.remote) Walls.trash(tile.modelData.path)
                onTapped: root.activate()
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    if (!tile.focused)
                        return;
                    if (tile.remote)
                        root.activate();
                    else
                        trashHeat.press();
                }
                onReleased: if (tile.focused && !tile.remote) trashHeat.release()
                onExited: trashHeat.cancel()
                onClicked: if (!tile.focused) root.focusIndex = tile.index
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.itemCount === 0 && !root.searchBusy
        text: {
            if (root.searching && root.query.length)
                return "no results";
            return "No wallpapers in " + root.dirLabel;
        }
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Text {
        anchors.centerIn: parent
        visible: root.searchBusy
        text: "searching…"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 11 * root.s
        visible: root.itemCount > 0 && !root.searching
        opacity: root.hintShown ? 1 : 0
        text: "← → move · ↵ set · hold delete · / search"
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: Font.Medium
        font.letterSpacing: 0.4 * root.s
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
    }

    MouseArea {
        id: wheelArea
        anchors.fill: parent
        z: 20
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0) {
                root.move(-notches);
                acc -= notches;
            }
            event.accepted = true;
        }
    }
}

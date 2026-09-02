pragma ComponentBehavior: Bound

import QtQuick

/**
 * Lazy surface loader for the pill. Defaults to inactive and filling the pill
 * body, so a surface declaration collapses to a single line that only carries
 * the surface-specific props and signal handlers.
 *
 * Each loader names its surface (`name: "mixer"`) and the pill it belongs to
 * (`host: pill`). On creation it registers itself into the host's
 * `_surfaceLoaders` map, so the pill never hand-maintains the name→loader
 * table. When the surface item loads, the shared s/open/morphCloseness props
 * are bound onto it from the host as reactive Qt.binding bindings (surfaces
 * are PillSurface subclasses and declare those props), so the loaders carry
 * no repeated s/open/morphCloseness triple.
 *
 * Compilation is deferred to first open: the loader carries a `sourceUrl`
 * (the surface file, resolved from this file's directory) and only calls
 * `setSource` inside `activate()`, which the host invokes the first time the
 * surface is opened. A surface that is never opened in a session therefore
 * never pays its QML compile cost — the 28 surface components were the
 * single largest chunk of the pill's startup memory. Once a surface has been
 * opened once, its compiled component stays cached on the Loader, so later
 * opens behave exactly like the old eager `sourceComponent` loaders.
 *
 * Creation is opt-in asynchronous per surface: heavy surfaces set the
 * inherited `asynchronous: true` on their declaration, so their first open
 * builds in frame gaps instead of blocking the frame that starts the morph.
 * Default (off) keeps light surfaces instant. Async only delays *when* the
 * item exists — the host's size thunks must treat a null item as "still
 * loading" (see the measure helpers in Pill.qml) and re-morph when the item
 * lands, which the read of `item` re-registers as a dependency.
 *
 * Per-surface extra props arrive through `surfaceProps` (prop name → function
 * returning the value, applied as reactive bindings on load) and the close /
 * surface-navigation signal forwards are centralized here instead of inline
 * handlers: `requestClose` routes to the host's close (or `closeAction` when
 * set, e.g. polkit's cancel), `requestSurface` routes to the host's surface
 * switcher.
 */
Loader {
    id: loader

    active: false
    anchors.fill: parent

    /** The pill surface this loader hosts, e.g. "mixer". Registry key. */
    property string name: ""

    /**
     * The pill that owns this loader; drives self-registration and the shared
     * props. Bound at declaration (`host: pill`), before any item can load, so
     * onLoaded always sees it set.
     */
    property var host: null

    /**
     * Surface file to load on first open, relative to this file's directory
     * (e.g. "widgets/mixer/Mixer.qml"). Empty until `activate()` calls
     * `setSource`, so nothing compiles until the surface is actually opened.
     */
    property string sourceUrl: ""

    /**
     * Extra per-surface props applied as reactive bindings once the item
     * loads: property name → function returning the value (the function's
     * property reads become the binding's dependencies). Mirrors the shared
     * s/open/morphCloseness treatment, so a surface can keep receiving
     * live-updating props (calendarFocusDate, mediaOpen, …) without inline
     * declarations.
     */
    property var surfaceProps: ({})

    /**
     * Optional custom close handler, used instead of the host's requestClose
     * (the polkit face must cancel its prompt rather than dismiss the pill).
     */
    property var closeAction: null

    /**
     * Compiles (first open) and activates this loader. Called by the host's
     * surfaceItem whenever a surface is requested. Subsequent calls are
     * cheap: the source is already set, so only `active` flips.
     */
    function activate() {
        if (!loader.active && loader.sourceUrl.length && !loader.source.length)
            loader.setSource(loader.sourceUrl);
        loader.active = true;
    }

    Component.onCompleted: {
        if (loader.host && loader.name.length)
            loader.host._surfaceLoaders[loader.name] = loader;
    }

    onLoaded: {
        const it = loader.item;
        if (it && loader.host) {
            it.s = Qt.binding(() => loader.host.s);
            /**
             * The surface counts as open only while the pill is actually
             * showing it: when the OSD preempts the pill for a flash, `open`
             * drops so the surface dissolves instead of being crushed under
             * the OSD-sized body, and it fades back in as the pill morphs
             * back to the surface.
             */
            it.open = Qt.binding(() => loader.host.surface === loader.name && loader.host.mode !== "osd");
            it.morphCloseness = Qt.binding(() => loader.host.morphCloseness);
            for (var k in loader.surfaceProps)
                it[k] = Qt.binding(loader.surfaceProps[k]);
            if (it.requestClose)
                it.requestClose.connect(loader.closeAction ? loader.closeAction : () => loader.host.requestClose());
            if (it.requestSurface)
                it.requestSurface.connect((n) => loader.host.requestSurface(n));
        }
    }
}

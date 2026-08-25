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
 * Creation is opt-in asynchronous per surface: heavy surfaces set the
 * inherited `asynchronous: true` on their declaration, so their first open
 * builds in frame gaps instead of blocking the frame that starts the morph.
 * Default (off) keeps light surfaces instant. Async only delays *when* the
 * item exists — the host's size thunks must treat a null item as "still
 * loading" (see the measure helpers in Pill.qml) and re-morph when the item
 * lands, which the read of `item` re-registers as a dependency.
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
        }
    }
}

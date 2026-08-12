pragma ComponentBehavior: Bound

import QtQuick

/**
 * Lazy surface loader for the pill. Extends Loader with the two properties
 * every pill surface loader shares — anchors.fill: parent and active: false —
 * so the Loader block is about half as tall.
 *
 * Each loader names its surface (`name: "mixer"`) and the pill it belongs to
 * (`host: pill`). On creation it registers itself into the host's
 * `_surfaceLoaders` map, so the pill never hand-maintains the name→loader
 * table. When the surface item loads, the shared s/open/morphCloseness props
 * are bound onto it from the host as reactive Qt.binding bindings (surfaces
 * are PillSurface subclasses and declare those props), so loader declarations
 * only carry the surface-specific props and signals — no repeated
 * s/open/morphCloseness triple per surface.
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
            it.open = Qt.binding(() => loader.host.surface === loader.name);
            it.morphCloseness = Qt.binding(() => loader.host.morphCloseness);
        }
    }
}

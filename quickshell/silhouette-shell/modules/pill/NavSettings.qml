import QtQml

/**
 * Settings-family navigation for the pill: resolving the open row-based
 * surface (settings and its sub-surfaces, plus the font picker) and driving
 * its focused row. All pill state lives on the host (`host`).
 */
QtObject {
    id: settings

    required property var host

    /**
     * Resolve an open surface's item through the pill's loader registry (null
     * when not open). The name keys must match the surface-name → loader map
     * each PillSurfaceLoader registers into on creation.
     */
    function itemFor(name) {
        var ld = host._surfaceLoaders[name];
        return ld ? ld.item : null;
    }

    function rowNavSurface() {
        if (host.settingsOpen)
            return itemFor("settings");
        if (host.appearanceOpen)
            return itemFor("appearance");
        if (host.lookOpen)
            return itemFor("look");
        if (host.inputOpen)
            return itemFor("input");
        if (host.displayOpen)
            return itemFor("display");
        if (host.animationOpen)
            return itemFor("animation");
        if (host.idlelockOpen)
            return itemFor("idlelock");
        if (host.fontpickerOpen)
            return itemFor("fontpicker");
        return null;
    }

    /**
     * Move the focused settings row by `dir` (+1 down, -1 up), carrying the soul
     * seam. Returns true when a settings-family surface is open and consumed it.
     */
    function settingsMove(dir) {
        var nav = host.rowNavSurface();
        if (!nav)
            return false;
        nav.kbMove(dir);
        return true;
    }

    /**
     * Left/right on an open settings surface: adjust the focused row's value
     * (seg cycle, toggle flip, scrub bump). Returns false when the focused row
     * is a nav row (nothing to adjust) so vim h/l fall through to back/enter
     * instead of being swallowed.
     */
    function settingsAdjust(dir) {
        var nav = host.rowNavSurface();
        if (!nav || !nav.rows || nav.rows.length === 0)
            return false;
        var idx = nav.kbIndex < 0 ? 0 : nav.kbIndex;
        if (idx >= nav.rows.length)
            return false;
        var r = nav.rows[idx];
        if (!r || r.kind === "nav")
            return false;
        if (nav.kbIndex < 0) {
            nav.kbIndex = 0;
            nav.focusRowItem = nav.rows[0].item;
        }
        nav.kbAdjust(dir);
        return true;
    }

    /**
     * Activate the focused settings row: a toggle flips, a nav row opens its
     * sub-surface. Returns true when a settings-family surface is open.
     */
    function settingsActivate() {
        var nav = host.rowNavSurface();
        if (!nav)
            return false;
        nav.kbActivate();
        return true;
    }

    /**
     * Slide the open keybinds list's focused row by `dir` (+1 down, -1 up),
     * carrying the soul seam. No-op unless the keybinds surface is open.
     */
    function keybindsMove(dir) {
        if (host.keybindsOpen && itemFor("keybinds"))
            itemFor("keybinds").move(dir);
    }

    /**
     * Enter on the open keybinds surface: arm chord capture on the focused row.
     * No-op unless the keybinds surface is open.
     */
    function keybindsActivate() {
        if (host.keybindsOpen && itemFor("keybinds"))
            itemFor("keybinds").activate();
    }
}

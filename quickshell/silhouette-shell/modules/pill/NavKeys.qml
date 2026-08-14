import QtQml

/**
 * Composed menu navigation for the pill, shared by the arrow keys and (with
 * the vim flag on) h/j/k/l. Each function returns true when an open surface
 * consumed it, which the key handlers in PillRoot read to accept the event.
 * Every action goes through the host pill's forwarding wrappers, so this
 * module only needs the pill.
 */
QtObject {
    id: keys

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

    function navUp() {
        if (host.keybindsOpen && !host.keybindsListening) { host.keybindsMove(-1); return true; }
        /** The recorder's chooser tiles are horizontal; don't step the faders behind it. */
        if (host.recorderOpen && host.recorderChooserOpen)
            return false;
        return host.calendarMove("v", -1) || host.linkMove(-1) || host.mixerStep(1)
            || host.recorderStep(5) || host.clipboardMove(-1)
            || host.fontpickerMove(-1) || host.launcherMove(-1) || host.localsendMove(-1)
            || host.workspacesMove(-1) || host.stashMove(-1) || host.spaceappsMove(-1)
            || host.settingsMove(-1)
            || (host.timerOpen && host.timerActivate());
    }
    function navDown() {
        if (host.keybindsOpen && !host.keybindsListening) { host.keybindsMove(1); return true; }
        if (host.recorderOpen && host.recorderChooserOpen)
            return false;
        return host.calendarMove("v", 1) || host.linkMove(1) || host.mixerStep(-1)
            || host.recorderStep(-5) || host.clipboardMove(1)
            || host.fontpickerMove(1) || host.launcherMove(1) || host.localsendMove(1)
            || host.workspacesMove(1) || host.stashMove(1) || host.spaceappsMove(1)
            || host.settingsMove(1)
            || (host.timerOpen && host.timerActivate());
    }
    function navLeft() {
        if (host.quickChoosing) return host.quickChooseMove(-1);
        if (host.recorderChooserOpen) return host.recorderChooserMove(-1);
        if (host.calendarOpen) return host.calendarMove("h", -1);
        if (host.mixerOpen) { host.mixerFocusMove(-1); return true; }
        if (host.wallpaperOpen) { host.wallpaperMove(-1); return true; }
        if (host.powerOpen) { host.powerMove(-1); return true; }
        if (host.recorderOpen) { host.recorderStep(-5); return true; }
        if (host.linkOpen) return host.linkAdjust(-1);
        if (host.settingsLike) return host.settingsAdjust(-1);
        if (host.mode === "hover" && !host.surfaceOpen) return host.faceMove(-1);
        return false;
    }
    function navRight() {
        if (host.quickChoosing) return host.quickChooseMove(1);
        if (host.recorderChooserOpen) return host.recorderChooserMove(1);
        if (host.calendarOpen) return host.calendarMove("h", 1);
        if (host.mixerOpen) { host.mixerFocusMove(1); return true; }
        if (host.wallpaperOpen) { host.wallpaperMove(1); return true; }
        if (host.powerOpen) { host.powerMove(1); return true; }
        if (host.recorderOpen) { host.recorderStep(5); return true; }
        if (host.linkOpen) return host.linkAdjust(1);
        if (host.settingsLike) return host.settingsAdjust(1);
        if (host.mode === "hover" && !host.surfaceOpen) return host.faceMove(1);
        return false;
    }

    /**
     * Vim `h` with no horizontal nav available: back out of the current menu,
     * mirroring the Backspace chain (quick-record cancel, recorder chooser
     * step-back, link subview pop, hover-face collapse, then surface back).
     */
    function vimBack() {
        if (host.quickChoosing) {
            host.quickChooseBack();
        } else if (!host.recorderChooserBack() && !host.linkBack() && !host.faceBack()) {
            host.surfaceBack();
        }
    }

    /**
     * Pop the open link surface one subview back. Returns true when the step was
     * consumed, false when the surface is already at its root (or not open) and
     * Escape should close the surface instead.
     */
    function linkBack() {
        return (host.linkOpen && itemFor("link")) ? itemFor("link").back() : false;
    }

    /**
     * Pop the open keybinds editor form back to the bind list. Returns true when a
     * form was open and dismissed, false otherwise so Escape closes the surface.
     */
    function keybindsBack() {
        if (host.keybindsOpen && itemFor("keybinds") && itemFor("keybinds").formOpen) {
            itemFor("keybinds").closeForm();
            return true;
        }
        return false;
    }

    /**
     * Backspace on the open timer surface: dismiss it. Returns true when consumed.
     */
    function timerBack() {
        if (!host.timerOpen || !itemFor("timer"))
            return false;
        host.requestClose();
        return true;
    }

    /**
     * Backspace on the recorder's inline source chooser: step the chooser back a
     * level (monitor sub-choice to sources, sources to the recorder). Returns true
     * when consumed.
     */
    function recorderChooserBack() {
        return (host.recorderOpen && itemFor("recorder")) ? itemFor("recorder").chooserBack() : false;
    }

    /**
     * Vim `l` with no horizontal nav available: enter the current menu,
     * mirroring the Return chain (activate the focused item of the open
     * surface, or the hover face when resting).
     */
    function vimEnter() {
        if (host.quickChoosing) {
            host.quickChooseActivate();
        } else if (host.wallpaperOpen) {
            host.wallpaperActivate();
        } else if (host.powerOpen) {
            host.powerPress();
        } else if (host.recorderChooserOpen) {
            host.recorderChooserActivate();
        } else if (host.recorderOpen) {
            host.recorderPress();
        } else if (host.calendarOpen) {
            host.calendarActivate();
        } else if (host.linkOpen) {
            host.linkActivate();
        } else if (host.clipboardOpen) {
            host.clipboardActivate();
        } else if (host.fontpickerOpen) {
            host.fontpickerActivate();
        } else if (host.localsendOpen) {
            host.localsendActivate();
        } else if (host.timerOpen) {
            host.timerActivate();
        } else if (host.workspacesOpen) {
            host.workspacesActivate();
        } else if (host.stashOpen) {
            host.stashActivate();
        } else if (host.spaceappsOpen) {
            host.spaceappsActivate();
        } else if (host.keybindsOpen && !host.keybindsListening) {
            host.keybindsActivate();
        } else if (host.settingsLike) {
            host.settingsActivate();
        } else if (host.mode === "hover" && !host.surfaceOpen) {
            host.faceActivate();
        }
    }
}

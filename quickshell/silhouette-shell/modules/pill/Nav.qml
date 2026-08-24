import QtQuick
import Quickshell.Services.SystemTray
import qs.services

/**
 * Keyboard routing and hover-face navigation for the pill, extracted from
 * Pill.qml. Pure logic: every function drives the host pill's public API and
 * its surfaces through the loader registry (`host._surfaceLoaders`), so the
 * pill keeps only thin forwarding wrappers plus the few properties PillRoot
 * reads directly. `quickChooserItem`, `minimizedRow` and `trayRow` are aliases
 * on the host for the child widgets this module drives.
 */
Item {
    id: nav

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

    function openCalendarAt(date) {
        host.calendarFocusDate = date
        host.requestSurface("calendar")
    }

    /**
     * Forward an arrow-key nudge to the open mixer's targeted fader. Returns true
     * when the mixer is open and a fader consumed the step.
     */
    function mixerStep(deltaPct) {
        return (host.mixerOpen && itemFor("mixer")) ? itemFor("mixer").stepFocused(deltaPct) : false;
    }

    /**
     * Move the open mixer's keyboard focus across the fader row; `dir` is +1
     * (right) or -1 (left). No-op unless the mixer is open.
     */
    function mixerFocusMove(dir) {
        if (host.mixerOpen && itemFor("mixer"))
            itemFor("mixer").moveFocus(dir);
    }

    /**
     * Forward an arrow-key nudge to the open recorder's focused audio fader.
     * Returns true when the recorder is open and a revealed fader consumed it.
     */
    function recorderStep(deltaPct) {
        return (host.recorderOpen && itemFor("recorder")) ? itemFor("recorder").stepFocused(deltaPct) : false;
    }

    NavSettings {
        id: navSettings
        host: nav.host
    }

    NavQuick {
        id: navQuick
        host: nav.host
    }

    /**
     * Step the open surface back one level when its header bar is clicked: a
     * settings sub-surface returns to the index, the font picker to appearance,
     * a keybinds form to its list, and any other surface dismisses to the hover
     * pill. Empty space in the body never triggers this.
     */
    function surfaceBack() {
        if (host.keybindsOpen) {
            if (itemFor("keybinds") && itemFor("keybinds").formOpen)
                itemFor("keybinds").closeForm();
            else
                host.requestSurface("settings");
            return;
        }
        if (host.fontpickerOpen) {
            host.requestSurface("appearance");
            return;
        }
        if (host.stashOpen) {
            if (itemFor("stash") && itemFor("stash").addOpen)
                itemFor("stash").closeAdd();
            else
                host.requestSurface("workspaces");
            return;
        }
        if (host.spaceappsOpen) {
            if (itemFor("spaceapps") && itemFor("spaceapps").addOpen)
                itemFor("spaceapps").closeAdd();
            else
                host.requestSurface("workspaces");
            return;
        }
        if (host.workspacesOpen && itemFor("workspaces") && itemFor("workspaces").formOpen) {
            itemFor("workspaces").closeForm();
            return;
        }
        if (host.calendarOpen && itemFor("calendar") && itemFor("calendar").editorShown) {
            itemFor("calendar").closeEditor();
            return;
        }
        if (host.appearanceOpen || host.updatesOpen || host.displayOpen || host.inputOpen || host.lookOpen || host.idlelockOpen || host.animationOpen || host.workspacesOpen) {
            host.requestSurface("settings");
            return;
        }
        host.requestClose();
    }

    /**
     * Slide the open wallpaper strip's focus by `dir` thumbs; +1 is right (older)
     * and -1 is left (newer). No-op unless the wallpaper surface is open.
     */
    function wallpaperMove(dir) {
        if (host.wallpaperOpen && itemFor("wallpaper"))
            itemFor("wallpaper").move(dir);
    }

    /**
     * Apply the wallpaper strip's focused thumb through wallpaper.sh. The
     * surface stays open so the pick can be iterated. No-op unless the
     * wallpaper surface is open.
     */
    function wallpaperActivate() {
        if (host.wallpaperOpen && itemFor("wallpaper"))
            itemFor("wallpaper").activate();
    }

    /** Keyboard hold-to-delete on the wallpaper strip. */
    function wallpaperHoldPress() {
        if (host.wallpaperOpen && itemFor("wallpaper"))
            itemFor("wallpaper").holdPress();
    }

    /**
     * Route the first printable keystroke over the open wallpaper strip into a
     * DuckDuckGo search seeded with that character. No-op unless the wallpaper
     * surface is open.
     */
    function wallpaperType(ch) {
        if (host.wallpaperOpen && itemFor("wallpaper"))
            itemFor("wallpaper").startSearch(ch);
    }

    /**
     * Slide the open power surface's keyboard focus by `dir` tiles; +1 is right
     * and -1 is left. No-op unless the power surface is open.
     */
    function powerMove(dir) {
        if (host.powerOpen && itemFor("power"))
            itemFor("power").move(dir);
    }

    /**
     * Enter pressed on the open power surface's focused tile: fires a safe tile
     * at once, latches a destructive tile's heat hold. Returns true when a tile
     * consumed the key. No-op (false) unless the power surface is open.
     */
    function powerPress() {
        return (host.powerOpen && itemFor("power")) ? itemFor("power").pressFocused() : false;
    }

    /**
     * Enter released on the open power surface: drains an unfinished destructive
     * hold so a key let go before the fill completes never confirms.
     */
    function powerRelease() {
        if (host.powerOpen && itemFor("power"))
            itemFor("power").releaseFocused();
    }

    /**
     * Slide the open clipboard's selection by `delta` rows. Returns true when
     * the clipboard surface consumed it.
     */
    function clipboardMove(delta) {
        if (!host.clipboardOpen || !itemFor("clipboard"))
            return false;
        itemFor("clipboard").move(delta);
        return true;
    }

    /** Return on the open clipboard: copy the selected entry and close. */
    function clipboardActivate() {
        if (!host.clipboardOpen || !itemFor("clipboard"))
            return false;
        itemFor("clipboard").activate();
        return true;
    }

    /**
     * Slide the open font picker's highlight by `dir`. Returns true when the
     * picker consumed it.
     */
    function fontpickerMove(dir) {
        if (!host.fontpickerOpen || !itemFor("fontpicker"))
            return false;
        itemFor("fontpicker").move(dir);
        return true;
    }

    /** Return on the open font picker: pick the highlighted family. */
    function fontpickerActivate() {
        if (!host.fontpickerOpen || !itemFor("fontpicker"))
            return false;
        itemFor("fontpicker").activate();
        return true;
    }

    function timerActivate() {
        if (!host.timerOpen || !itemFor("timer"))
            return false;
        itemFor("timer").toggle();
        return true;
    }

    function timerReset() {
        if (!host.timerOpen || !itemFor("timer"))
            return false;
        itemFor("timer").reset();
        return true;
    }

    /**
     * Slide the open launcher's selection by `delta`. Returns true when the
     * launcher consumed it.
     */
    function launcherMove(delta) {
        if (!host.launcherOpen || !itemFor("launcher"))
            return false;
        itemFor("launcher").move(delta);
        return true;
    }

    /** Return on the open launcher: launch the selected entry. */
    function launcherActivate() {
        if (!host.launcherOpen || !itemFor("launcher"))
            return false;
        itemFor("launcher").activate();
        return true;
    }

    /**
     * Return on the open recorder: press its action bar (start / stop / open
     * the source chooser).
     */
    function recorderPress() {
        if (!host.recorderOpen || !itemFor("recorder"))
            return false;
        itemFor("recorder").press();
        return true;
    }

    /**
     * Slide the open workspaces hub's focus by `dir`. Returns true when the
     * hub consumed it.
     */
    function workspacesMove(dir) {
        if (!host.workspacesOpen || !itemFor("workspaces"))
            return false;
        itemFor("workspaces").move(dir);
        return true;
    }

    /**
     * Return on the open workspaces hub: open the focused row's surface or the
     * add-workspace form.
     */
    function workspacesActivate() {
        if (!host.workspacesOpen || !itemFor("workspaces"))
            return false;
        itemFor("workspaces").activate();
        return true;
    }

    /**
     * Slide the open stash list's focus by `dir` (+1 down, -1 up), across the
     * stashed apps and the add-app bar. Returns true when consumed.
     */
    function stashMove(dir) {
        if (!host.stashOpen || !itemFor("stash"))
            return false;
        itemFor("stash").move(dir);
        return true;
    }

    /**
     * Return on the open stash list: remove the focused app, or open the add
     * picker when the add bar is focused. Returns true when consumed.
     */
    function stashActivate() {
        if (!host.stashOpen || !itemFor("stash"))
            return false;
        itemFor("stash").activate();
        return true;
    }

    /** Slide the open space-apps list's focus by `dir`. Returns true when consumed. */
    function spaceappsMove(dir) {
        if (!host.spaceappsOpen || !itemFor("spaceapps"))
            return false;
        itemFor("spaceapps").move(dir);
        return true;
    }

    /** Return on the open space-apps list: remove the focused app, or open the picker. */
    function spaceappsActivate() {
        if (!host.spaceappsOpen || !itemFor("spaceapps"))
            return false;
        itemFor("spaceapps").activate();
        return true;
    }

    /**
     * Move the open calendar's keyboard day by `dir` along `axis` ("h" rows
     * by one day, "v" by a week). Returns true when the calendar consumed it.
     */
    function calendarMove(axis, dir) {
        if (!host.calendarOpen || !itemFor("calendar"))
            return false;
        itemFor("calendar").kbMove(axis, dir);
        return true;
    }

    /** Return on the open calendar: select the keyboard-focused day. */
    function calendarActivate() {
        if (!host.calendarOpen || !itemFor("calendar"))
            return false;
        itemFor("calendar").kbActivate();
        return true;
    }

    /**
     * Slide the open link surface's row focus by `dir`, across the rows of the
     * active subview (connectivity rows, wifi networks, bt devices). Returns
     * true when the link surface consumed it.
     */
    function linkMove(dir) {
        if (!host.linkOpen || !itemFor("link"))
            return false;
        itemFor("link").kbMove(dir);
        return true;
    }

    /** Return on the open link surface: activate the focused row. */
    function linkActivate() {
        if (!host.linkOpen || !itemFor("link"))
            return false;
        itemFor("link").kbActivate();
        return true;
    }

    /**
     * Left/right on the open link surface: cycle the focused subview row's
     * confirm buttons (connect/disconnect, reveal, forget). Returns true when
     * the link surface consumed it.
     */
    function linkAdjust(dir) {
        if (!host.linkOpen || !itemFor("link"))
            return false;
        return itemFor("link").kbAdjust(dir);
    }

    /**
     * Move the recorder's inline source chooser focus by `dir`: across the
     * Screen / Window tiles, or the monitor tiles in the sub-chooser. Returns
     * true when the chooser consumed it.
     */
    function recorderChooserMove(dir) {
        return (host.recorderOpen && itemFor("recorder")) ? itemFor("recorder").chooserMove(dir) : false;
    }

    /** Return on the recorder's inline source chooser: pick the focused tile. */
    function recorderChooserActivate() {
        return (host.recorderOpen && itemFor("recorder")) ? itemFor("recorder").chooserActivate() : false;
    }

    /**
     * Backspace on the recorder's inline source chooser: the monitor sub-
     * chooser returns to the sources, the sources close the chooser. Returns
     * true when a chooser was open and consumed it.
     */
    NavFace {
        id: navFace
        host: nav.host
    }

    /**
     * Focus the open picker's search field, for a forward-slash keypress.
     * Returns true when a picker consumed it.
     */
    function focusSearch() {
        if (host.keybindsOpen && itemFor("keybinds")) {
            itemFor("keybinds").focusSearch();
            return true;
        }
        if (host.fontpickerOpen && itemFor("fontpicker")) {
            itemFor("fontpicker").focusSearch();
            return true;
        }
        if (host.clipboardOpen && itemFor("clipboard")) {
            itemFor("clipboard").focusField();
            return true;
        }
        if (host.launcherOpen && itemFor("launcher")) {
            itemFor("launcher").focusField();
            return true;
        }
        if (host.wallpaperOpen && itemFor("wallpaper")) {
            itemFor("wallpaper").focusSearch();
            return true;
        }
        return false;
    }

    /**
     * Composed menu navigation, shared by the arrow keys and (with the vim
     * flag on) h/j/k/l. Each returns true when an open surface consumed it,
     * which the key handlers in PillRoot read to accept the event. The pill
     * owns the routing so the per-monitor key handling stays a thin shell.
     */
    NavKeys {
        id: navKeys
        host: nav.host
    }

    /** Forwards to the domain modules, keeping the pill's routing facade stable. */
    function linkBack() { return navKeys.linkBack(); }
    function keybindsBack() { return navKeys.keybindsBack(); }
    function timerBack() { return navKeys.timerBack(); }
    function recorderChooserBack() { return navKeys.recorderChooserBack(); }
    function rowNavSurface() { return navSettings.rowNavSurface(); }
    function settingsMove(dir) { return navSettings.settingsMove(dir); }
    function settingsAdjust(dir) { return navSettings.settingsAdjust(dir); }
    function settingsActivate() { return navSettings.settingsActivate(); }
    function keybindsMove(dir) { return navSettings.keybindsMove(dir); }
    function keybindsActivate() { return navSettings.keybindsActivate(); }
    function quickChooseSource(kind) { return navQuick.quickChooseSource(kind); }
    function quickPickMonitor(name) { return navQuick.quickPickMonitor(name); }
    function quickChooseMove(dir) { return navQuick.quickChooseMove(dir); }
    function quickChooseActivate() { return navQuick.quickChooseActivate(); }
    function quickChooseBack() { return navQuick.quickChooseBack(); }
    function faceMove(dir) { return navFace.faceMove(dir); }
    function faceActivate() { return navFace.faceActivate(); }
    function faceBack() { return navFace.faceBack(); }
    function navUp() { return navKeys.navUp(); }
    function navDown() { return navKeys.navDown(); }
    function navLeft() { return navKeys.navLeft(); }
    function navRight() { return navKeys.navRight(); }
    function vimBack() { return navKeys.vimBack(); }
    function vimEnter() { return navKeys.vimEnter(); }
}

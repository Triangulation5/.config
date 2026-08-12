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
QtObject {
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

    /**
     * Resolve which settings-family surface owns keyboard row navigation right
     * now: the category index or one of its morphing sub-surfaces. Returns null
     * when none of them is open.
     */
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

    /**
     * A tile was picked in the standalone quick-record chooser. Screen with several
     * monitors flips to the inline sub-choice; otherwise each source kicks off its
     * resolver (which counts down once the target is ready) and the chooser closes.
     */
    function quickChooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                ScreenRec.quickScreenChoosing = true;
                return;
            }
            ScreenRec.prepareScreen(host.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
    }

    function quickPickMonitor(name) {
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
        ScreenRec.prepareScreen(name);
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

    function localsendMove(dir) {
        if (!host.localsendOpen || !itemFor("localsend"))
            return false;
        itemFor("localsend").move(dir);
        return true;
    }

    function localsendActivate() {
        if (!host.localsendOpen || !itemFor("localsend"))
            return false;
        itemFor("localsend").activate();
        return true;
    }

    function timerBack() {
        if (!host.timerOpen || !itemFor("timer"))
            return false;
        host.requestClose();
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
    function recorderChooserBack() {
        return (host.recorderOpen && itemFor("recorder")) ? itemFor("recorder").chooserBack() : false;
    }

    /**
     * Move the standalone quick-record chooser's focus by `dir`: across the
     * Screen / Window tiles, or the monitor tiles in the sub-choice. Returns
     * true when the chooser consumed it.
     */
    function quickChooseMove(dir) {
        if (!host.quickChoosing)
            return false;
        host.quickChooserItem.move(dir);
        return true;
    }

    /** Return on the quick-record chooser: pick the focused tile. */
    function quickChooseActivate() {
        if (!host.quickChoosing)
            return false;
        host.quickChooserItem.activate();
        return true;
    }

    /**
     * Backspace on the quick-record chooser: the monitor sub-choice returns to
     * the sources, the sources cancel the chooser. Returns true when consumed.
     */
    function quickChooseBack() {
        if (!host.quickChoosing)
            return false;
        host.quickChooserItem.back();
        return true;
    }

    readonly property var faceTargets: {
        var out = [];
        if (host.hasMedia) out.push("media");
        if (host.minimizedRow.count > 0) out.push("minimized");
        if (SystemTray.items.values.length > 0) out.push("tray");
        out.push("clock");
        return out;
    }
    readonly property int faceCount: faceTargets.length

    function faceMove(dir) {
        if (host.surfaceOpen || host.mode !== "hover" || faceCount < 2)
            return false;
        if (host.faceFocus < 0 || host.faceFocus >= faceCount)
            host.faceFocus = 0;
        var key = faceTargets[host.faceFocus];
        /**
         * While the ring sits on a per-icon widget, arrows walk its icons and
         * step out to the neighbouring face target at the edges.
         */
        if (key === "minimized") {
            if (host.minimizedRow.focusIndex < 0)
                host.minimizedRow.focusIndex = 0;
            if (dir < 0 && host.minimizedRow.focusIndex === 0)
                host.faceFocus = (host.faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && host.minimizedRow.focusIndex === host.minimizedRow.count - 1)
                host.faceFocus = (host.faceFocus + 1) % faceCount;
            else
                host.minimizedRow.moveFocus(dir);
            return true;
        }
        if (key === "tray") {
            var nItems = SystemTray.items.values.length;
            if (host.trayRow.focusIndex < 0)
                host.trayRow.focusIndex = 0;
            if (dir < 0 && host.trayRow.focusIndex === 0)
                host.faceFocus = (host.faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && host.trayRow.focusIndex === nItems - 1)
                host.faceFocus = (host.faceFocus + 1) % faceCount;
            else
                host.trayRow.moveFocus(dir);
            return true;
        }
        host.faceFocus = (host.faceFocus + dir + faceCount) % faceCount;
        var landed = faceTargets[host.faceFocus];
        if (landed === "minimized" && host.minimizedRow.focusIndex < 0)
            host.minimizedRow.focusIndex = 0;
        if (landed === "tray" && host.trayRow.focusIndex < 0)
            host.trayRow.focusIndex = 0;
        return true;
    }

    function faceActivate() {
        if (host.surfaceOpen || host.mode !== "hover")
            return false;
        var key = host.faceFocus >= 0 && host.faceFocus < faceCount ? faceTargets[host.faceFocus] : "clock";
        if (key === "media") {
            host.requestSurface("media");
        } else if (key === "minimized") {
            if (host.minimizedRow.focusIndex < 0)
                host.minimizedRow.focusIndex = 0;
            host.minimizedRow.activate();
        } else if (key === "tray") {
            if (host.trayRow.focusIndex < 0)
                host.trayRow.focusIndex = 0;
            host.trayRow.activate();
        } else {
            host.openCalendarAt(null);
        }
        return true;
    }

    /**
     * Escape/Backspace on the hover face: unpin if held and collapse the pill
     * back to rest. Returns true when the face was showing and consumed it.
     */
    function faceBack() {
        if (host.surfaceOpen || host.mode !== "hover")
            return false;
        if (host.pinned)
            host.pinned = false;
        host.hoverLatch = false;
        host.host.faceFocus = -1;
        return true;
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

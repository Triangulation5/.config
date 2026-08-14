import QtQml
import qs.services

/**
 * Quick-record chooser navigation for the pill: source picks (screen with an
 * inline monitor sub-choice, or window) that hand off to the ScreenRec
 * resolvers, plus the arrow/return/back handlers for the chooser tiles.
 */
QtObject {
    id: quick

    required property var host

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
}

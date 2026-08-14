pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.pill

/**
 * One per-monitor overlay window hosting the morphing pill. It owns the input
 * mask (pill rect vs full-screen when modal), the backdrop press handling, and
 * the keyboard focus scope that routes arrows / vim / backspace / return to
 * the pill's nav module. All surface routing state lives on the host
 * (`host`, the shell root): open surface, peek monitor, and the per-monitor
 * collapsed flags.
 */
Variants {
    id: overlayRoot

    required property var host

    model: Quickshell.screens

    PanelWindow {
        id: overlay
        required property var modelData
        readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
        readonly property real topGap: 8 * Flags.topGap * s
        readonly property string surface: host.openMon === modelData.name ? host.openSurface : ""
        readonly property bool surfaceOpen: surface.length > 0
        readonly property bool modal: pill.authPending ? false : (surfaceOpen || pill.held || pill.quickChoosing)

        /**
         * Auto-hide: with the flag on, the rest pill retracts off the top
         * edge and the band mask collapses to a thin strip, so a pointer
         * touch anywhere along the top edge wakes it. Anything that needs
         * the pill (an open surface, pin, peek, OSD/toast, special
         * workspace) keeps it down.
         */
        readonly property bool autoRetracted: Flags.autoHide && !monFullscreen
            && pill.specialView === "" && pill.mode === "rest"

        /**
         * True while auto-hide keeps the reserved band collapsed: the pill
         * is either retracted off-screen or floating over windows in a
         * transient hover, an open surface, OSD, toast or quick-record. The
         * band is only reclaimed once the pill is held (pin/peek) or a
         * special workspace forces the pill on, so windows never shift
         * from a glance at the bar or an auto-hidden surface.
         */
        readonly property bool autoCollapsed: Flags.autoHide && !monFullscreen
            && pill.specialView === "" && !pill.held

        /** The wake strip and the growing hover band, shared by the mask. */
        readonly property real autoStripH: 5 * s
        readonly property real autoBandH: Math.max(autoStripH, pill.y + pill.height + autoStripH)

        onAutoCollapsedChanged: host.setPillCollapsed(modelData.name, autoCollapsed)
        Component.onCompleted: host.setPillCollapsed(modelData.name, autoCollapsed)

        /**
         * True while this monitor's active workspace holds a real
         * fullscreen window. The pill then retracts off the top edge and
         * the whole layer becomes click-through so fullscreen content owns
         * the screen. Maximize is suppressed globally, so only true
         * fullscreen ever flips this.
         */
        readonly property bool monFullscreen: {
            var mons = Hyprland.monitors.values;
            for (var i = 0; i < mons.length; i++) {
                if (mons[i].name === modelData.name) {
                    var ws = mons[i].activeWorkspace;
                    var o = ws ? ws.lastIpcObject : null;
                    return o ? !!o.hasfullscreen : false;
                }
            }
            return false;
        }

        onMonFullscreenChanged: if (monFullscreen) {
            if (host.openMon === modelData.name) host.close();
            if (host.peekMon === modelData.name) host.peekMon = "";
            pill.pinned = false;
        }

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: ((surfaceOpen || pill.quickChoosing) && !pill.authPending) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "pill"

        anchors { top: true; left: true; right: true; bottom: true }

        mask: monFullscreen ? hiddenRegion : (modal ? fullRegion : (Flags.autoHide ? autoRegion : pillRegion))
        Region { id: hiddenRegion }
        Region {
            id: autoRegion
            width: overlay.width
            height: overlay.autoBandH
        }
        Region {
            id: pillRegion
            readonly property real baseW: Math.max(pill.width, pill.targetW)
            x: pill.x + (pill.width - baseW) / 2
            y: pill.y
            width: baseW + pill.inputPadRight
            height: Math.max(pill.height, pill.targetH)
        }
        Region {
            id: fullRegion
            width: overlay.width
            height: overlay.height
        }

        MouseArea {
            anchors.fill: parent
            enabled: overlay.modal
            acceptedButtons: Qt.AllButtons
            onPressed: (mouse) => {
                if (pill.quickChoosing) {
                    ScreenRec.quickChoosing = false;
                    ScreenRec.quickScreenChoosing = false;
                } else if (overlay.surfaceOpen) {
                    var inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width
                        && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                    if (!inside)
                        host.close();
                    else if (mouse.y <= pillRegion.y + 40 * pill.s)
                        pill.surfaceBack();
                } else {
                    pill.pinned = false;
                    host.peekMon = "";
                }
            }
        }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            /**
             * Keyboard ownership follows the pointer. Hovering the pill is
             * already an OnDemand keyboard grab (Hyprland focuses on-demand
             * layers under the cursor), so with the flag below the shell
             * actually uses those keys for the hover face instead of
             * dropping them. A surface or the quick-record chooser takes
             * the keys exclusively.
             */
            focus: overlay.surfaceOpen || pill.quickChoosing
                || (pill.mode === "hover" && pill.hovered)

            HoverHandler {
                onHoveredChanged: pill.hovered = hovered
            }
            Keys.onEscapePressed: {
                if (pill.quickChoosing) {
                    ScreenRec.quickChoosing = false;
                    ScreenRec.quickScreenChoosing = false;
                } else if (pill.surfaceOpen) {
                    host.close();
                } else if (pill.mode === "hover") {
                    pill.pinned = false;
                    pill.hoverLatch = false;
                    pill.faceFocus = -1;
                }
            }
            /**
             * Arrow keys: with the vim flag on they go dead in the menus and
             * h/j/k/l take over (below). Inside a focused search field they
             * still work — that is insert mode.
             */
            Keys.onUpPressed: (e) => {
                if (Flags.vimKeys) return;
                e.accepted = pill.navUp();
            }
            Keys.onDownPressed: (e) => {
                if (Flags.vimKeys) return;
                e.accepted = pill.navDown();
            }
            Keys.onLeftPressed: (e) => {
                if (Flags.vimKeys) return;
                e.accepted = pill.navLeft();
            }
            Keys.onRightPressed: (e) => {
                if (Flags.vimKeys) return;
                e.accepted = pill.navRight();
            }

            /**
             * Return/Enter/Space: the wallpaper strip applies its focused
             * thumb on every press; the power surface fires a safe tile on
             * the first press and, for a destructive tile, holds the heat
             * fill across autorepeat presses (drained on release). Autorepeat
             * is swallowed for everything else so a held key never re-fires.
             */
            Keys.onPressed: (e) => {
                /**
                 * Forward-slash focuses the open picker's search field (the
                 * keybind search, font picker, clipboard, launcher or
                 * wallpaper strip). A focused field consumes it as text, so
                 * this only fires while browsing the list.
                 */
                if (e.key === Qt.Key_Slash && pill.focusSearch()) {
                    e.accepted = true;
                    return;
                }
                if (e.key === Qt.Key_R && !e.isAutoRepeat && pill.timerOpen) {
                    pill.timerReset();
                    e.accepted = true;
                    return;
                }
                /**
                 * Vim navigation: with the flag on, h/j/k/l drive the same
                 * menu moves as the arrows (which are disabled above). h/l
                 * select and deselect — they flip toggles and cycle
                 * segments in the settings rows. A focused search field
                 * still consumes them as text, so this only fires while
                 * browsing. The wallpaper strip is covered too: h/l page
                 * it instead of seeding a search.
                 */
                if (Flags.vimKeys && e.text.length === 1) {
                    var c = e.text;
                    if (c === "h") {
                        /**
                         * Vim `h`: move left where a menu has horizontal
                         * navigation (calendar days, mixer faders, settings
                         * values). In a vertical list (link rows, launcher,
                         * clipboard, settings index) nothing consumes it, so
                         * fall back to backing out — the same chain as
                         * Backspace. Always accepted so the key never leaks
                         * into a search.
                         */
                        if (!pill.navLeft() && !e.isAutoRepeat)
                            pill.vimBack();
                        e.accepted = true;
                        return;
                    }
                    if (c === "j") { e.accepted = pill.navDown(); return; }
                    if (c === "k") { e.accepted = pill.navUp(); return; }
                    if (c === "l") {
                        /**
                         * Vim `l`: move right where a menu has horizontal
                         * navigation, otherwise enter — the same chain as
                         * Return/Enter (drill into a link subview, activate
                         * the focused row). Autorepeat is swallowed so a
                         * held key never re-fires an activate. Always
                         * accepted.
                         */
                        if (!pill.navRight() && !e.isAutoRepeat)
                            pill.vimEnter();
                        e.accepted = true;
                        return;
                    }
                }
                /**
                 * Backspace is the shell-wide "back": it cancels a quick-
                 * record chooser, steps the recorder's inline chooser back,
                 * pops a link subview, collapses the hover face, then runs
                 * the surface's own back navigation (a settings sub-surface
                 * returns to its index, a form closes, anything else
                 * dismisses). Handled in the general onPressed because this
                 * build's Keys exposes no named onBackspacePressed handler.
                 * A focused search field consumes its own Backspace, so this
                 * only fires while browsing.
                 */
                if (e.key === Qt.Key_Backspace) {
                    if (pill.quickChoosing) {
                        pill.quickChooseBack();
                    } else if (!pill.recorderChooserBack() && !pill.linkBack() && !pill.faceBack() && !pill.keybindsBack() && !pill.timerBack()) {
                        pill.surfaceBack();
                    }
                    e.accepted = true;
                    return;
                }
                if (pill.wallpaperOpen && !pill.wallpaperSearching
                    && e.text.length === 1 && e.text > " ") {
                    pill.wallpaperType(e.text);
                    e.accepted = true;
                    return;
                }
                if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space)
                    return;
                /**
                 * Order matters only where branches overlap: the quick-
                 * record chooser is not a surface so it must be claimed
                 * first; the recorder's inline source chooser must be
                 * claimed before the plain recorder press; the font picker
                 * before the settingsLike branch (whose rows are empty
                 * there and would swallow the key).
                 */
                if (pill.quickChoosing) {
                    if (!e.isAutoRepeat) pill.quickChooseActivate();
                    e.accepted = true;
                } else if (pill.wallpaperOpen) {
                    if (e.isAutoRepeat) {
                        if (!pill._wpHoldStarted) {
                            pill._wpHoldStarted = true;
                            pill.wallpaperHoldPress();
                        }
                        e.accepted = true;
                    } else {
                        pill.wallpaperActivate();
                        e.accepted = true;
                    }
                } else if (pill.powerOpen) {
                    if (!e.isAutoRepeat) pill.powerPress();
                    e.accepted = true;
                } else if (pill.recorderChooserOpen) {
                    if (!e.isAutoRepeat) pill.recorderChooserActivate();
                    e.accepted = true;
                } else if (pill.recorderOpen) {
                    if (!e.isAutoRepeat) pill.recorderPress();
                    e.accepted = true;
                } else if (pill.calendarOpen) {
                    if (!e.isAutoRepeat) pill.calendarActivate();
                    e.accepted = true;
                } else if (pill.linkOpen) {
                    if (!e.isAutoRepeat) pill.linkActivate();
                    e.accepted = true;
                } else if (pill.clipboardOpen) {
                    if (!e.isAutoRepeat) pill.clipboardActivate();
                    e.accepted = true;
                } else if (pill.fontpickerOpen) {
                    if (!e.isAutoRepeat) pill.fontpickerActivate();
                    e.accepted = true;
                } else if (pill.launcherOpen) {
                    if (!e.isAutoRepeat) pill.launcherActivate();
                    e.accepted = true;
                } else if (pill.workspacesOpen) {
                    if (!e.isAutoRepeat) pill.workspacesActivate();
                    e.accepted = true;
                } else if (pill.stashOpen) {
                    if (!e.isAutoRepeat) pill.stashActivate();
                    e.accepted = true;
                } else if (pill.spaceappsOpen) {
                    if (!e.isAutoRepeat) pill.spaceappsActivate();
                    e.accepted = true;
                } else if (pill.keybindsOpen && !pill.keybindsListening) {
                    if (!e.isAutoRepeat) pill.keybindsActivate();
                    e.accepted = true;
                } else if (pill.timerOpen) {
                    if (!e.isAutoRepeat) pill.timerActivate();
                    e.accepted = true;
                } else if (pill.settingsLike) {
                    if (!e.isAutoRepeat) pill.settingsActivate();
                    e.accepted = true;
                } else if (pill.mode === "hover" && !pill.surfaceOpen) {
                    if (!e.isAutoRepeat) pill.faceActivate();
                    e.accepted = true;
                }
            }

            /**
             * Backspace travels through the general onPressed handler above
             * (this build has no named Keys.onBackspacePressed).
             */
            Keys.onReleased: (e) => {
                if (e.isAutoRepeat)
                    return;
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    /** Re-arm the wallpaper hold latch so the next press-hold re-fires the delete hold. */
                    if (pill.wallpaperOpen)
                        pill._wpHoldStarted = false;
                    if (pill.powerOpen) {
                        pill.powerRelease();
                        e.accepted = true;
                    }
                }
            }

            Pill {
                id: pill
                anchors.top: parent.top
                anchors.topMargin: pill.mode === "game" ? 0 : overlay.topGap
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on anchors.topMargin {
                    NumberAnimation {
                        duration: Motion.morph
                        easing.type: Motion.easeMorph
                        easing.bezierCurve: Motion.morphCurve
                    }
                }
                s: overlay.s
                screenName: overlay.modelData.name
                barWindow: overlay
                surface: overlay.surface
                forcePinned: host.peekMon === overlay.modelData.name

                opacity: (overlay.monFullscreen || overlay.autoRetracted) ? 0 : 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: Math.round(Motion.morph * 0.7)
                        easing.type: Easing.OutCubic
                    }
                }
                transform: Translate {
                    y: (overlay.monFullscreen || overlay.autoRetracted) ? -(pill.height + overlay.topGap) : 0
                    Behavior on y {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                }

                onRequestSurface: (name) => host.toggleSurface(overlay.modelData.name, name)
                onRequestClose: host.close()
            }
        }

        onSurfaceOpenChanged: if (surfaceOpen) focusScope.forceActiveFocus()

        Connections {
            target: pill
            function onQuickChoosingChanged() {
                if (pill.quickChoosing)
                    focusScope.forceActiveFocus();
            }
            function onModeChanged() {
                if (pill.mode === "hover" && pill.hovered && !pill.surfaceOpen)
                    focusScope.forceActiveFocus();
            }
            function onWallpaperSearchingChanged() {
                if (!pill.wallpaperSearching && overlay.surfaceOpen)
                    focusScope.forceActiveFocus();
            }
            function onKeybindsListeningChanged() {
                if (!pill.keybindsListening && overlay.surfaceOpen)
                    focusScope.forceActiveFocus();
            }
        }
    }
}

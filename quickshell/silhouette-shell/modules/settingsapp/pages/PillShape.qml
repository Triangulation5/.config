pragma Singleton

import QtQuick

/**
 * Pill shape: the sizes the pill's own surfaces are drawn at, one flag per
 * tunable the shell used to hard-code in `Pill.qml` (see the constants
 * block there — every one of them now reads a flag, and the flag's default
 * is the number it used to be). Derived sizes stay out: `hoverW` comes from
 * the hover row's contents, `mediaW` from whether a second player is
 * available, and `gameW` from the bar window.
 *
 * Widths are per surface rather than one global scale, because the surfaces
 * do different jobs — the launcher wants room to grow, a toast does not. Each
 * value is multiplied, where the pill draws it, by the pill's own `s`, which
 * the host sets to (monitor height / 1080) x uiScale. A number here is therefore
 * logical pixels on a 1080-tall screen at 100% UI scale, and it follows both the
 * screen and the UI scale from there.
 */
QtObject {
    readonly property string name: "Pill shape"
    readonly property string icon: "\u25A2"
    readonly property string keywords: "pill shape size sizes width height geometry box surface launcher mixer osd toast panel picker popover scale"

    readonly property var groups: [
        { card: "Rest bar", rows: [
            { key: "pillRestW", type: "slider", label: "Rest width", min: 80, max: 260, step: 2, unit: "px", reset: 160 },
            { key: "pillRestH", type: "slider", label: "Rest height", min: 24, max: 60, step: 1, unit: "px", reset: 38 },
            { key: "pillRestCorner", type: "slider", label: "Corner radius", min: 0, max: 44, step: 1, unit: "px", reset: 28 },
            { key: "pillNotchCorner", type: "slider", label: "Notch corner radius", min: 0, max: 32, step: 1, unit: "px",
              caption: "Corner radius while the pill is a notch", reset: 18 },
        ] },
        { card: "Hover face", rows: [
            { key: "pillHoverPad", type: "slider", label: "Hover padding", min: 0, max: 44, step: 1, unit: "px", reset: 20 },
            { key: "pillHoverH", type: "slider", label: "Hover height", min: 90, max: 260, step: 2, unit: "px", reset: 172 },
            { key: "pillMixerH", type: "slider", label: "Mixer height", min: 120, max: 320, step: 2, unit: "px", reset: 214 },
        ] },
        { card: "Launcher & panels", rows: [
            { key: "pillLauncherW", type: "slider", label: "Launcher width", min: 220, max: 560, step: 2, unit: "px", reset: 360 },
            { key: "pillLauncherH", type: "slider", label: "Launcher height", min: 220, max: 560, step: 2, unit: "px", reset: 332 },
            { key: "pillClipboardW", type: "slider", label: "Clipboard width", min: 220, max: 560, step: 2, unit: "px", reset: 360 },
            { key: "pillClipboardH", type: "slider", label: "Clipboard height", min: 220, max: 560, step: 2, unit: "px", reset: 332 },
            { key: "pillPowerW", type: "slider", label: "Power menu width", min: 220, max: 520, step: 2, unit: "px", reset: 330 },
            { key: "pillPowerH", type: "slider", label: "Power menu height", min: 90, max: 260, step: 2, unit: "px", reset: 150 },
            { key: "pillBatteryW", type: "slider", label: "Battery width", min: 220, max: 480, step: 2, unit: "px", reset: 316 },
            { key: "pillMediaH", type: "slider", label: "Media height", min: 90, max: 240, step: 2, unit: "px", reset: 150 },
            { key: "pillTimerW", type: "slider", label: "Timer width", min: 220, max: 460, step: 2, unit: "px", reset: 340 },
            { key: "pillTimerH", type: "slider", label: "Timer height", min: 220, max: 600, step: 2, unit: "px", reset: 460 },
            { key: "pillWallpaperW", type: "slider", label: "Wallpaper picker width", min: 420, max: 900, step: 4, unit: "px", reset: 720 },
            { key: "pillWallpaperH", type: "slider", label: "Wallpaper picker height", min: 90, max: 260, step: 2, unit: "px", reset: 172 },
        ] },
        { card: "Settings surfaces", rows: [
            { key: "pillSettingsW", type: "slider", label: "Settings surface width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillKeybindsW", type: "slider", label: "Keybinds width", min: 280, max: 640, step: 2, unit: "px", reset: 460 },
            { key: "pillWorkspacesW", type: "slider", label: "Workspaces width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillStashW", type: "slider", label: "Stash width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillSpaceappsW", type: "slider", label: "Space apps width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillSysmonW", type: "slider", label: "System monitor width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillAppearanceW", type: "slider", label: "Appearance width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillUpdatesW", type: "slider", label: "Updates width", min: 220, max: 520, step: 2, unit: "px", reset: 360 },
            { key: "pillDisplayW", type: "slider", label: "Display width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillInputW", type: "slider", label: "Input width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillLookW", type: "slider", label: "Look width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillIdlelockW", type: "slider", label: "Idle & lock width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillAnimationW", type: "slider", label: "Animation width", min: 240, max: 560, step: 2, unit: "px", reset: 392 },
            { key: "pillRecorderW", type: "slider", label: "Recorder width", min: 220, max: 540, step: 2, unit: "px", reset: 384 },
        ] },
        { card: "Pickers & popovers", rows: [
            { key: "pillFontpickerW", type: "slider", label: "Font picker width", min: 220, max: 520, step: 2, unit: "px", reset: 360 },
            { key: "pillWeatherW", type: "slider", label: "Weather width", min: 260, max: 600, step: 2, unit: "px", reset: 400 },
            { key: "pillPolkitW", type: "slider", label: "Polkit prompt width", min: 280, max: 640, step: 2, unit: "px", reset: 440 },
            { key: "pillOpenCorner", type: "slider", label: "Open corner radius", min: 0, max: 40, step: 1, unit: "px",
              caption: "Corner radius while a surface is open", reset: 22 },
            { key: "pillToastW", type: "slider", label: "Toast width", min: 220, max: 520, step: 2, unit: "px", reset: 342 },
            { key: "pillQuickChooseW", type: "slider", label: "Record chooser width", min: 220, max: 500, step: 2, unit: "px", reset: 344 },
            { key: "pillQuickChooseH", type: "slider", label: "Record chooser height", min: 50, max: 130, step: 1, unit: "px", reset: 76 },
            { key: "pillQuickCountW", type: "slider", label: "Record countdown width", min: 90, max: 240, step: 1, unit: "px", reset: 150 },
            { key: "pillQuickCountH", type: "slider", label: "Record countdown height", min: 40, max: 110, step: 1, unit: "px", reset: 64 },
            { key: "pillDragOverW", type: "slider", label: "Drop overlay width", min: 180, max: 460, step: 2, unit: "px", reset: 300 },
            { key: "pillDragOverH", type: "slider", label: "Drop overlay height", min: 80, max: 220, step: 2, unit: "px", reset: 126 },
            { key: "pillGameH", type: "slider", label: "Game-mode bar height", min: 20, max: 60, step: 1, unit: "px", reset: 34 },
        ] },
        // The lifecycle timers moved to the Timers page, next to the shell's other
        // durations. This page is sizes, and a timeout among forty-eight of them is
        // the one row nobody finds.
    ]
}

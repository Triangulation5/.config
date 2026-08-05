# Planing Forward with This Shell

<!--toc:start-->
- [Planing Forward with This Shell](#planing-forward-with-this-shell)
  - [Creating the Shell's Own Repository](#creating-the-shells-own-repository)
  - [Name Choice](#name-choice)
  - [Launcher](#launcher)
<!--toc:end-->

## Creating the Shell's Own Repository

Try to not add too much `.js` or expand into `.rs`, `.cpp`. This is cause it
adds unneeded complexity, this is a compromise that will cause the shell to be
over 30k+ lines.

## Name Choice

silhouette-shell

Like the notch and dynamic island concepts found in modern devices, here the
interface is not something to hide or work around. A permanent shape that
provides context, information, and interaction.


## Launcher

Bring back the launcher as its separate instance that can be initiated by a
script.

## Moving to a modular Quickshell config

The config lives in `~/.config/quickshell/silhouette-shell/`.

The structure follows a modular Quickshell layout:

- `shell.qml` is the main entry point and only loads modules.
- `modules/` contains user-facing features such as the bar, launcher, lock screen, settings, and control center.
- `components/` contains reusable UI components shared across modules.
- `services/` contains global state and system integrations such as battery, network, audio, and theme.
- `utils/` contains stateless helper functions and JavaScript utilities.
- `assets/` contains static resources such as shaders, images, and configuration files.
- `plugin/` contains optional Quickshell extensions.
- `extras/` contains optional experimental features.

Modules should depend on components and services, but components and services
should remain independent of modules. This keeps the shell easier to extend,
debug, and lazy-load.

Do not switch to C++ or Rust.

```bash
.
├── shell.qml
├── features.md
├── forward.md
│
├── assets/
│   ├── shaders/
│   │   ├── blur.frag
│   │   ├── blur.frag.qsb
│   │   ├── glow.frag
│   │   ├── glow.frag.qsb
│   │   ├── grade.frag
│   │   └── grade.frag.qsb
│   └── cava.conf
│
├── components/
│   ├── Icon.qml
│   ├── GlyphIcon.qml
│   ├── WifiGlyph.qml
│   ├── RoundCorner.qml
│   ├── ScreenCorner.qml
│   ├── Surface.qml
│   ├── Tooltip.qml
│   ├── Marquee.qml
│   ├── ScrubValue.qml
│   ├── HFader.qml
│   ├── VFader.qml
│   ├── WheelScroller.qml
│   ├── Filament.qml
│   ├── AnimationSurface.qml
│   └── qmldir
│
├── modules/
│   │
│   ├── launcher/
│   │   ├── Launcher.qml
│   │   ├── AppRow.qml
│   │   ├── SearchField.qml
│   │   ├── lib/
│   │   │   └── fuzzy.js
│   │   └── qmldir
│   │
│   ├── lock/
│   │   ├── Lock.qml
│   │   ├── Auth.qml
│   │   ├── Content.qml
│   │   ├── Clock.qml
│   │   ├── BatterySurface.qml
│   │   ├── LinkSurface.qml
│   │   ├── LinkToggle.qml
│   │   ├── LinkWifi.qml
│   │   ├── LockSurface.qml
│   │   ├── GlowField.qml
│   │   └── qmldir
│   │
│   ├── bar/
│   │   ├── Bar.qml
│   │   ├── PillSurface.qml
│   │   ├── Battery.qml
│   │   ├── Media.qml
│   │   ├── MusicLine.qml
│   │   ├── MusicBars.qml
│   │   ├── Workspaces.qml
│   │   ├── WorkspacesSurface.qml
│   │   ├── Tray.qml
│   │   ├── MinimizedTray.qml
│   │   ├── Osd.qml
│   │   ├── Toast.qml
│   │   ├── Wallpaper.qml
│   │   └── qmldir
│   │
│   ├── settings/
│   │   ├── Settings.qml
│   │   ├── SettingsSurface.qml
│   │   ├── SettingsRow.qml
│   │   ├── SettingsSeg.qml
│   │   ├── SettingsHeader.qml
│   │   ├── Appearance.qml
│   │   ├── Look.qml
│   │   ├── FontPicker.qml
│   │   └── qmldir
│   │
│   ├── controlcenter/
│   │   ├── Display.qml
│   │   ├── DisplayPicker.qml
│   │   ├── Input.qml
│   │   ├── Keybinds.qml
│   │   ├── Power.qml
│   │   ├── Link.qml
│   │   ├── LinkBt.qml
│   │   ├── LinkWifi.qml
│   │   └── qmldir
│   │
│   └── extras/
│       ├── Clipboard.qml
│       ├── Recorder.qml
│       ├── Calendar.qml
│       ├── Updates.qml
│       ├── SysmonSurface.qml
│       └── qmldir
│
├── services/
│   ├── Theme.qml
│   ├── Battery.qml
│   ├── Backlight.qml
│   ├── Cava.qml
│   ├── Network.qml
│   ├── Audio.qml
│   ├── Players.qml
│   ├── Devices.qml
│   ├── Notifications.qml
│   ├── NightLight.qml
│   ├── ScreenRec.qml
│   ├── Weather.qml
│   ├── Clipboard.qml
│   ├── Workspaces.qml
│   ├── Spaces.qml
│   ├── Dyn.qml
│   ├── Flags.qml
│   ├── Events.qml
│   ├── GameMode.qml
│   ├── Motion.qml
│   ├── Walls.qml
│   ├── Sysmon.qml
│   ├── Pw.qml
│   ├── System.qml
│   ├── Workspacerules.qml
│   └── qmldir
│
├── utils/
│   ├── fuzzy.js
│   ├── binds.js
│   ├── calc.js
│   ├── keychord.js
│   ├── monitors.js
│   ├── setAnim.js
│   ├── setDeco.js
│   └── setInput.js
│
├── plugin/
│
└── extras/
```

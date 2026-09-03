# SilhouetteShell

<!--toc:start-->
- [SilhouetteShell](#silhouetteshell)
  - [Docs](#docs)
  - [Credits](#credits)
<!--toc:end-->

A Qt/QML desktop shell for Hyprland. The core is one pill bar at the top of
the screen. Hover it and it grows a face with the clock, media, tray and
minimized apps. Tap it and it morphs into whatever surface you need: a
calendar, clipboard, mixer, wallpaper picker, recorder, launcher or settings.

The whole shell is hand-written QML. No copied widgets, no web UI. Surfaces
are lazy loaded and killed after they sit idle, so the shell stays light on
RAM and CPU. The static theme is a port of vague.nvim (cool, dark, low
contrast), with an option to pull the palette from the current wallpaper
instead.

---

## Docs

### Setup

- [Dependencies](setup/dependencies.md) — what the shell needs to run

### Architecture

- [Core Shell](architecture/core-shell.md) — the pill, modes, Ame, keyboard nav

### Features

- [Desktop Controls](features/desktop-controls.md) — launcher, AppImage installer, power menu, lockscreen
- [System Integration](features/system-integration.md) — notifications, clipboard, media, tray, mixer
- [Visualizers](features/visualizers.md) — cava bars and the music line
- [Display & Hardware](features/display-hardware.md) — display switcher, OSD, bluetooth, wifi, input
- [Calendar & Time](features/calendar-time.md) — calendar and weather
- [Workspaces](features/workspaces.md) — workspace switcher, stash, space apps
- [Customization](features/customization.md) — theme, wallpaper, icons, motion, corners, game mode
- [Recording](features/recording.md) — screen recorder and quick record
- [System Monitoring](features/system-monitoring.md) — live machine vitals
- [Settings](features/settings.md) — settings menu and persistent config
- [Utilities](features/utilities.md) — calculator, tooltips, keybind system

### Security

- [Authentication](security/authentication.md) — polkit prompts on the pill
- [Face Unlock](security/face-unlock.md) — howdy on the lockscreen

### Troubleshooting

- [Commands](troubleshooting/commands.md) — recording failure fixes

### Development

- [Roadmap](development/roadmap.md) — ideas grouped by difficulty
- [Memory](development/memory.md) — the 200 MB budget, soak tooling, measured numbers

## Credits

This shell is a rebrand of [Ricelin](https://github.com/Gakuseei/Ricelin) by
[Gakuseei](https://github.com/Gakuseei). The pill concept and the original
shell base come from there, so all credit for the base code goes to the
original author. The static theme ports
[vague.nvim](https://github.com/vague-theme/vague.nvim). Screen corners
borrow from [Ambxst](https://github.com/Axenide/Ambxst), some cava ideas
from the [caelestia shell](https://github.com/caelestia-dots/shell), and the
string visualizer from
[flickowoa's dotfiles](https://github.com/flickowoa/dotfiles). See
[CREDITS.md](../CREDITS.md).

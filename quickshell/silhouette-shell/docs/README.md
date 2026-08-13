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

- [Dependencies](dependencies.md)
- [Core Shell](core-shell.md)
- [Desktop Controls](desktop-controls.md)
- [System Integration](system-integration.md)
- [Visualizers](visualizers.md)
- [Display & Hardware](display-hardware.md)
- [Calendar & Time](calendar-time.md)
- [Workspaces](workspaces.md)
- [Customization](customization.md)
- [Recording](recording.md)
- [System Monitoring](system-monitoring.md)
- [Settings](settings.md)
- [Utilities](utilities.md)
- [Troubleshooting](commands.md)
- [Authentication](authentication.md)
- [Face Unlock](face-unlock.md)
- [Roadmap](roadmap.md)

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

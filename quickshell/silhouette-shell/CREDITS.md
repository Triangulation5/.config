# Credits

SilhouetteShell is built on [Ricelin](https://github.com/Gakuseei/Ricelin) by
[Gakuseei](https://github.com/Gakuseei).

The pill concept, a single bar that morphs into whatever surface is needed,
and the original shell base come from there, and this config's scripts started
as Ricelin's custom scripts. All credit for that base goes to the original
author:

- **Author:** [Gakuseei](https://github.com/Gakuseei)
- **Original project:** [Gakuseei/Ricelin](https://github.com/Gakuseei/Ricelin)

What sits in `quickshell/silhouette-shell` now is that base with a lot of local
work on it: reworked modules, a settings app and IPC surface of its own, extra
surfaces, and scripts pulled apart and rebuilt. The design language (pill, washi
material) is kept. The static theme is a port of vague.nvim, replacing the warm
vermilion theme Ricelin shipped.

Not all of it traces to Ricelin. One part came from
[Ukishima](https://github.com/amanhex/ukishima) by
[amanhex](https://github.com/amanhex), itself a Ricelin-derived Quickshell
shell: the system monitor's on-demand speed test, the Cloudflare ping, download
and upload card in `modules/pill/surfaces/SysmonSurface.qml`, was inspired by
its version of that. The two shells share a base, so plenty of animation and
control components look alike across them without either having taken the
other's.

Not everything here is hand-written. Parts of the shell and the scripts were
written with AI assistance, and several features take code or ideas from the
projects below.

## Inspirations

Specific features drew on other projects:

- [vague.nvim](https://github.com/vague-theme/vague.nvim) by the vague-theme org. The static color theme is a direct port of its palette.

- [Ambxst](https://github.com/Axenide/Ambxst) by
  [Axenide](https://github.com/Axenide). The rounded screen corners and related
  decorations.
- [caelestia shell](https://github.com/caelestia-dots/shell) by the
  caelestia-dots org. Some of the cava audio-visualizer ideas.
- [flickowoa dotfiles](https://github.com/flickowoa/dotfiles) by
  [flickowoa](https://github.com/flickowoa). The flowing string music
  visualizer.
- [howdy](https://github.com/boltgolt/howdy) by
  [boltgolt](https://github.com/boltgolt). Face unlock on the lockscreen.

- [ChillPill-Shell](https://github.com/LUCKYS1NGHH/ChillPill-Shell) by
  [LUCKYS1NGHH](https://github.com/LUCKYS1NGHH). A pill bar aimed at machines
  with no discrete GPU, and the source of this shell's performance pass:

  - **Lite mode** (`liteMode`) — one flag that drops the expensive GPU layers
    instead of leaving them always on: the now-playing bleed blur
    (`modules/pill/widgets/media/Media.qml`), the ambient aura blur
    (`modules/pill/Pill.qml`), the Ame bead's bloom
    (`modules/pill/widgets/ame/AmeBody.qml`), the surface closing blur
    (`modules/pill/surfaces/PillSurface.qml`), the lock backdrop's six blur
    passes (`modules/lock/BlurredShot.qml`) and the lock audio glow
    (`components/effects/GlowField.qml`). Their shell simply has no blur,
    shader or canvas layers at all; this is the version that keeps the look
    and lets the layers be turned off.
  - **Fullscreen from the foreign-toplevel protocol** rather than by shelling
    out to `hyprctl` (`services/Fullscreen.qml`) — their
    `ToplevelManager.activeToplevel.fullscreen` is the whole idea.
  - **Precomputed derived lists** instead of rebuilding them inside bindings
    (`services/Notifs.qml`: the grouped notification tree).
  - **Collapsing duplicate notifications** (`notifDedupe`) and the
    **notification sound** (`notifSound`).
  - **A volume ceiling past unity** (`maxVolume`), which the mixer's fader
    and the OSD both read.

  Their config file is also the reference for a handful of small switches
  worth having. The work here is a reimplementation of the ideas, not a copy
  of their code — ChillPill-Shell is GPL-3.0, so none of its source was taken.

Vendored third-party work lives with the config that uses it, such as the yazi
flavors and plugins in `yazi/flavors/` and `yazi/plugins/`.

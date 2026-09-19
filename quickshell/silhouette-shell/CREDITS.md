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

Vendored third-party work lives with the config that uses it, such as the yazi
flavors and plugins in `yazi/flavors/` and `yazi/plugins/`.

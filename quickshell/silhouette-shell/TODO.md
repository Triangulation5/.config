# Project TODO

## Current continuation

- [x] Restore the previous power-menu close timing and behavior.
- [x] Keep Material palette behavior across the shell; only lockscreen color
  tokens use the Washi palette equivalents.
- [x] Match the notch-ear outlines to the pill border and screen-corner fills
  to the pill surface.
- [x] Persist desktop-widget geometry and custom settings in local `flags.json`,
  including edits made before the file finishes loading; verified across reloads.
- [x] Load all desktop-widget QML types without shell QML errors and remove
  temporary validation files.
- [x] Review changed paths and the live shell reload; no new QML errors. Two
  existing `ShaderEffect` source warnings remain in unchanged effect components.
- [ ] Commit and push the requested shell and attribution changes, excluding
  unrelated worktree edits.

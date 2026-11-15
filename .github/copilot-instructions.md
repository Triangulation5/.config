# Copilot instructions for this repository

This repo is a personal dotfiles configuration for a Hyprland desktop, not a
conventional application project. The important runtime is the Quickshell shell
under `quickshell/silhouette-shell`; the rest of the tree is configuration for
Hyprland, GTK, terminals, editors, and helper scripts.

## Build, test, and lint

There is no package.json, Cargo.toml, pytest setup, or app build pipeline in
this repo. The main automated validation is the shell’s QML lint.

- Run the repo’s lint check from the repo root:
  - `cd /home/josh/.config && python3
    quickshell/silhouette-shell/utils/lint_qml.py`
- Run a single file through the same linter:
  - `cd /home/josh/.config && python3
    quickshell/silhouette-shell/utils/lint_qml.py
    quickshell/silhouette-shell/modules/pill/surfaces/Foo.qml`
- Audit a file more aggressively (reports more non-literal `text:` bindings):
  - `cd /home/josh/.config && python3
    quickshell/silhouette-shell/utils/lint_qml.py --all
    quickshell/silhouette-shell/modules/.../Foo.qml`

For runtime validation in a live session:

- Start the shell: `~/.config/scripts/launch.sh`
- Reload the shell: `~/.config/scripts/reload.sh`

`launch.sh` adds the jemalloc tuning and performs once-only state migration
before launching Quickshell; `reload.sh` restarts the shell through the
watchdog flow instead of launching a duplicate instance.

## High-level architecture

- `hypr/` contains the compositor configuration (binds, autostart, monitors,
  rules, style, etc.).
- `scripts/` contains the shell lifecycle scripts (`launch.sh`, `reload.sh`,
  migration and watchdog logic) and other desktop helper tooling.
- `quickshell/silhouette-shell/` is the actual desktop shell code. The entry
  point is `shell.qml`, which composes the shell and keeps each top-level
  surface self-contained.
- `modules/` is the UI layer: `pill`, `bar`, `lock`, `launcher`, `settingsapp`,
  desktop widgets, recorder, screen corner, and reload surfaces. Each module
  owns its own routing and IPC surface.
- `components/` contains shared QML widgets used across surfaces.
- `utils/` contains helper scripts such as the QML linter, memory soak, and
  backup/restore utilities.
- `assets/` is visual content; `services/` and `settingsapp/config` hold shell
  state, theme, motion, and config tokens.

The important design pattern is that the shell is a composition root rather
than a monolithic UI: `shell.qml` wires the modules together and should stay
minimal; surface-specific behavior belongs in the relevant module.

## Key conventions and repo-specific rules

- QML and JS comments must be doc comments (`/** ... */`). Plain `//` comments
  and plain `/* ... */` blocks are not the repo style. This is enforced by
  `utils/lint_qml.py`.
- Reasoning lives next to the code. Header comments explain what a file is for
  and any non-obvious design decision; this repository intentionally avoids a
  separate docs tree.
- The shell is stateful and flag-driven. Values that the settings app can edit
  live in the shell’s flag/state layer rather than being scattered as local
  constants.
- Do not add raw hex colors outside the theme layer. The design docs explicitly
  treat `ColorScheme.qml` and `Theme.qml` as the only approved homes for
  hard-coded hex values.
- The shell’s visual language is token-based: colors, durations, sizes, and
  motion should come from the theme/motion system instead of ad hoc literals.
- Keep the active presentation to one top-level mode at a time
  (pillar/bar/lock/launcher). The repo’s design rules reject duplicating
  surface state or making unrelated modules know too much about each other.
- This project is sensitive to shell lifecycle and state migration. Changes
  that affect the shell startup, reload behavior, or config storage should be
  checked against the `launch.sh`/`reload.sh`/state-migration flow, because the
  shell reads and writes session state across restarts.

## Repository-specific working style

- Prefer edits in the relevant subsystem rather than broad, cross-cutting
  cleanup.
- Treat UI behavior as part of the shell’s runtime contract; if a change
  touches a binding, state flag, or IPC surface, verify the shell still remains
  responsive and reloading still works.
- When a change is likely to affect the shell UI, use the QML linter as the
  first validation step before broader visual or session testing.

## Useful starting points for a new session

- `quickshell/silhouette-shell/shell.qml` for the composition root
- `quickshell/silhouette-shell/DESIGN.md` for the design system and non-obvious
  conventions
- `quickshell/silhouette-shell/README.md` for runtime/tooling context and known
  failure modes
- `scripts/launch.sh` and `scripts/reload.sh` for lifecycle and restart
  behavior
- `hypr/modules/binds.lua` for the keybinds and reload entry points

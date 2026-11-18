# Agent instructions

This repository is a personal Hyprland and Quickshell dotfiles configuration.
Read `.github/copilot-instructions.md` for the detailed architecture, QML
conventions, validation commands, and lifecycle requirements before making
changes.

- Keep changes focused on the relevant subsystem and preserve unrelated work.
- For Quickshell changes, keep `shell.qml` as a composition root and put
  surface-specific behavior in its owning module or service.
- Preserve shell fallbacks when adding optional Rust tools; honor the
  `useRustTools` setting and do not make Rust a runtime requirement.
- Avoid committing generated binaries, Cargo `target` directories, local state,
  or credentials.
- Run the narrowest applicable check. For shell UI changes, start with the QML
  linter; for Rust tools, run Cargo formatting, tests, and a release build.
- Do not commit unless the user asks.

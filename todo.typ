- Add a migration docuement from Fedora -> Gentoo (something I am thinking about).
- Save wireguard, and vpm configurations before switching over.

- Test out installer using Gentoo on vm-curator.

- Very far future: Rewrite entire shell in Rust, get it below 100 MB, and distribute as binary.
- Optimize and hunt pests inside the shell.
- Symlink files to automatically update configs. Think about using GNU stow (and saving more than just ~/.config).

- Create custom build of st (simple terminal), kitty takes up too much memory.
- Create repository for st and make it a part of the installer script, ask user to chose between st (default), kitty, or ghostty

- Confirm package names for emerge in installer.
- Fix flashing progress bar in installer (make it more like a background task thing).
- Yazi lives in copr repo... Fix that for Fedora.

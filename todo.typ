- Add a migration docuement from Fedora -> Gentoo (something I am thinking
  about).
- Symlink files to automatically update configs. Think about using GNU stow
  (and saving more than just ~/.config).

- Create custom build of st (simple terminal), kitty takes up too much memory.
- Create repository for st and make it a part of the installer script, ask user
  to chose between st (default), kitty, or ghostty

- Get fonts like JetBrainsMono, Iosevka, FiraCode, SF Pro, and Rubik fonts
  installer. (Let them chose between 1, 2, 3, etc or 1-5, all).
- Get the Papirus-Dark icon pack, GTK settings and those stuff (only what is needed not bloat).
- xdg-desktop-portal-hyprland and other xdg-desktop-portal-*.* ones that are required by this.


- Have two major themeing styles Vague theme (default), and Flexoki theme (just
- Make installer better for Alpine, and Arch/Artix linux.
  the dark theme, secondary)
- Make it so that the shell fades the screen corners when on fullscreen
  windows.
- Dotfiles turning into desktop...

- Save wireguard, and vpn configurations before switching over.

- Prompt pi agent harness setup script, to ask what ollama models you want, and add setup/install script for ollama.
- Models you are prompted for:
- Smaller (testing, subagents, etc):
  qwen3:1.7b
  qwen3:4b (recommended, fast)
  qwen3.5:2b
  qwen3.5:4b
  gemma4:e4b
  gemma4:e2b
  ministral-3:3b
  nemotron-3-nano:4b
  deepseek-r1:7b

- Larger (reasonable sized agents):
  gpt-oss:20b (recommended)
  glm-4.7-flash
  qwen3:30b-a3b
  qwen3.6:27b-q4_K_M
  qwen3.6:35b-a3b

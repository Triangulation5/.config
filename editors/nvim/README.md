# Neovim v0.12.0 Configuration
## This configuration only works in Neovim v0.12.0+
## NVIM v0.12.0-dev-1215+ga897cc17a5

This is a high-performance, minimal, and extensible Neovim Nightly configuration designed around fast startup, sane defaults, and modern plugin architecture. Built for Neovim 0.12+.

---

## Configuration Screenshots

### MiniFiles Explorer
![MiniFiles](screenshots/configuration0.png)

### blink.cmp Autocomplete
![blink.cmp](screenshots/configuration1.png)

### MiniPick File Picker
![MiniPick](screenshots/configuration2.png)

### Diagnostics & LSP Info
![Diagnostics](screenshots/configuration3.png)

---

## Features

- ⚡ Fast startup using `vim.pack.add()`
- 🧼 Clean UI with custom `fillchars`, `guicursor`, and `winblend`
- ⌨️ Keymap-driven workflow with no-yank deletes, quick buffer cycling, Harpoon nav, and LSP integration
- 🛠️ Language support for Python, Go, and more via native LSP
- 🧩 Minimal plugin set using:
  - `mini.nvim` suite
  - `oil.nvim`
  - `mason.nvim`
  - Picker interface via `Telescope`
- 🎨 Nice colorscheme (`vague`)
- 🧠 Smart formatting dispatch per filetype (`ruff`, `gofmt`, etc.)
  - Built-in support for Python, Go, Rust, Typst, and Markdown files.

---

## Requirements

- [Neovim Nightly](https://neovim.io/download/nightly) (v0.11+)
- `git` for plugin installation via `vim.pack.add()`
- Optional language-specific tools (Mason is intentionally left empty so you can configure your own):
  - Python: `ruff`
  - Go: `gofmt`
  - Rust: `rust-analyzer`, `cargo`
  - Typst: `tinymist`, `typst`
  - Shell/git tools: `lazygit`, `yazi`

## Getting Started

1. Install [Neovim Nightly](https://neovim.io/download/nightly).
2. Clone this configuration:
   ```bash
   git clone https://github.com/Triangulation5/sleepyvim ~/.config/nvim
   ```
---

## Plugin Architecture

Managed via [`vim.pack.add`](https://neovim.io/doc/user/repeat.html#vim.pack):

- [`neovim/nvim-lspconfig`](https://github.com/neovim/nvim-lspconfig)
- [`mason-org/mason.nvim`](https://github.com/williamboman/mason.nvim)
- [`stevearc/oil.nvim`](https://github.com/stevearc/oil.nvim)
- [`echasnovski/mini.nvim`](https://github.com/echasnovski/mini.nvim)
- [`vague2k/vague.nvim`](https://github.com/vague2k/vague.nvim)
- [`rose-pine/neovim`](https://github.com/rose-pine/neovim)
- [`folke/tokyonight`](https://github.com/folke/tokyonight.nvim)
- [`Saghen/blink.cmp`](https://github.com/Saghen/blink.cmp)
- [`nvim-lua/plenary.nvim`](https://github.com/nvim-lua/plenary.nvim)

---

## Key Bindings

### General
| Key                  | Action                               |
|----------------------|--------------------------------------|
| `<leader>w`          | Trim trailing space + save           |
| `<leader>q`          | Quit                                 |
| `<leader>b[n/p/d/f]` | Buffer next/prev/delete/delete force |
| `<leader>cm`         | Open Mason                           |
| `<C-p>`              | Open PowerShell terminal             |
| `<leader>gg`         | Open LazyGit terminal                |

### File Navigation
| Key              | Action                |
|------------------|-----------------------|
| `<leader>f`      | Pick files            |
| `<leader>fb`     | Pick buffers          |
| `<leader>fg`     | Pick grep_live        |
| `<leader>fc`     | Pick colorschemes     |
| `<leader>fw`     | Pick word             |
| `<leader>h`      | Pick help             |
| `<leader>e`      | Open Oil              |
| `<leader>ef`     | Open MiniFiles        |

### LSP
| Key              | Action                     |
|------------------|----------------------------|
| `<leader>lf`     | Format via LSP             |
| `<leader>ca`     | Format + clean (Go/Python) |

### UI
| Key              | Action                     |
|------------------|----------------------------|
| `<leader>t`      | Cycle color schemes        |
| `<leader>tt`     | Toggle transparency        |
| `<leader>ta`     | Enable cursor animations   |
| `<leader>wz`     | Zoom current window        |

### Editing Behavior
| Key              | Action                              |
|------------------|-------------------------------------|
| `d/c/x`          | Mapped to blackhole register (`"_`) |
| Visual `d/c`     | Same as above                       |

---

## Language Support

Configured LSPs:

- **Lua** (`lua_ls`)
- **Python** (`pyright`, `ruff`)
- **Go** (`gopls` with staticcheck and param analysis)
- **Rust** (`rust_analyzer`)

Custom `LspAttach` handler enables completion autotriggering. (Could optionally use blink.cmp).

---

## UI & Colors

Themes supported:

- `rose-pine`
- `vague` (with custom statusline)

---

## Notes

- Filetype-specific formatters are dispatched using `jobstart`, with auto-reload.
- Assumes Lazygit is installed.
- No telescope, cmp, lualine, or treesitter used — intentional minimalism via `mini.nvim`.

---

## License

MIT

vim.pack.add({
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/stevearc/oil.nvim" },
    { src = "https://github.com/echasnovski/mini.nvim" },
    { src = "https://github.com/vague-theme/vague.nvim" }, -- version = "24cd29d"
    { src = "https://github.com/chomosuke/typst-preview.nvim" },
})

-- Eager: these are cheap and/or used immediately (pick, colorscheme, mason UI)
require("plugins.mini")
require("plugins.mason")
require("plugins.colorscheme")

-- Lazy: only registers the trigger (autocmd/keymap) here; the actual
-- plugin setup is deferred via util.lazy until first use.
require("plugins.typst-preview").setup()
-- plugins.oil is intentionally NOT required here — it's pulled in by
-- config.keymaps, which is the only thing that ever needs it.

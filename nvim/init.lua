vim.cmd([[set mouse=]])
if vim.loader then vim.loader.enable() end; vim.g.mapleader = " "; local opt = vim.opt for k, v in pairs({ nu = true, rnu = true,
    scl = "yes",
    ts = 4, sts = 4, sw = 4, et = true,
    si = true, bri = true, stal = 2,
    ic = true, scs = true, hls = false,
     ut = 50, tm = 250, gcr = "a:block",
    so = 8, siso = 8,
    winborder = "rounded", cb = "unnamedplus",
    cot = { "menuone", "noselect" },
    ph = 10, swf = false,
    title = true, titlestring = "nvim", titlelen = 0,
}) do opt[k] = v end

for _, m in ipairs({
    { "n", "<leader>w", ":write<CR>", "Trim & Save" }, { "n", "<leader>q", ":quit<CR>", "Quit" }, { "n", "<leader>wq", ":xa<CR>", "Save & Quit" },
    { "n", "<leader>f", ":Pick files<CR>", "Pick: Files" },
    { "n", "<leader>fg", ":Pick grep_live<CR>", "Pick: Grep" },
    { "n", "<leader>h", ":Pick help<CR>", "Pick: Help" },
    { { "n", "v", "x" }, "<leader>n", ":norm ", "Enter Norm Commmand" },
    { "n", "<leader>e", function() oil().open() end, "Oil: Explorer" },
    { "n", "<leader>lf", function() require("mini.trailspace").trim(); require("mini.trailspace").trim_last_lines(); vim.lsp.buf.format() end, "LSP: Format" }, { "n", "<leader>i", [[<Cmd>tabedit .gitignore<CR>]], "Edit .gitignore" }, { "n", "<leader>p", ":TypstPreview<CR>", "Preview Typst File" },
    { "n", "<leader>bf", ":bd!<CR>", "Force Delete Buffer" }, { "n", "<leader>tf", ":tabc<CR>", "Close Tab" },
    { "n", "<leader>da", function() vim.diagnostic.setqflist({ open = true, title = "Diagnostics"}) end, "Show Diagnostics in Quickfix"}, { "n", "<C-q>", ":copen<CR>", "Opens Quickfix"},
    { "n", "<M-t>", function() vim.cmd('botright split term://bash') end, "Bash" },
}) do vim.keymap.set(m[1], m[2], m[3], { desc = m[4] }) end

vim.pack.add({
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/stevearc/oil.nvim" },
    { src = "https://github.com/echasnovski/mini.nvim" },
    { src = "https://github.com/vague-theme/vague.nvim", version = "24cd29d" },
    { src = "https://github.com/chomosuke/typst-preview.nvim" },
})

vim.opt.undofile = true; local u = vim.fn.stdpath("state") .. "/undo"; vim.opt.undodir = u; vim.fn.mkdir(u, "p"); local t = u .. "/.last_cleanup"; local n = os.time(); local l = vim.fn.filereadable(t) == 1 and tonumber(vim.fn.readfile(t)[1]) or 0; if n - l > 86400 then for _,f in ipairs(vim.fn.glob(u.."/*",true,true)) do local s=vim.uv.fs_stat(f); if f~=t and s and n-s.mtime.sec>60*86400 then os.remove(f) end end; vim.fn.writefile({tostring(n)},t) end

for _,m in ipairs({"ai","diff","git","icons","move","pairs","pick","surround"}) do require("mini."..m).setup() end
MiniIcons.tweak_lsp_kind(); MiniIcons.mock_nvim_web_devicons()
local lt_opts = { action = 'open', pair = '<>', neigh_pattern = '\r.', register = { cr = false }, }; MiniPairs.map('i', '<', lt_opts); local gt_opts = { action = 'close', pair = '<>', register = { cr = false } }; MiniPairs.map('i', '>', gt_opts); local map_typ = function() MiniPairs.map_buf(0, 'i', '$', { action = 'closeopen', pair = '$$' }) end; vim.api.nvim_create_autocmd( 'FileType', { pattern = 'typst', callback = map_typ })

require("mason").setup(); oil_loaded, oil = false, function() if oil_loaded then return require("oil") end require("oil").setup({ view_options = { show_hidden = true } }) oil_loaded = true return require("oil") end

require("vague").setup(); vim.cmd.colorscheme("vague")

vim.api.nvim_create_autocmd("LspAttach", { callback = function(ev) local client = vim.lsp.get_client_by_id(ev.data.client_id); if client then vim.api.nvim_buf_set_option(ev.buf, "omnifunc", "v:lua.vim.lsp.omnifunc"); if client:supports_method("textDocument/completion") then vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true }) end end end })
vim.lsp.enable({ "pyright", "ruff", "marksman", "vtsls", "tinymist" })
vim.lsp.config("gopls", { settings = { gopls = { completeUnimported = true, usePlaceholders = true, analyses = { unusedparams = true, shadow = true }, staticcheck = true } } }); vim.lsp.config("vtsls", { root_dir = vim.fs.root(0, { "jsconfig.json", "package.json", "tsconfig.json" }) }); vim.lsp.config("tinymist", { settings = { formatterMode = "typstyle", exportPdf = "never" } }); vim.diagnostic.config({ virtual_text = { prefix = "■", spacing = 6, hl_mode = "combine", format = function(d) return string.format("%s [%s]", d.message, d.source or d.code or "") end }, signs = true, underline = true, update_in_insert = false, severity_sort = true, float = { border = "rounded", header = "Diagnostic(s):", source = "always", focusable = true } }); local typst_loaded = false; vim.api.nvim_create_autocmd("FileType", { pattern = "typst", callback = function() if typst_loaded then return end typst_loaded = true vim.schedule(function() vim.cmd.packadd("typst-preview.nvim") local ok, typst = pcall(require, "typst-preview") if not ok then vim.notify("typst-preview failed to load") return end typst.setup({}) vim.notify("typst-preview initialized") end) end, })

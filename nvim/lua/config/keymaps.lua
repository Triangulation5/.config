local oil = require("plugins.oil")

local keymaps = {
    { "n", "<leader>w", ":write<CR>", "Trim & Save" },
    { "n", "<leader>q", ":quit<CR>", "Quit" },
    { "n", "<leader>wq", ":xa<CR>", "Save & Quit" },
    { "n", "<leader>f", ":Pick files<CR>", "Pick: Files" },
    { "n", "<leader>fg", ":Pick grep_live<CR>", "Pick: Grep" },
    { "n", "<leader>h", ":Pick help<CR>", "Pick: Help" },
    { { "n", "v", "x" }, "<leader>n", ":norm ", "Enter Norm Command" },
    { "n", "<leader>e", oil.open, "Oil: Explorer" },
    {
        "n",
        "<leader>lf",
        function()
            require("mini.trailspace").trim()
            require("mini.trailspace").trim_last_lines()
            vim.lsp.buf.format()
        end,
        "LSP: Format",
    },
    { "n", "<leader>i", [[<Cmd>tabedit .gitignore<CR>]], "Edit .gitignore" },
    { "n", "<leader>p", ":TypstPreview<CR>", "Preview Typst File" },
    { "n", "<leader>P", ":LspTinymistExportPdf<CR>", "Export Typst to PDF" },
    { "n", "<leader>bf", ":bd!<CR>", "Force Delete Buffer" },
    { "n", "<leader>tf", ":tabc<CR>", "Close Tab" },
    {
        "n",
        "<leader>da",
        function()
            vim.diagnostic.setqflist({ open = true, title = "Diagnostics" })
        end,
        "Show Diagnostics in Quickfix",
    },
    { "n", "<C-q>", ":copen<CR>", "Opens Quickfix" },
    {
        "n",
        "<M-m>",
        function()
            vim.cmd("botright split term://zsh")
        end,
        "Zoomer Shell",
    },
}

for _, m in ipairs(keymaps) do
    vim.keymap.set(m[1], m[2], m[3], { desc = m[4] })
end

for _, module in ipairs({ "ai", "diff", "git", "move", "pairs", "pick", "surround" }) do
    require("mini." .. module).setup()
end

-- MiniIcons.tweak_lsp_kind()
-- MiniIcons.mock_nvim_web_devicons()

-- Treat <> as a pair, but only greedily open next to non-whitespace
MiniPairs.map("i", "<", {
    action = "open",
    pair = "<>",
    neigh_pattern = "\r.",
    register = { cr = false },
})
MiniPairs.map("i", ">", {
    action = "close",
    pair = "<>",
    register = { cr = false },
})

-- Typst math mode: treat $...$ as a pair too
vim.api.nvim_create_autocmd("FileType", {
    pattern = "typst",
    callback = function()
        MiniPairs.map_buf(0, "i", "$", { action = "closeopen", pair = "$$" })
    end,
})

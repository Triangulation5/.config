local lazy = require("util.lazy")

local plugin = lazy.once(function()
    vim.cmd.packadd("typst-preview.nvim")
    local ok, typst = pcall(require, "typst-preview")
    if not ok then
        vim.notify("typst-preview failed to load")
        return
    end
    typst.setup({})
    vim.notify("typst-preview initialized")
end)

local M = {}

--- Registers the autocmd trigger. The plugin itself only loads the
--- first time a typst buffer is opened.
function M.setup()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "typst",
        callback = function()
            vim.schedule(plugin.load)
        end,
    })
end

return M

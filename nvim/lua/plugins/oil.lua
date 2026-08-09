local lazy = require("util.lazy")

local plugin = lazy.once(function()
    require("oil").setup({ view_options = { show_hidden = true } })
end)

local M = {}

function M.open()
    plugin.load()
    require("oil").open()
end

return M

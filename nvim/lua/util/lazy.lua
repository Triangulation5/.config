-- Minimal helper for "configure a plugin only when it's first needed".
-- Any plugin that shouldn't pay its setup cost at startup (oil.nvim,
-- typst-preview.nvim, ...) wraps its setup in M.once() and calls
-- `plugin.load()` from whatever keymap/autocmd first needs it.
local M = {}

---@param setup fun() # runs the plugin's setup/packadd the first time load() fires
---@return { load: fun() }
function M.once(setup)
    local done = false
    return {
        load = function()
            if done then
                return
            end
            done = true
            setup()
        end,
    }
end

return M

if vim.loader then
    vim.loader.enable()
end

require("config.options")
require("plugins")
require("lsp")
require("config.keymaps")

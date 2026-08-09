-- Per-server configs (only servers with custom settings need a file;
-- pyright/ruff/marksman use defaults and are just named below).
require("lsp.rust_analyzer")
require("lsp.vtsls")
require("lsp.tinymist")

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if not client then
            return
        end

        vim.api.nvim_buf_set_option(ev.buf, "omnifunc", "v:lua.vim.lsp.omnifunc")
        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
        end
    end,
})

vim.diagnostic.config({
    virtual_text = {
        prefix = "■",
        spacing = 6,
        hl_mode = "combine",
        format = function(d)
            return string.format("%s [%s]", d.message, d.source or d.code or "")
        end,
    },
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = {
        border = "rounded",
        header = "Diagnostic(s):",
        source = "always",
        focusable = true,
    },
})

vim.lsp.enable({ "pyright", "ruff", "marksman", "vtsls", "tinymist", "rust_analyzer" })

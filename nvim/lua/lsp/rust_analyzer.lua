vim.lsp.config("rust_analyzer", {
    capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
        textDocument = {
            completion = {
                completionItem = {
                    snippetSupport = true,
                    resolveSupport = {
                        properties = { "documentation", "detail", "additionalTextEdits" },
                    },
                },
            },
        },
    }),
    settings = {
        ["rust-analyzer"] = {
            cargo = { allFeatures = true },
            checkOnSave = true,
            procMacro = { enable = true },
            lens = { enable = true },
        },
    },
})

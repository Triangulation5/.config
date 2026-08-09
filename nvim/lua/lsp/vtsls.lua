vim.lsp.config("vtsls", {
    root_dir = vim.fs.root(0, { "jsconfig.json", "package.json", "tsconfig.json" }),
})

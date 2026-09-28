vim.cmd([[set mouse=]])

vim.g.mapleader = " "

local opt = vim.opt
for k, v in pairs({
    number = true, relativenumber = true,
    signcolumn = "yes",
    tabstop = 4, softtabstop = 4, shiftwidth = 4, expandtab = true,
    smartindent = true, breakindent = true, showtabline = 1,
    ignorecase = true, smartcase = true, hlsearch = false,
    updatetime = 50, timeoutlen = 250, guicursor = "a:block",
    scrolloff = 8, sidescrolloff = 8,
    winborder = "rounded", clipboard = "unnamedplus",
    completeopt = { "menuone", "noselect" },
    pumheight = 10, swapfile = false,
}) do
    opt[k] = v
end

-- Undo files, with a lazy daily sweep of anything untouched for 60+ days
opt.undofile = true
local undodir = vim.fn.stdpath("state") .. "/undo"
opt.undodir = undodir
vim.fn.mkdir(undodir, "p")

local cleanup_marker = undodir .. "/.last_cleanup"
local now = os.time()
local last_cleanup = vim.fn.filereadable(cleanup_marker) == 1
    and tonumber(vim.fn.readfile(cleanup_marker)[1])
    or 0

if now - last_cleanup > 86400 then
    for _, file in ipairs(vim.fn.glob(undodir .. "/*", true, true)) do
        local stat = vim.uv.fs_stat(file)
        if file ~= cleanup_marker and stat and now - stat.mtime.sec > 60 * 86400 then
            os.remove(file)
        end
    end
    vim.fn.writefile({ tostring(now) }, cleanup_marker)
end

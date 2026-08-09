vim.cmd([[set mouse=]])

vim.g.mapleader = " "

local opt = vim.opt
for k, v in pairs({
    nu = true, rnu = true,
    scl = "yes",
    ts = 4, sts = 4, sw = 4, et = true,
    si = true, bri = true, stal = 2,
    ic = true, scs = true, hls = false,
    ut = 50, tm = 250, gcr = "a:block",
    so = 8, siso = 8,
    winborder = "rounded", cb = "unnamedplus",
    cot = { "menuone", "noselect" },
    ph = 10, swf = false,
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

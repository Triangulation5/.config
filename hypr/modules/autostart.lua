-- https://wiki.hypr.land/Configuring/Basics/Autostart/
--
-- Session autostart adapts automatically to whether a Rust toolchain
-- (`cargo` / `rustc`) is installed and `useRustTools` is enabled in
-- `~/.local/state/silhouette/flags.json`:
--   - Rust installed: ensures `~/.cargo/bin` is on PATH, builds any missing or
--     outdated Rust binaries (`silhouette-tools`, `silhouette_watchers`,
--     `sysmon_sampler`, `framepump`) in the background, and dispatches the
--     native Rust rewrites (`session-start`, `awww-daemon`, `cliphist-watch`,
--     `watchdog`, `polkit-agent`, `privacy-watch`, `sysmon`, `watchers`, etc.)
--     with automatic fallback to the Bash/POSIX and Python scripts while a
--     first-boot build is still compiling.
--   - Rust absent (or disabled): exports `SILHOUETTE_NO_NATIVE=1`,
--     `SILHOUETTE_FORCE_SHELL=1`, and `SILHOUETTE_FORCE_PYTHON=1` so Hyprland,
--     helper scripts, and Quickshell cleanly run the Bash/POSIX and Python
--     scripts (`session-start.sh`, `awww-daemon-wrapper.sh`,
--     `cliphist-watch.sh`, `watchdog-fallback.sh`, `agent.py`, `sampler.py`,
--     `wallcolors.py`, `portal_capture.py`, etc.).

local home        = os.getenv("HOME") or ""
local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local state_home  = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local cargo_bin   = (os.getenv("CARGO_HOME") or (home .. "/.cargo")) .. "/bin"
local scripts_dir = config_home .. "/scripts"
local rust_bin    = scripts_dir .. "/bin/silhouette-tools"

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function has_rust_toolchain()
  if file_exists(cargo_bin .. "/cargo") or file_exists(cargo_bin .. "/rustc") then
    return true
  end
  local path_env = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
  for dir in string.gmatch(path_env, "[^:]+") do
    if dir ~= "" and (file_exists(dir .. "/cargo") or file_exists(dir .. "/rustc")) then
      return true
    end
  end
  return false
end

local function rust_pref_enabled()
  if os.getenv("SILHOUETTE_NO_NATIVE") == "1"
    or os.getenv("SILHOUETTE_FORCE_SHELL") == "1"
    or os.getenv("SILHOUETTE_FORCE_PYTHON") == "1" then
    return false
  end
  local f = io.open(state_home .. "/silhouette/flags.json", "r")
  if not f then
    return true
  end
  local content = f:read("*a") or ""
  f:close()
  if content:match('"useRustTools"%s*:%s*false')
    or content:match('"rustWallpapers"%s*:%s*false') then
    return false
  end
  return true
end

if has_rust_toolchain() then
  local current_path = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
  if (file_exists(cargo_bin .. "/cargo") or file_exists(cargo_bin .. "/rustc"))
    and not (":" .. current_path .. ":"):find(":" .. cargo_bin .. ":", 1, true) then
    hl.env("PATH", cargo_bin .. ":" .. current_path)
  end
else
  hl.env("SILHOUETTE_NO_NATIVE", "1")
  hl.env("SILHOUETTE_FORCE_SHELL", "1")
  hl.env("SILHOUETTE_FORCE_PYTHON", "1")
end

-- cliphist-watch starts the `wl-paste --watch cliphist store` listeners that
-- actually populate the clipboard db. The shell's own wl-paste watcher only
-- fires a change signal so the clipboard surface can refresh, so without this
-- the db is never created: `cliphist list` exits 1 and the surface comes up
-- blank. Guarded by /proc / pgrep checks, so it is safe on a config reload.
hl.on("hyprland.start", function ()
  if has_rust_toolchain() and rust_pref_enabled() then
    hl.exec_cmd("bash " .. scripts_dir .. "/build-rust-tools.sh --ensure")
    if file_exists(rust_bin) then
      hl.exec_cmd(rust_bin .. " session-start || bash " .. scripts_dir .. "/session-start.sh")
      hl.exec_cmd(rust_bin .. " awww-daemon start || bash " .. scripts_dir .. "/awww-daemon-wrapper.sh start")
      hl.exec_cmd(rust_bin .. " cliphist-watch || bash " .. scripts_dir .. "/cliphist-watch.sh")
      hl.exec_cmd(rust_bin .. " watchdog silhouette-shell --scripts-dir " .. scripts_dir .. " || bash " .. scripts_dir .. "/watchdog.sh silhouette-shell")
    else
      hl.exec_cmd("bash " .. scripts_dir .. "/session-start.sh")
      hl.exec_cmd("bash " .. scripts_dir .. "/awww-daemon-wrapper.sh start")
      hl.exec_cmd("bash " .. scripts_dir .. "/cliphist-watch.sh")
      hl.exec_cmd("bash " .. scripts_dir .. "/watchdog.sh silhouette-shell")
    end
  else
    hl.exec_cmd("SILHOUETTE_NO_NATIVE=1 SILHOUETTE_FORCE_SHELL=1 SILHOUETTE_FORCE_PYTHON=1 bash " .. scripts_dir .. "/session-start.sh")
    hl.exec_cmd("SILHOUETTE_NO_NATIVE=1 SILHOUETTE_FORCE_SHELL=1 SILHOUETTE_FORCE_PYTHON=1 bash " .. scripts_dir .. "/awww-daemon-wrapper.sh start")
    hl.exec_cmd("SILHOUETTE_NO_NATIVE=1 SILHOUETTE_FORCE_SHELL=1 SILHOUETTE_FORCE_PYTHON=1 bash " .. scripts_dir .. "/cliphist-watch.sh")
    hl.exec_cmd("SILHOUETTE_NO_NATIVE=1 SILHOUETTE_FORCE_SHELL=1 SILHOUETTE_FORCE_PYTHON=1 sh " .. scripts_dir .. "/watchdog-fallback.sh silhouette-shell")
  end
end)

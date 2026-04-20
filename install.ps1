$ErrorActionPreference = "Stop"

$DotfilesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProfilePath = $PROFILE

$NvimConfigPath = "$env:LOCALAPPDATA\nvim"
$YaziConfigPath = "$env:APPDATA\yazi"
$BatConfigPath  = "$env:APPDATA\bat"

function Fail($msg) {
    Write-Error $msg
    exit 1
}

function Warn($msg) {
    Write-Warning $msg
}

function Require-Command($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Fail "Missing required dependency: $cmd"
    }
}

Write-Output "==> Preflight checks"

New-Item -ItemType Directory -Force -Path (Split-Path $ProfilePath) | Out-Null

$NestedGit = Get-ChildItem -Path $DotfilesDir -Recurse -Force -Directory -Filter ".git" |
    Where-Object { $_.FullName -ne (Join-Path $DotfilesDir ".git") }

if ($NestedGit) {
    Warn "Nested .git detected"
}

Write-Output "==> Installing dependencies"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget not found. Install manually."
}

$packages = @(
    "junegunn.fzf",
    "BurntSushi.ripgrep",
    "ajeetdsouza.zoxide",
    "Neovim.Neovim",
    "sharkdp.bat",
    "sxyazi.yazi",
    "JanDeDobbeleer.OhMyPosh",
    "Git.Git"
)

foreach ($pkg in $packages) {
    $exists = winget list --id $pkg -e 2>$null
    if (-not $exists) {
        try {
            winget install --id $pkg -e --silent
        } catch {
            Fail "Failed installing $pkg"
        }
    }
}

Write-Output "==> Validating dependencies"

$commands = @("fzf","rg","zoxide","nvim","bat","yazi","oh-my-posh","git")

foreach ($cmd in $commands) {
    Require-Command $cmd
}

Write-Output "==> Backing up configs"

function Backup($path) {
    if (Test-Path $path) {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        Copy-Item $path "$path.$ts.bak" -Recurse -Force
    }
}

Backup $ProfilePath
Backup $NvimConfigPath
Backup $YaziConfigPath
Backup "$HOME\.ripgreprc"

Write-Output "==> Creating directories"

New-Item -ItemType Directory -Force -Path $NvimConfigPath | Out-Null
New-Item -ItemType Directory -Force -Path $YaziConfigPath | Out-Null
New-Item -ItemType Directory -Force -Path $BatConfigPath | Out-Null

function Safe-Link($target, $link) {

    if (-not (Test-Path $target)) {
        Fail "Target missing: $target"
    }

    $temp = "$link.tmp"

    try {
        if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }

        New-Item -ItemType SymbolicLink -Path $temp -Target $target -ErrorAction Stop | Out-Null

        # backup existing BEFORE delete
        if (Test-Path $link) {
            $backup = "$link.prelink.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $link $backup -Recurse -Force
            Remove-Item $link -Recurse -Force
        }

        Rename-Item $temp $link -ErrorAction Stop

        if (-not (Test-Path $link)) {
            Fail "Link creation failed: $link"
        }

        Write-Output "Linked: $link"
    }
    catch {
        if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }

        Warn "Symlink failed for $link. Reason: $($_.Exception.Message)"

        try {
            if (Test-Path $link) {
                $backup = "$link.precopy.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item $link $backup -Recurse -Force
                Remove-Item $link -Recurse -Force
            }

            Copy-Item $target $link -Recurse -Force -ErrorAction Stop

            if (-not (Test-Path $link)) {
                Fail "Copy fallback failed for $link"
            }

            Write-Output "Copied: $link"
        }
        catch {
            Fail "Hard failure linking $link : $($_.Exception.Message)"
        }
    }
}

function Ensure-Line($file, $match, $line) {
    if (-not (Test-Path $file)) {
        New-Item -ItemType File -Path $file -Force | Out-Null
    }

    $content = Get-Content $file -Raw -ErrorAction SilentlyContinue

    if (-not $content -or $content -notmatch [regex]::Escape($match)) {
        Add-Content -Path $file -Value "`n$line"
    }
}

Write-Output "==> Linking dotfiles"

Safe-Link "$DotfilesDir\pwshprofile\Microsoft.PowerShell_profile.ps1" $ProfilePath
Safe-Link "$DotfilesDir\editors\nvim\init.lua" "$NvimConfigPath\init.lua"
Safe-Link "$DotfilesDir\tools\yazi" $YaziConfigPath

if (Test-Path "$DotfilesDir\terminal\bat\themes") {
    Safe-Link "$DotfilesDir\terminal\bat\themes" "$BatConfigPath\themes"
}

Write-Output "==> Configuring PowerShell profile"

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Ensure-Line $ProfilePath "oh-my-posh init" 'oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression'
} else {
    Fail "oh-my-posh missing after install"
}

Write-Output "==> Post setup"

if (Get-Command bat -ErrorAction SilentlyContinue) {
    try { bat cache --build | Out-Null } catch { Warn "bat cache failed" }
}

Write-Output "==> Install complete"

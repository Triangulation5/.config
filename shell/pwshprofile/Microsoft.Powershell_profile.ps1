$ompTheme = "$env:LOCALAPPDATA\Programs\oh-my-posh\themes\vague-terminal.omp.json"
oh-my-posh init pwsh --config $ompTheme | Invoke-Expression

function y {
    $tmp = (New-TemporaryFile).FullName
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
        Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
    }
    Remove-Item -Path $tmp
}

$env:FZF_DEFAULT_COMMAND = if (Get-Command rg -ErrorAction SilentlyContinue) {
    'rg --files --hidden --glob "!.git/*"'
} else { 'Get-ChildItem -Recurse -File | ForEach-Object FullName' }

$env:FZF_DEFAULT_OPTS = @"
--color=fg:#cdcdcd,fg+:#e8b589,bg:#141415,bg+:#1c1c24 `
--color=hl:#7e98e8,hl+:#6e94b2,info:#606079,marker:#7fa563 `
--color=prompt:#d8647e,spinner:#7e98e8,pointer:#7e98e8,header:#606079 `
--color=border:#878787,label:#cdcdcd,query:#cdcdcd
--border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
--marker=">" --pointer=" " --separator="─" --scrollbar="|"
--height=95% --style=default
--preview='bat --color=always --style=numbers --line-range=:500 {}'
"@

# *** Rose Pine Main ***
# --color=fg:#e0def4,fg+:#e0def4,bg:#191724,bg+:#1f1d2e
# --color=hl:#c4a7e7,hl+:#c4a7e7,info:#908caa,marker:#31748f
# --color=prompt:#eb6f92,spinner:#c4a7e7,pointer:#c4a7e7,header:#6e6a86
# --color=border:#26233a,label:#e0def4,query:#e0def4
# *** Flexoki (Sublime Text colorscheme) ***
# --color=fg:#CECDC3,fg+:#E6E4D9,bg:#1C1B1A,bg+:#282726 `
# --color=hl:#8B7EC8,hl+:#5E409D,info:#9F9D96,marker:#3AA99F `
# --color=prompt:#D14D41,spinner:#8B7EC8,pointer:#8B7EC8,header:#6F6E69 `
# --color=border:#343331,label:#E6E4D9,query:#E6E4D9
# *** Vague colorscheme ***
# --color=fg:#cdcdcd,fg+:#e8b589,bg:#141415,bg+:#1c1c24 `
# --color=hl:#7e98e8,hl+:#6e94b2,info:#606079,marker:#7fa563 `
# --color=prompt:#d8647e,spinner:#7e98e8,pointer:#7e98e8,header:#606079 `
# --color=border:#878787,label:#cdcdcd,query:#cdcdcd

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function MenuComplete
}

function fzf-file {
    $f = fzf
    if ($f) { Set-Clipboard -Value $f }
}
Set-Alias fzf-file fzf-file

function fzf-dir {
    $d = fzf --preview "if (Test-Path '{}') { ls -Force -Name '{}' }" --preview-window=right:40%
    if ($d) { Set-Location $d }
}
Set-Alias fzf-dir fzf-dir

function fzfn {
    fzf | % { & nvim $_ }
}

$env:BAT_THEME = "Vague"

Invoke-Expression (& { (zoxide init powershell | Out-String) })

$env:EDITOR = "nvim"
$env:VISUAL = "nvim"

clear

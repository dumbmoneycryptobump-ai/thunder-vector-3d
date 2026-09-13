[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "找不到 Codex CLI。先執行 scripts/install_windows.ps1，或安裝後重開 PowerShell。"
}

if (-not (Test-Path ".git")) {
    git init
    git add .
    git commit -m "Initial Codex handoff checkpoint" 2>$null
}

$Prompt = Get-Content "prompts/CODEX_MASTER_PROMPT.md" -Raw
$Prompt | codex exec --sandbox workspace-write -

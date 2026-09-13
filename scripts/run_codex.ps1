[CmdletBinding()]
param([switch]$BuildCore)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "Codex CLI is not installed. Run: npm install -g @openai/codex@latest"
}
if ($BuildCore) {
    $prompt = Get-Content "prompts\CODEX_MASTER_PROMPT.md" -Raw
    codex exec --sandbox workspace-write $prompt | Tee-Object -FilePath "logs\codex-last.md"
} else {
    codex
}

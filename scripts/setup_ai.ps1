[CmdletBinding()]
param(
    [string]$OllamaModel = "",
    [switch]$SkipModelPull
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$pythonCommand = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { $null }
if (-not $pythonCommand) { throw "Python was not found. Run scripts/install_windows.ps1 or install Python 3.10+." }

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    & $pythonCommand -m venv .venv
}
& ".venv\Scripts\python.exe" -m pip install --upgrade pip
& ".venv\Scripts\python.exe" -m pip install -r tools\requirements.txt

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Warning "Ollama was not found. The game still runs; only local-model review will be unavailable."
} elseif (-not $SkipModelPull -and $OllamaModel) {
    Write-Host "Pulling Ollama model '$OllamaModel'. This may be a large download." -ForegroundColor Cyan
    ollama pull $OllamaModel
} else {
    Write-Host "No model was pulled. Choose one later, for example: ollama pull qwen3.5" -ForegroundColor Yellow
}

if (-not (Test-Path ".git")) {
    git init
    git add .
    git commit -m "Initial Thunder Vector 3D starter kit" 2>$null
}

& ".venv\Scripts\python.exe" tools\verify_project.py
Write-Host "`nAI environment ready. Next run scripts/configure_codex_mcp.ps1." -ForegroundColor Green

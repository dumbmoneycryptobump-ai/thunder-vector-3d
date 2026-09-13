[CmdletBinding()]
param(
    [switch]$SkipBlender,
    [switch]$SkipOllama
)

$ErrorActionPreference = "Continue"

function Install-PackageSafe {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Name)
    Write-Host "`n==> $Name ($Id)" -ForegroundColor Cyan
    $installed = winget list --id $Id -e 2>$null | Select-String -SimpleMatch $Id
    if ($installed) {
        Write-Host "Already installed." -ForegroundColor Green
        return
    }
    winget install --id $Id -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Name could not be installed automatically. Install it manually, then rerun verification."
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is unavailable. Update Microsoft App Installer, or follow README.md for manual installation."
}

Install-PackageSafe "GodotEngine.GodotEngine" "Godot Engine"
Install-PackageSafe "Git.Git" "Git"
Install-PackageSafe "Microsoft.VisualStudioCode" "Visual Studio Code"
Install-PackageSafe "Python.Python.3.13" "Python 3"
Install-PackageSafe "OpenJS.NodeJS.LTS" "Node.js LTS"
if (-not $SkipBlender) { Install-PackageSafe "BlenderFoundation.Blender" "Blender" }
if (-not $SkipOllama) { Install-PackageSafe "Ollama.Ollama" "Ollama" }

Write-Host "`nInstalling/updating Codex CLI with npm..." -ForegroundColor Cyan
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install -g @openai/codex@latest
} else {
    Write-Warning "npm is not visible in this shell yet. Restart PowerShell, then run: npm install -g @openai/codex@latest"
}

Write-Host "`nInstallation stage finished. Restart PowerShell so PATH changes are applied, then run scripts/setup_ai.ps1." -ForegroundColor Green

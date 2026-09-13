[CmdletBinding()]
param(
    [switch]$Editor,
    [switch]$Exported,
    [string]$GodotCommand = "godot"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Game = Join-Path $Root "game"


function Resolve-GodotPath {
    param([Parameter(Mandatory)][string]$CommandName)

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($CommandName -ne "godot" -or -not $env:LOCALAPPDATA) { return $null }

    $packageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { return $null }
    $candidates = @(
        Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "GodotEngine.GodotEngine_*" } |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq "Godot_v4.7.2-stable_win64_console.exe" }
            }
    )
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}


if ($Editor -and $Exported) { throw "Choose either -Editor or -Exported, not both." }
if ($Exported) {
    $exePath = Join-Path $Root "build\ThunderVector3D.exe"
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Exported game was not found at $exePath. Run .\scripts\build_windows.ps1 first."
    }
    Start-Process -FilePath $exePath -WorkingDirectory (Split-Path -Parent $exePath) | Out-Null
    Write-Host "Started exported game: $exePath" -ForegroundColor Green
    return
}

$godotPath = Resolve-GodotPath -CommandName $GodotCommand
if (-not $godotPath) { throw "Godot 4.7.2 was not found in PATH or the WinGet installation directory." }
$versionOutput = @(& $godotPath --version 2>&1)
$versionExitCode = $LASTEXITCODE
$version = ($versionOutput | Select-Object -Last 1).ToString().Trim()
if ($versionExitCode -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    throw "Godot 4.7.2 is required; '$godotPath' reported '$version' (exit $versionExitCode)."
}

if ($Editor) {
    & $godotPath --editor --path $Game
} else {
    & $godotPath --path $Game
}

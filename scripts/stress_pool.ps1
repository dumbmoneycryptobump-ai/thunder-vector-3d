[CmdletBinding()]
param([string]$GodotCommand = "godot")
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Game = Join-Path $Root "game"

$command = Get-Command $GodotCommand -ErrorAction SilentlyContinue
$godotPath = if ($command) { $command.Source } else { $null }
if (-not $godotPath -and $GodotCommand -eq "godot" -and $env:LOCALAPPDATA) {
    $packageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $packageRoot -PathType Container) {
        $godotPath = @(
            Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "GodotEngine.GodotEngine_*" } |
                ForEach-Object {
                    Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "Godot_v4.7.2-stable_win64_console.exe" }
                }
        ) | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $godotPath) { throw "Godot 4.7.2 was not found." }

$version = @(& $godotPath --version 2>&1) | Select-Object -Last 1
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    throw "Godot 4.7.2 is required; '$godotPath' reported '$version'."
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$output = @(& $godotPath --headless --path $Game --fixed-fps 60 --quit-after 36600 --script res://tests/pool_stress.gd 2>&1)
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
$output | ForEach-Object { Write-Host $_ }
$ansiEscape = "$([char]27)\[[0-?]*[ -/]*[@-~]"
$errorLines = @(
    $output |
        ForEach-Object { "$_" -replace $ansiEscape, "" } |
        Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }
)
if ($exitCode -ne 0 -or $errorLines.Count -gt 0 -or -not ($output -match 'POOL_STRESS_PASS')) {
    throw "Godot 10-minute simulated pool stress test failed (exit $exitCode; $($errorLines.Count) error line(s))."
}
Write-Host "Godot 10-minute simulated pool stress test passed." -ForegroundColor Green

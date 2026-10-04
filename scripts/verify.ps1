[CmdletBinding()]
param([string]$GodotCommand = "godot")
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Game = Join-Path $Root "game"
Set-Location $Root

function Invoke-GodotCheck {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$GodotPath,
        [Parameter(Mandatory)][string[]]$GodotArguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = @(& $GodotPath @GodotArguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference

    $output | ForEach-Object { Write-Host $_ }
    $ansiEscape = "$([char]27)\[[0-?]*[ -/]*[@-~]"
    $errorLines = @(
        $output |
            ForEach-Object { "$_" -replace $ansiEscape, "" } |
            Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }
    )
    if ($exitCode -ne 0 -or $errorLines.Count -gt 0) {
        throw "$Label failed (exit $exitCode; $($errorLines.Count) Godot error line(s))."
    }
    Write-Host "$Label passed." -ForegroundColor Green
}

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

$python = if (Test-Path ".venv\Scripts\python.exe") { ".venv\Scripts\python.exe" } elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "py" }
& $python tools\verify_project.py
if ($LASTEXITCODE -ne 0) { throw "Static project validation failed." }
& $python -m unittest tools/test_verify_project.py
if ($LASTEXITCODE -ne 0) { throw "Static verifier unit tests failed." }
& $python -m unittest tools/test_publication_tools.py
if ($LASTEXITCODE -ne 0) { throw "Publication safety regression tests failed." }
& $python tools/test_font_coverage.py
if ($LASTEXITCODE -ne 0) { throw "Offline font coverage validation failed." }

$godotPath = Resolve-GodotPath -CommandName $GodotCommand
if ($godotPath) {
    $versionOutput = @(& $godotPath --version 2>&1)
    $versionExitCode = $LASTEXITCODE
    $version = ($versionOutput | Select-Object -Last 1).ToString().Trim()
    if ($versionExitCode -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
        throw "Godot 4.7.2 is required; '$godotPath' reported '$version' (exit $versionExitCode)."
    }
    Write-Host "Godot $version ($godotPath)" -ForegroundColor Cyan
    Invoke-GodotCheck -Label "Godot headless import/parser validation" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--import")
    Invoke-GodotCheck -Label "Godot settings persistence self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/settings_store_test.gd")
    Invoke-GodotCheck -Label "Godot settings keyboard/UI self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/settings_ui_test.gd")
    Invoke-GodotCheck -Label "Godot generated-art alpha/integration self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/art_integration_test.gd")
    Invoke-GodotCheck -Label "Godot complete gameplay-flow self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/gameplay_flow_test.gd")
    Invoke-GodotCheck -Label "Godot transient FX/audio pool self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/transient_effects_test.gd")
    Invoke-GodotCheck -Label "Godot optimized-runtime regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/runtime_optimization_test.gd")
    Invoke-GodotCheck -Label "Godot cached-HUD/terminal-frame regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/hud_runtime_test.gd")
    Invoke-GodotCheck -Label "Godot encounter catalog self-test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/encounter_director_test.gd")
    Invoke-GodotCheck -Label "Godot content expansion integration test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/content_expansion_test.gd")
    Invoke-GodotCheck -Label "Godot shield pickup regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/shield_pickup_test.gd")
    Invoke-GodotCheck -Label "Godot arsenal pattern regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/arsenal_test.gd")
    Invoke-GodotCheck -Label "Godot arcade feedback regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/arcade_feedback_test.gd")
    Invoke-GodotCheck -Label "Godot arcade combat integration test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/arcade_combat_test.gd")
    Invoke-GodotCheck -Label "Godot arcade progression/state regression test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/arcade_flow_test.gd")
    Invoke-GodotCheck -Label "Godot bounded three-sector scenery test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/sector_scenery_test.gd")
    Invoke-GodotCheck -Label "Godot expanded map integration test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/map_integration_test.gd")
    Invoke-GodotCheck -Label "Godot special weapons damage/lifecycle test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/weapon_system_test.gd")
    Invoke-GodotCheck -Label "Godot expanded edge/lifetime/capacity test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/expanded_edge_test.gd")
    Invoke-GodotCheck -Label "Godot multi-touch ownership test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/device_controls_test.gd")
    Invoke-GodotCheck -Label "Godot cross-device main integration test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--script", "res://tests/device_integration_test.gd")
    Invoke-GodotCheck -Label "Godot 15-second main-scene smoke test" -GodotPath $godotPath -GodotArguments @("--headless", "--path", $Game, "--fixed-fps", "60", "--quit-after", "1200", "--script", "res://tests/headless_smoke.gd")
} else {
    throw "Godot 4.7.2 was not found; static checks passed, but parser/runtime validation was not completed."
}

[CmdletBinding()]
param(
    [string]$GodotCommand = "godot",
    [switch]$SkipLaunchValidation
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Game = Join-Path $Root "game"
$Build = Join-Path $Root "build"
$Version = "1.0.0"
$ReleaseName = "ThunderVector3D-$Version-windows-x86_64"


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


function Get-GodotErrorLines {
    param([Parameter(Mandatory)][object[]]$Lines)

    $ansiEscape = "$([char]27)\[[0-?]*[ -/]*[@-~]"
    return @(
        $Lines |
            ForEach-Object { "$_" -replace $ansiEscape, "" } |
            Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }
    )
}


function Assert-GeneratedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedParent
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($AllowedParent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated path escaped its allowed directory: $fullPath"
    }
    return $fullPath
}


function Remove-GeneratedItem {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedParent,
        [switch]$Recurse
    )

    $safePath = Assert-GeneratedPath -Path $Path -AllowedParent $AllowedParent
    if (-not (Test-Path -LiteralPath $safePath)) { return }
    if ($Recurse) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
    } else {
        Remove-Item -LiteralPath $safePath -Force
    }
}


function Assert-WindowsX64Executable {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 64) { throw "Exported file is too small to be a PE executable." }
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Exported file is missing the MZ signature." }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset + 6 -gt $stream.Length) { throw "Exported file has an invalid PE header offset." }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Exported file is missing the PE signature." }
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) { throw ("Exported PE machine is 0x{0:X4}; expected x86_64 (0x8664)." -f $machine) }
    } finally {
        $stream.Dispose()
    }
}


function Assert-CleanGodotLog {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label did not create its log file: $Path" }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $errors = Get-GodotErrorLines -Lines $lines
    if ($errors.Count -gt 0) { throw "$Label log contains $($errors.Count) Godot error line(s)." }
}


function Get-StreamSha256 {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $hasher.ComputeHash($Stream)
        return ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $hasher.Dispose()
    }
}


Set-Location $Root
$godotPath = Resolve-GodotPath -CommandName $GodotCommand
if (-not $godotPath) { throw "Godot 4.7.2 was not found in PATH or the WinGet installation directory." }

$versionOutput = @(& $godotPath --version 2>&1)
$versionExitCode = $LASTEXITCODE
$engineVersion = ($versionOutput | Select-Object -Last 1).ToString().Trim()
if ($versionExitCode -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    throw "Godot 4.7.2 is required; '$godotPath' reported '$engineVersion' (exit $versionExitCode)."
}

if (-not $env:APPDATA) { throw "APPDATA is unavailable; cannot locate Godot export templates." }
$templatePath = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe"
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Godot 4.7.2 Windows x86_64 release template is missing: $templatePath"
}

Write-Host "Running the complete source verification gate..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "verify.ps1") -GodotCommand $godotPath

New-Item -ItemType Directory -Force -Path $Build | Out-Null
$exePath = Assert-GeneratedPath -Path (Join-Path $Build "ThunderVector3D.exe") -AllowedParent $Build
$headlessLog = Assert-GeneratedPath -Path (Join-Path $Build "exported_headless_smoke.log") -AllowedParent $Build
$windowedLog = Assert-GeneratedPath -Path (Join-Path $Build "exported_windowed_smoke.log") -AllowedParent $Build
Remove-GeneratedItem -Path $exePath -AllowedParent $Build
Remove-GeneratedItem -Path $headlessLog -AllowedParent $Build
Remove-GeneratedItem -Path $windowedLog -AllowedParent $Build

$exportStarted = Get-Date
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$exportOutput = @(& $godotPath --headless --path $Game --export-release "Windows Desktop" $exePath 2>&1)
$exportExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
$exportOutput | ForEach-Object { Write-Host $_ }
$exportErrors = Get-GodotErrorLines -Lines $exportOutput
if ($exportExitCode -ne 0 -or $exportErrors.Count -gt 0) {
    throw "Windows export failed (exit $exportExitCode; $($exportErrors.Count) Godot error line(s))."
}
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Godot reported success but did not create $exePath" }
$exeItem = Get-Item -LiteralPath $exePath
if ($exeItem.Length -lt 1MB) { throw "Exported executable is unexpectedly small: $($exeItem.Length) bytes." }
if ($exeItem.LastWriteTime -lt $exportStarted.AddSeconds(-2)) { throw "Exported executable is stale and was not created by this build." }
Assert-WindowsX64Executable -Path $exePath
$exeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Exported x86_64 PE: $exePath ($($exeItem.Length) bytes, SHA-256 $exeHash)" -ForegroundColor Green

$launchValidation = "passed"
if ($SkipLaunchValidation) {
    $launchValidation = "skipped-by-explicit-switch"
    Write-Warning "Exported EXE launch validation was explicitly skipped; the package is not launch-validated."
} else {
    $headlessProcess = Start-Process -FilePath $exePath -ArgumentList @(
        "--headless", "--fixed-fps", "60", "--quit-after", "300", "--log-file", "`"$headlessLog`""
    ) -WorkingDirectory $Build -WindowStyle Hidden -PassThru
    if (-not $headlessProcess.WaitForExit(30000)) {
        Stop-Process -Id $headlessProcess.Id -Force -ErrorAction SilentlyContinue
        throw "Exported headless smoke test exceeded 30 seconds."
    }
    $headlessProcess.Refresh()
    if ($headlessProcess.ExitCode -ne 0) { throw "Exported headless smoke test exited $($headlessProcess.ExitCode)." }
    Assert-CleanGodotLog -Label "Exported headless smoke test" -Path $headlessLog
    Write-Host "Exported headless smoke test passed." -ForegroundColor Green

    $windowedProcess = $null
    try {
        $windowedProcess = Start-Process -FilePath $exePath -ArgumentList @(
            "--log-file", "`"$windowedLog`""
        ) -WorkingDirectory $Build -PassThru
        $windowDeadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 250
            $windowedProcess.Refresh()
        } while (-not $windowedProcess.HasExited -and $windowedProcess.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $windowDeadline)

        if ($windowedProcess.HasExited) { throw "Exported windowed smoke test exited early with code $($windowedProcess.ExitCode)." }
        if ($windowedProcess.MainWindowHandle -eq 0) { throw "Exported game did not create a Windows main window within 15 seconds." }
        Start-Sleep -Seconds 3
        $windowedProcess.Refresh()
        if ($windowedProcess.HasExited) { throw "Exported game exited during the windowed survival check." }
        if (-not $windowedProcess.CloseMainWindow()) { throw "Exported game window did not accept a normal close request." }
        if (-not $windowedProcess.WaitForExit(10000)) { throw "Exported game did not close normally within 10 seconds." }
        $windowedProcess.Refresh()
        if ($windowedProcess.ExitCode -ne 0) { throw "Exported windowed smoke test exited $($windowedProcess.ExitCode)." }
    } finally {
        if ($null -ne $windowedProcess) {
            $windowedProcess.Refresh()
            if (-not $windowedProcess.HasExited) {
                Stop-Process -Id $windowedProcess.Id -Force -ErrorAction SilentlyContinue
                $windowedProcess.WaitForExit(5000) | Out-Null
            }
        }
    }
    Assert-CleanGodotLog -Label "Exported windowed smoke test" -Path $windowedLog
    Write-Host "Exported Windows-window smoke test passed." -ForegroundColor Green
}

$stagePath = Assert-GeneratedPath -Path (Join-Path $Build $ReleaseName) -AllowedParent $Build
$zipPath = Assert-GeneratedPath -Path (Join-Path $Build "$ReleaseName.zip") -AllowedParent $Build
Remove-GeneratedItem -Path $stagePath -AllowedParent $Build -Recurse
Remove-GeneratedItem -Path $zipPath -AllowedParent $Build
New-Item -ItemType Directory -Path (Join-Path $stagePath "LICENSES") -Force | Out-Null
Copy-Item -LiteralPath $exePath -Destination (Join-Path $stagePath "ThunderVector3D.exe")
Copy-Item -LiteralPath (Join-Path $Root "docs\RELEASE_README.txt") -Destination (Join-Path $stagePath "README.txt")
Copy-Item -LiteralPath (Join-Path $Root "docs\licenses\GODOT_LICENSE.txt") -Destination (Join-Path $stagePath "LICENSES\GODOT_LICENSE.txt")
Copy-Item -LiteralPath (Join-Path $Root "docs\licenses\GODOT_COPYRIGHT.txt") -Destination (Join-Path $stagePath "LICENSES\GODOT_COPYRIGHT.txt")
Copy-Item -LiteralPath (Join-Path $Root "docs\licenses\GODOT_THIRD_PARTY_NOTICES.txt") -Destination (Join-Path $stagePath "LICENSES\GODOT_THIRD_PARTY_NOTICES.txt")
Copy-Item -LiteralPath (Join-Path $Root "LICENSE_ASSETS.txt") -Destination (Join-Path $stagePath "LICENSES\LICENSE_ASSETS.txt")
Copy-Item -LiteralPath (Join-Path $Game "assets\generated\ART_PROVENANCE.md") -Destination (Join-Path $stagePath "ART_PROVENANCE.md")

$gitCommit = (& git -C $Root rev-parse HEAD 2>$null).Trim()
if (-not $gitCommit) { $gitCommit = "unavailable" }
$gitState = if ((& git -C $Root status --porcelain 2>$null)) { "working-tree-with-changes" } else { "clean" }
$buildInfo = @(
    "product=Thunder Vector 3D"
    "version=$Version"
    "target=windows-x86_64"
    "godot=$engineVersion"
    "renderer=GL Compatibility"
    "launch_validation=$launchValidation"
    "git_commit=$gitCommit"
    "source_state=$gitState"
    "built_utc=$([DateTime]::UtcNow.ToString('o'))"
)
Set-Content -LiteralPath (Join-Path $stagePath "BUILD_INFO.txt") -Value $buildInfo -Encoding utf8
Set-Content -LiteralPath (Join-Path $stagePath "SHA256SUMS.txt") -Value "$exeHash  ThunderVector3D.exe" -Encoding ascii

Compress-Archive -Path (Join-Path $stagePath "*") -DestinationPath $zipPath -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$expectedEntries = @(
    "ART_PROVENANCE.md",
    "BUILD_INFO.txt",
    "LICENSES/GODOT_COPYRIGHT.txt",
    "LICENSES/GODOT_LICENSE.txt",
    "LICENSES/GODOT_THIRD_PARTY_NOTICES.txt",
    "LICENSES/LICENSE_ASSETS.txt",
    "README.txt",
    "SHA256SUMS.txt",
    "ThunderVector3D.exe"
) | Sort-Object
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $actualEntries = @($archive.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\', '/') } | Sort-Object)
    if (($actualEntries -join "`n") -ne ($expectedEntries -join "`n")) {
        throw "Release ZIP entry whitelist mismatch: $($actualEntries -join ', ')"
    }
    $zippedExe = $archive.GetEntry("ThunderVector3D.exe")
    if ($null -eq $zippedExe) { throw "Release ZIP is missing ThunderVector3D.exe." }
    $zippedStream = $zippedExe.Open()
    try { $zippedExeHash = Get-StreamSha256 -Stream $zippedStream } finally { $zippedStream.Dispose() }
    if ($zippedExeHash -ne $exeHash) { throw "Release ZIP executable hash does not match the validated export." }
} finally {
    $archive.Dispose()
}
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

if ($SkipLaunchValidation) {
    Write-Host "Release archive integrity verified; exported EXE launch validation was skipped: $zipPath" -ForegroundColor Yellow
} else {
    Write-Host "Windows release package and exported EXE launch verified: $zipPath" -ForegroundColor Green
}
Write-Host "ZIP SHA-256: $zipHash" -ForegroundColor Green

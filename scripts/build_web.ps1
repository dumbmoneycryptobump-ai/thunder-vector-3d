[CmdletBinding()]
param(
    [string]$GodotCommand = "godot",
    [ValidatePattern('^[A-Za-z0-9_-]*$')]
    [string]$BuildName = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$gameRoot = Join-Path $projectRoot "game"
if (-not $BuildName) { $BuildName = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ") }
$buildParent = Join-Path $projectRoot "build/web-crossdevice"
$runRoot = Join-Path $buildParent $BuildName
$siteRoot = Join-Path $runRoot "site"
if (Test-Path -LiteralPath $runRoot) { throw "Refusing to reuse an existing build directory: $runRoot. Choose a fresh -BuildName." }

$godotPath = (Get-Command $GodotCommand -ErrorAction SilentlyContinue).Source
if (-not $godotPath -and $GodotCommand -eq "godot" -and $env:LOCALAPPDATA) {
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft/WinGet/Packages"
    $godotPath = Get-ChildItem -LiteralPath $wingetRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "GodotEngine.GodotEngine_*" } |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File | Where-Object { $_.Name -eq "Godot_v4.7.2-stable_win64_console.exe" } } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godotPath) { throw "Godot 4.7.2 was not found; supply -GodotCommand with its executable path." }
$engineVersion = (@(& $godotPath --version 2>&1) | Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Expected Godot 4.7.2 stable, got $engineVersion" }
if ($env:APPDATA) {
    $templateRoot = Join-Path $env:APPDATA "Godot/export_templates/4.7.2.stable"
} elseif ($env:XDG_DATA_HOME) {
    $templateRoot = Join-Path $env:XDG_DATA_HOME "godot/export_templates/4.7.2.stable"
} else {
    $templateRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".local/share/godot/export_templates/4.7.2.stable"
}
$template = Join-Path $templateRoot "web_nothreads_release.zip"
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Missing official single-threaded Web template: $template. See web/README.md." }

function Invoke-GodotChecked {
    param([string[]]$Arguments)
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lines = @(& $godotPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $priorPreference
    $lines | ForEach-Object { Write-Host $_ }
    $plain = $lines | ForEach-Object { "$_" -replace "$([char]27)\[[0-?]*[ -/]*[@-~]", "" }
    if ($exitCode -ne 0 -or @($plain | Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }).Count -gt 0) {
        throw "Godot validation/export failed (exit $exitCode). No successful build is reported."
    }
}

Push-Location $projectRoot
try {
    & python tools/verify_project.py
    if ($LASTEXITCODE -ne 0) { throw "Static project verification failed." }
    Invoke-GodotChecked -Arguments @("--headless", "--path", $gameRoot, "--editor", "--quit")
    New-Item -ItemType Directory -Path $siteRoot -Force | Out-Null
    $htmlPath = Join-Path $siteRoot "index.html"
    Invoke-GodotChecked -Arguments @("--headless", "--path", $gameRoot, "--export-release", "Web", $htmlPath)
    foreach ($name in @("index.html", "index.js", "index.wasm", "index.pck", "index.service.worker.js", "index.manifest.json")) {
        $path = Join-Path $siteRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw "Missing/empty exported file: $name" }
    }
    $html = Get-Content -LiteralPath $htmlPath -Raw
    if ($html -match '\$GODOT_[A-Z_]+') { throw "The custom HTML shell contains unexpanded Godot placeholders." }
    if ($html -notmatch '"ensureCrossOriginIsolationHeaders"\s*:\s*false') { throw "Web export unexpectedly requires isolation headers." }
    $licenseRoot = Join-Path $siteRoot "licenses"
    New-Item -ItemType Directory -Path $licenseRoot | Out-Null
    foreach ($source in @("LICENSE", "LICENSE_ASSETS.txt", "docs/licenses/GODOT_LICENSE.txt", "docs/licenses/GODOT_COPYRIGHT.txt", "docs/licenses/GODOT_THIRD_PARTY_NOTICES.txt", "docs/licenses/OFL_NotoSansTC.txt", "game/assets/fonts/FONT_PROVENANCE.md")) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $licenseRoot
    }
    Get-ChildItem -LiteralPath (Join-Path $gameRoot "assets/generated") -Filter "*PROVENANCE.md" -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $licenseRoot }
    Copy-Item -LiteralPath (Join-Path $projectRoot "web/README.md") -Destination (Join-Path $siteRoot "README.md")
    $files = @(Get-ChildItem -LiteralPath $siteRoot -Recurse -File | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($siteRoot.Length + 1).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $zipPath = Join-Path $runRoot "ThunderVector3D-web.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($siteRoot, $zipPath)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($archive.Entries.Count -ne $files.Count) { throw "ZIP file count does not match the export." }
        foreach ($entry in $archive.Entries) {
            $expected = @($files | Where-Object { $_.path -eq $entry.FullName.Replace('\', '/') })
            if ($expected.Count -ne 1) { throw "Unexpected/duplicate ZIP member: $($entry.FullName)" }
            $stream = $entry.Open()
            $hasher = [System.Security.Cryptography.SHA256]::Create()
            try { $actual = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
            finally { $hasher.Dispose(); $stream.Dispose() }
            if ($actual -ne $expected[0].sha256) { throw "ZIP member hash mismatch: $($entry.FullName)" }
        }
    } finally { $archive.Dispose() }
    $commit = (& git rev-parse HEAD).Trim()
    $dirty = @(& git status --porcelain).Count -gt 0
    $report = [ordered]@{
        build_utc = (Get-Date).ToUniversalTime().ToString("o"); engine = $engineVersion
        source_commit = $commit; source_worktree_dirty = $dirty
        preset = "Web"; threads = $false; isolation_headers_required = $false
        template_sha256 = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant()
        site = $siteRoot; zip = $zipPath
        zip_sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        browser_validation = "pending-separate-real-browser-test"; files = $files
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot "build-manifest.json") -Encoding UTF8
    Write-Host "WEB_EXPORT_PASS site=$siteRoot zip=$zipPath browser_validation=pending" -ForegroundColor Green
} finally { Pop-Location }

[CmdletBinding()]
param([string]$Task = "Review the current repository diff for correctness and regressions")
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root
if (-not (Test-Path ".venv\Scripts\python.exe")) { throw "Run scripts/setup_ai.ps1 first." }
$diff = git diff --no-ext-diff
if (-not $diff) { throw "There is no uncommitted git diff to review." }
$diff | & ".venv\Scripts\python.exe" tools\local_review.py --task $Task --output logs\local-review-last.md

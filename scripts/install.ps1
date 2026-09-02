# ==============================================================================
# Installer for Claude Desktop Plugin System on Windows (PowerShell)
# Supports local run and one-liner `irm ... | iex`
# ==============================================================================

$ErrorActionPreference = "Stop"

$RawBase = "https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main"
$TargetDir = Join-Path $env:APPDATA "Claude\plugins"

Write-Host "[*] Installing Claude Desktop Plugin System on Windows..." -ForegroundColor Cyan

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$ScriptDir = ""
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
}

if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "..\loader.js"))) {
    $RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
    Write-Host "[*] Installing from local repository ($RepoRoot)..." -ForegroundColor Cyan
    Copy-Item -Path (Join-Path $RepoRoot "loader.js") -Destination (Join-Path $TargetDir "loader.js") -Force
    Copy-Item -Path (Join-Path $RepoRoot "plugins\*.js") -Destination $TargetDir -Force
    $PatcherPath = Join-Path $ScriptDir "patch-claude-desktop.ps1"
} else {
    Write-Host "[*] Downloading latest files from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri "$RawBase/loader.js" -OutFile (Join-Path $TargetDir "loader.js")
    Invoke-RestMethod -Uri "$RawBase/plugins/auto-continue.js" -OutFile (Join-Path $TargetDir "auto-continue.js")
    
    $TempPatcher = Join-Path $env:TEMP "patch-claude-desktop.ps1"
    Invoke-RestMethod -Uri "$RawBase/scripts/patch-claude-desktop.ps1" -OutFile $TempPatcher
    $PatcherPath = $TempPatcher
}

Write-Host "[+] Installed loader & plugins to: $TargetDir" -ForegroundColor Green

# Run patcher
if (Test-Path $PatcherPath) {
    Write-Host "[*] Running Claude Desktop patcher..." -ForegroundColor Cyan
    & $PatcherPath
}

Write-Host "[+] Windows setup complete! Any .js files in $TargetDir will automatically load on Claude startup." -ForegroundColor Green

# ==============================================================================
# Installer for Claude Desktop Plugin System on Windows (PowerShell)
# Supports local run and one-liner `irm ... | iex`
# ==============================================================================

$ErrorActionPreference = "Stop"

function Initialize-PluginDirectory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Install-FromLocalRepo {
    param(
        [string]$RepoRoot,
        [string]$TargetDir
    )
    Write-Host "[*] Installing from local repository ($RepoRoot)..." -ForegroundColor Cyan
    Copy-Item -Path (Join-Path $RepoRoot "loader.js") -Destination (Join-Path $TargetDir "loader.js") -Force
    Copy-Item -Path (Join-Path $RepoRoot "plugins\*.js") -Destination $TargetDir -Force
    return (Join-Path $RepoRoot "scripts\patch-claude-desktop.ps1")
}

function Install-FromRemote {
    param(
        [string]$BaseUrl,
        [string]$TargetDir
    )
    Write-Host "[*] Downloading latest files from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri "$BaseUrl/loader.js" -OutFile (Join-Path $TargetDir "loader.js")
    Invoke-RestMethod -Uri "$BaseUrl/plugins/auto-continue.js" -OutFile (Join-Path $TargetDir "auto-continue.js")
    
    $tempPatcher = Join-Path $env:TEMP "patch-claude-desktop.ps1"
    Invoke-RestMethod -Uri "$BaseUrl/scripts/patch-claude-desktop.ps1" -OutFile $tempPatcher
    return $tempPatcher
}

function Main {
    $rawBase = "https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main"
    $targetDir = Join-Path $env:APPDATA "Claude\plugins"

    Write-Host "[*] Installing Claude Desktop Plugin System on Windows..." -ForegroundColor Cyan
    Initialize-PluginDirectory -Path $targetDir

    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
    $patcherScript = $null

    if ($scriptDir -and (Test-Path (Join-Path $scriptDir "..\loader.js"))) {
        $repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
        $patcherScript = Install-FromLocalRepo -RepoRoot $repoRoot -TargetDir $targetDir
    } else {
        $patcherScript = Install-FromRemote -BaseUrl $rawBase -TargetDir $targetDir
    }

    Write-Host "[+] Installed loader & plugins to: $targetDir" -ForegroundColor Green

    if ($patcherScript -and (Test-Path $patcherScript)) {
        Write-Host "[*] Running Claude Desktop patcher..." -ForegroundColor Cyan
        & $patcherScript
    }

    Write-Host "[+] Windows setup complete! Any .js files in $targetDir will automatically load on Claude startup." -ForegroundColor Green
}

Main

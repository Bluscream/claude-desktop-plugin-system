# ==============================================================================
# Claude Desktop Universal Plugin Patcher for Windows (PowerShell)
# Repatches Claude Desktop app.asar to load %APPDATA%\Claude\plugins\
# ==============================================================================

param(
    [string]$TargetAsar = ""
)

$ErrorActionPreference = "Stop"

# Auto-detect app.asar location if not specified
if (-not $TargetAsar) {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\AnthropicClaude\app-*\resources\app.asar",
        "$env:LOCALAPPDATA\Programs\Claude\resources\app.asar",
        "$env:ProgramFiles\Claude\resources\app.asar",
        "$env:ProgramFiles(x86)\Claude\resources\app.asar"
    )

    foreach ($pattern in $possiblePaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) {
            $TargetAsar = $found.FullName
            break
        }
    }
}

if (-not $TargetAsar -or -not (Test-Path $TargetAsar)) {
    Write-Error "[-] Error: Could not find Claude Desktop app.asar on this system."
    Write-Host "    Usage: .\patch-claude-desktop.ps1 -TargetAsar 'C:\path\to\resources\app.asar'"
    exit 1
}

Write-Host "[*] Target app.asar: $TargetAsar" -ForegroundColor Cyan

# Check if Claude is running and stop it
$claudeProcesses = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeProcesses) {
    Write-Host "[!] Claude Desktop is currently running. Stopping process..." -ForegroundColor Yellow
    $claudeProcesses | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$workDir = Join-Path $env:TEMP ("claude-patch-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $workDir | Out-Null
$asarExtractDir = Join-Path $workDir "asar-unpacked"

try {
    Write-Host "[*] Extracting app.asar..." -ForegroundColor Cyan
    npx -y @electron/asar extract "$TargetAsar" "$asarExtractDir"

    $entryFile = Join-Path $asarExtractDir ".vite\build\index.pre.js"
    if (-not (Test-Path $entryFile)) {
        $entryFile = Join-Path $asarExtractDir ".vite\build\index.js"
    }

    if (-not (Test-Path $entryFile)) {
        throw "Could not find entry point in asar archive."
    }

    $content = Get-Content -Path $entryFile -Raw
    $hookFlag = "/* CLAUDE_PLUGIN_LOADER_HOOK */"

    if ($content -match [regex]::Escape($hookFlag)) {
        Write-Host "[!] Plugin loader hook is already installed in $entryFile" -ForegroundColor Yellow
    } else {
        Write-Host "[*] Injecting universal plugin loader hook..." -ForegroundColor Cyan
        $hookCode = @"
/* CLAUDE_PLUGIN_LOADER_HOOK */
try {
  const electron = require('electron');
  const _path = require('path');
  const _fs = require('fs');
  const _userData = (electron.app ? electron.app.getPath('userData') : null) || 
                    (process.platform === 'win32' 
                      ? _path.join(process.env.APPDATA || '', 'Claude') 
                      : _path.join(require('os').homedir(), '.config', 'Claude'));
  const _loader = _path.join(_userData, 'plugins', 'loader.js');
  if (_fs.existsSync(_loader)) { require(_loader); }
} catch (_e) { console.error('[PluginLoaderHook] Error:', _e); }
"@
        $newContent = $hookCode + "`n" + $content
        Set-Content -Path $entryFile -Value $newContent -NoNewline
    }

    Write-Host "[*] Creating backup of original app.asar..." -ForegroundColor Cyan
    Copy-Item -Path "$TargetAsar" -Destination "$TargetAsar.bak" -Force

    Write-Host "[*] Repacking app.asar..." -ForegroundColor Cyan
    npx -y @electron/asar pack "$asarExtractDir" "$TargetAsar"

    Write-Host "[+] Successfully patched Claude Desktop app.asar!" -ForegroundColor Green
    Write-Host "    Plugins directory: $env:APPDATA\Claude\plugins"
    Write-Host "    Backup saved to:   $TargetAsar.bak"
} finally {
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

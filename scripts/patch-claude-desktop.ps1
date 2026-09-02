# ==============================================================================
# Claude Desktop Universal Plugin Patcher for Windows (PowerShell)
# Repatches Claude Desktop app.asar to load %APPDATA%\Claude\plugins\
# ==============================================================================

param(
    [string]$TargetAsar = ""
)

$ErrorActionPreference = "Stop"

# Collect all matching target asars
$targets = @()

if ($TargetAsar) {
    if (Test-Path $TargetAsar) {
        $targets += (Resolve-Path $TargetAsar).Path
    } else {
        Write-Error "[-] Error: Specified TargetAsar does not exist: $TargetAsar"
        exit 1
    }
} else {
    $possiblePaths = @(
        "$env:ProgramFiles\WindowsApps\Claude_*\app\resources\app.asar",
        "$env:ProgramData\Microsoft\Windows\WindowsApps\Claude_*\app\resources\app.asar",
        "$env:LOCALAPPDATA\AnthropicClaude\app-*\resources\app.asar",
        "$env:LOCALAPPDATA\Programs\Claude\resources\app.asar",
        "$env:ProgramFiles\Claude\resources\app.asar",
        "$env:ProgramFiles(x86)\Claude\resources\app.asar"
    )

    foreach ($pattern in $possiblePaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
        if ($found) {
            foreach ($item in $found) {
                if ($targets -notcontains $item.FullName) {
                    $targets += $item.FullName
                }
            }
        }
    }
}

if ($targets.Count -eq 0) {
    Write-Error "[-] Error: Could not find any Claude Desktop app.asar on this system."
    Write-Host "    Usage: .\patch-claude-desktop.ps1 -TargetAsar 'C:\path\to\resources\app.asar'"
    exit 1
}

# If multiple targets were found, print warning
if ($targets.Count -gt 1) {
    Write-Warning "[!] Found multiple Claude Desktop installations ($($targets.Count) found):"
    foreach ($t in $targets) {
        Write-Warning "    -> $t"
    }
    Write-Host "[*] Patching all $($targets.Count) installations..." -ForegroundColor Yellow
} else {
    Write-Host "[*] Target app.asar: $($targets[0])" -ForegroundColor Cyan
}

# Check if Claude is running and stop it
$claudeProcesses = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeProcesses) {
    Write-Host "[!] Claude Desktop is currently running. Stopping process..." -ForegroundColor Yellow
    $claudeProcesses | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$hookFlag = "/* CLAUDE_PLUGIN_LOADER_HOOK */"
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

foreach ($target in $targets) {
    Write-Host "`n[*] Processing: $target" -ForegroundColor Cyan
    $workDir = Join-Path $env:TEMP ("claude-patch-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $asarExtractDir = Join-Path $workDir "asar-unpacked"

    try {
        Write-Host "    -> Extracting app.asar..." -ForegroundColor Gray
        npx -y @electron/asar extract "$target" "$asarExtractDir"

        $entryFile = Join-Path $asarExtractDir ".vite\build\index.pre.js"
        if (-not (Test-Path $entryFile)) {
            $entryFile = Join-Path $asarExtractDir ".vite\build\index.js"
        }

        if (-not (Test-Path $entryFile)) {
            Write-Warning "    [!] Entry file not found in $target. Skipping."
            continue
        }

        $content = Get-Content -Path $entryFile -Raw

        if ($content -match [regex]::Escape($hookFlag)) {
            Write-Host "    [!] Plugin loader hook is already installed in $entryFile" -ForegroundColor Yellow
        } else {
            Write-Host "    -> Injecting universal plugin loader hook..." -ForegroundColor Gray
            $newContent = $hookCode + "`n" + $content
            Set-Content -Path $entryFile -Value $newContent -NoNewline
        }

        Write-Host "    -> Creating backup: $target.bak" -ForegroundColor Gray
        Copy-Item -Path "$target" -Destination "$target.bak" -Force

        Write-Host "    -> Repacking app.asar..." -ForegroundColor Gray
        npx -y @electron/asar pack "$asarExtractDir" "$target"

        Write-Host "    [+] Successfully patched: $target" -ForegroundColor Green
    } catch {
        Write-Error "    [-] Failed patching $target : $_"
    } finally {
        if (Test-Path $workDir) {
            Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n[+] All Claude Desktop targets processed!" -ForegroundColor Green
Write-Host "    Plugins directory: $env:APPDATA\Claude\plugins"

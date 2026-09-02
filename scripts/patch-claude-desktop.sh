#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Claude Desktop Universal Plugin Patcher (Low CPU / Low I/O)
# Repatches Claude Desktop AppImage / ASAR to load ~/.config/Claude/plugins/
# ==============================================================================

TARGET_APPIMAGE="${1:-/home/blu/.local/bin/Claude_Desktop.AppImage}"

if [[ ! -f "$TARGET_APPIMAGE" ]]; then
    echo "[-] Error: Target AppImage not found at $TARGET_APPIMAGE"
    echo "    Usage: $0 [/path/to/Claude_Desktop.AppImage]"
    exit 1
fi

echo "[*] Target AppImage: $TARGET_APPIMAGE"

WORK_DIR=$(mktemp -d /tmp/claude-patch-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "[*] Extracting AppImage (throttled)..."
cd "$WORK_DIR"
nice -n 19 ionice -c 3 "$TARGET_APPIMAGE" --appimage-extract > /dev/null

APP_DIR="$WORK_DIR/squashfs-root"
ASAR_FILE="$APP_DIR/usr/lib/claude-desktop/resources/app.asar"

if [[ ! -f "$ASAR_FILE" ]]; then
    echo "[-] Error: app.asar not found at $ASAR_FILE"
    exit 1
fi

ASAR_EXTRACT_DIR="$WORK_DIR/asar-unpacked"
echo "[*] Extracting app.asar..."
nice -n 19 ionice -c 3 npx -y asar extract "$ASAR_FILE" "$ASAR_EXTRACT_DIR"

ENTRY_FILE="$ASAR_EXTRACT_DIR/.vite/build/index.pre.js"
if [[ ! -f "$ENTRY_FILE" ]]; then
    ENTRY_FILE="$ASAR_EXTRACT_DIR/.vite/build/index.js"
fi

if [[ ! -f "$ENTRY_FILE" ]]; then
    echo "[-] Error: Entry file not found in asar bundle"
    exit 1
fi

HOOK_FLAG="/* CLAUDE_PLUGIN_LOADER_HOOK */"
if grep -q "$HOOK_FLAG" "$ENTRY_FILE"; then
    echo "[!] Plugin loader hook is already installed in $ENTRY_FILE"
else
    echo "[*] Injecting universal plugin loader hook into $(basename "$ENTRY_FILE")..."
    HOOK_CODE="$HOOK_FLAG
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
"
    TMP_ENTRY="$WORK_DIR/entry.tmp"
    echo "$HOOK_CODE" | cat - "$ENTRY_FILE" > "$TMP_ENTRY"
    mv "$TMP_ENTRY" "$ENTRY_FILE"
fi

echo "[*] Repacking app.asar..."
nice -n 19 ionice -c 3 npx -y asar pack "$ASAR_EXTRACT_DIR" "$ASAR_FILE"

echo "[*] Creating backup of original AppImage..."
cp "$TARGET_APPIMAGE" "${TARGET_APPIMAGE}.bak"

echo "[*] Repacking AppImage (throttled: 2 CPU cores, zstd fast compression, idle I/O priority)..."
export ARCH=x86_64
APPIMAGETOOL="/home/blu/.local/bin/appimagetool"
TMP_OUT="$WORK_DIR/Claude_Patched.AppImage"

TOOL_CMD="appimagetool"
if [[ -x "$APPIMAGETOOL" ]]; then
    TOOL_CMD="$APPIMAGETOOL --appimage-extract-and-run"
fi

nice -n 19 ionice -c 3 $TOOL_CMD \
    -n \
    --comp zstd \
    --mksquashfs-opt -processors \
    --mksquashfs-opt 2 \
    --mksquashfs-opt -Xcompression-level \
    --mksquashfs-opt 3 \
    "$APP_DIR" "$TMP_OUT" > /dev/null

chmod +x "$TMP_OUT"
mv -f "$TMP_OUT" "$TARGET_APPIMAGE"

echo "[+] Successfully patched Claude Desktop AppImage smoothly!"
echo "    Plugins loaded from: ~/.config/Claude/plugins/"
echo "    Original backup saved: ${TARGET_APPIMAGE}.bak"

#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Claude Desktop Universal Plugin Patcher (Low CPU / Low I/O)
# Repatches the Claude Desktop AppImage so its Electron main process loads
# <userData>/plugins/loader.js on startup.
#
# Usage:
#   patch-claude-desktop.sh [/path/to/Claude.AppImage]
#
# With no argument the AppImage is auto-detected from the usual locations.
# Override the detected path with $CLAUDE_APPIMAGE, and appimagetool with
# $APPIMAGETOOL.
# ==============================================================================

# ------------------------------------------------------------------ discovery

# Candidate locations, most specific first. Gear Lever installs to ~/AppImages,
# older manual installs used ~/.local/bin.
CANDIDATES=(
    "${CLAUDE_APPIMAGE:-}"
    "$HOME/AppImages/claude.appimage"
    "$HOME/AppImages/Claude.AppImage"
    "$HOME/.local/bin/Claude_Desktop.AppImage"
    "$HOME/.local/bin/claude.appimage"
    "$HOME/Applications/Claude.AppImage"
)

TARGET_APPIMAGE="${1:-}"
if [[ -z "$TARGET_APPIMAGE" ]]; then
    for candidate in "${CANDIDATES[@]}"; do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        TARGET_APPIMAGE="$candidate"
        break
    done
fi

if [[ -z "$TARGET_APPIMAGE" ]]; then
    echo "[-] Error: could not find a Claude Desktop AppImage."
    echo "    Looked in:"
    for candidate in "${CANDIDATES[@]}"; do
        [[ -n "$candidate" ]] && echo "      $candidate"
    done
    echo "    Pass the path explicitly: $0 /path/to/Claude.AppImage"
    exit 1
fi

if [[ ! -f "$TARGET_APPIMAGE" ]]; then
    echo "[-] Error: Target AppImage not found at $TARGET_APPIMAGE"
    echo "    Usage: $0 [/path/to/Claude.AppImage]"
    exit 1
fi

# The build runs from a scratch directory, so a relative path passed on the
# command line must be resolved before we cd away from the caller's cwd.
TARGET_APPIMAGE="$(readlink -f "$TARGET_APPIMAGE")"

# --------------------------------------------------------------- dependencies

MISSING=()
command -v npx >/dev/null 2>&1 || MISSING+=("npx (Node.js)")
command -v mksquashfs >/dev/null 2>&1 || MISSING+=("mksquashfs (squashfs-tools)")

APPIMAGETOOL="${APPIMAGETOOL:-$HOME/.local/bin/appimagetool}"
TOOL_CMD=""
if [[ -x "$APPIMAGETOOL" ]]; then
    TOOL_CMD="$APPIMAGETOOL --appimage-extract-and-run"
elif command -v appimagetool >/dev/null 2>&1; then
    TOOL_CMD="appimagetool"
else
    MISSING+=("appimagetool")
fi

if (( ${#MISSING[@]} )); then
    echo "[-] Error: missing required tools:"
    printf '      %s\n' "${MISSING[@]}"
    exit 1
fi

echo "[*] Target AppImage: $TARGET_APPIMAGE"

# Preserve the embedded zsync update information. appimagetool drops it unless
# it is passed back in explicitly, and losing it silently breaks auto-updates
# in Gear Lever / AppImageUpdate.
UPDATE_INFO="${UPDATE_INFO:-$("$TARGET_APPIMAGE" --appimage-updateinfo 2>/dev/null | head -1 || true)}"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-patch-XXXXXX")
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

# ------------------------------------------------------------------ injection

HOOK_FLAG="/* CLAUDE_PLUGIN_LOADER_HOOK */"
WAS_CLEAN=1
# -F is essential: the flag contains /* and */, whose asterisks are quantifiers
# in a basic regex, so a plain `grep -q` never matches and the hook gets
# re-injected on every run.
if grep -qF "$HOOK_FLAG" "$ENTRY_FILE"; then
    echo "[!] Plugin loader hook is already installed in $(basename "$ENTRY_FILE")"
    WAS_CLEAN=0
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

# --------------------------------------------------------------------- backup

# The .bak is only meaningful as a *pristine* copy. Refresh it only when the
# image we were handed was still unpatched; re-running the patcher must never
# overwrite the clean original with an already-patched build.
BACKUP="${TARGET_APPIMAGE}.bak"
if (( WAS_CLEAN )); then
    echo "[*] Creating backup of original AppImage..."
    cp "$TARGET_APPIMAGE" "$BACKUP"
elif [[ -f "$BACKUP" ]]; then
    echo "[*] Keeping existing unpatched backup: $BACKUP"
else
    echo "[!] Warning: target was already patched and no backup exists; none created."
fi

# --------------------------------------------------------------------- repack

echo "[*] Repacking AppImage (throttled: 2 CPU cores, zstd fast compression, idle I/O priority)..."
export ARCH="${ARCH:-x86_64}"
TMP_OUT="$WORK_DIR/Claude_Patched.AppImage"

UPD_ARGS=()
if [[ -n "$UPDATE_INFO" ]]; then
    echo "[*] Preserving update info: $UPDATE_INFO"
    UPD_ARGS=(-u "$UPDATE_INFO")
else
    echo "[!] Warning: no embedded update info found; auto-updates may not work."
fi

nice -n 19 ionice -c 3 $TOOL_CMD \
    "${UPD_ARGS[@]}" \
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
echo "    Plugins loaded from: <userData>/plugins/  (Linux: ~/.config/Claude/plugins/)"
if [[ -f "$BACKUP" ]]; then
    echo "    Unpatched backup:    $BACKUP"
fi

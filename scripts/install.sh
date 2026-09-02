#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Installer for Claude Desktop Plugin System
# Supports both local cloned run and one-liner `curl ... | bash`
# ==============================================================================

RAW_BASE="https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/plugins"
BIN_DIR="$HOME/.local/bin"

echo "[*] Installing Claude Desktop Plugin System..."
mkdir -p "$TARGET_DIR" "$BIN_DIR"

# Detect if running from cloned repo
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../loader.js" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    echo "[*] Installing from local repository ($REPO_ROOT)..."
    cp -f "$REPO_ROOT/loader.js" "$TARGET_DIR/loader.js"
    cp -f "$REPO_ROOT/plugins/"*.js "$TARGET_DIR/"
    cp -f "$REPO_ROOT/scripts/patch-claude-desktop.sh" "$BIN_DIR/patch-claude-desktop.sh"
else
    echo "[*] Downloading latest files from GitHub..."
    curl -fsSL "$RAW_BASE/loader.js" -o "$TARGET_DIR/loader.js"
    curl -fsSL "$RAW_BASE/plugins/auto-continue.js" -o "$TARGET_DIR/auto-continue.js"
    curl -fsSL "$RAW_BASE/scripts/patch-claude-desktop.sh" -o "$BIN_DIR/patch-claude-desktop.sh"
fi

chmod +x "$BIN_DIR/patch-claude-desktop.sh"
echo "[+] Installed loader & plugins to: $TARGET_DIR"
echo "[+] Installed patch script to: $BIN_DIR/patch-claude-desktop.sh"

# Check if Claude AppImage exists and patch it
TARGET_APPIMAGE="$BIN_DIR/Claude_Desktop.AppImage"
if [[ -f "$TARGET_APPIMAGE" ]]; then
    echo "[*] Patching installed Claude Desktop AppImage ($TARGET_APPIMAGE)..."
    "$BIN_DIR/patch-claude-desktop.sh" "$TARGET_APPIMAGE"
fi

echo "[+] Setup complete! Any .js files in $TARGET_DIR will automatically load on Claude startup."

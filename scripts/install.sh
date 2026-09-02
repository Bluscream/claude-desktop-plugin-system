#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Installer for Claude Desktop Plugin System
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/plugins"

echo "[*] Installing Claude Desktop Plugin System..."
mkdir -p "$TARGET_DIR"

# Copy loader
echo "[*] Installing loader.js -> $TARGET_DIR/loader.js"
cp -f "$REPO_ROOT/loader.js" "$TARGET_DIR/loader.js"

# Copy plugins
echo "[*] Installing bundled plugins -> $TARGET_DIR/"
cp -f "$REPO_ROOT/plugins/"*.js "$TARGET_DIR/"

# Install patch script to ~/.local/bin
mkdir -p "$HOME/.local/bin"
echo "[*] Installing patch-claude-desktop.sh -> $HOME/.local/bin/"
cp -f "$REPO_ROOT/scripts/patch-claude-desktop.sh" "$HOME/.local/bin/patch-claude-desktop.sh"
chmod +x "$HOME/.local/bin/patch-claude-desktop.sh"

echo "[*] Checking if Claude AppImage needs patching..."
if [[ -f "$HOME/.local/bin/Claude_Desktop.AppImage" ]]; then
    read -rp "Do you want to patch your installed Claude_Desktop.AppImage now? [y/N] " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        "$HOME/.local/bin/patch-claude-desktop.sh" "$HOME/.local/bin/Claude_Desktop.AppImage"
    fi
fi

echo "[+] Installation complete! Any .js files in $TARGET_DIR will be loaded on Claude startup."

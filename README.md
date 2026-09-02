# Claude Desktop Plugin System & Auto-Continue ⚡

A lightweight, update-proof, cross-platform plugin framework and enhancement suite for **Claude Desktop** on **Linux** (AppImage / Debian) and **Windows**.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows-blueviolet.svg)

---

## ⚡ Quick Start & One-Liner Install

### 🐧 Linux (Bash)
Run in terminal to install the loader, bundled plugins, and patch your AppImage:
```bash
curl -fsSL https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/install.sh | bash
```

### 🪟 Windows (PowerShell)
Run in PowerShell to install into `%APPDATA%\Claude\plugins` and patch your installed Claude Desktop:
```powershell
irm https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/install.ps1 | iex
```

---

## 🔄 Repatching (After Claude Desktop Updates)

When Claude Desktop updates, re-run the patcher to re-inject the 1-line hook into `app.asar`:

### 🐧 Linux
```bash
patch-claude-desktop.sh
```
*(Or remote one-liner: `curl -fsSL https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/patch-claude-desktop.sh | bash`)*

### 🪟 Windows
```powershell
irm https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/patch-claude-desktop.ps1 | iex
```

---

## 🌟 Highlights & Architecture

| Feature | Details |
| :--- | :--- |
| **Decoupled User Directory** | Plugins live in `~/.config/Claude/plugins/` (Linux) or `%APPDATA%\Claude\plugins\` (Windows). |
| **Update-Proof** | Updating Claude Desktop never wipes your plugins or settings. Repatching takes 3 seconds. |
| **Safe Draggable UI** | Protected against titlebar window-drag zones (`-webkit-app-region: no-drag`). |
| **Non-Blocking / Low-Resource** | On Linux, throttles repacking to 2 CPU cores with `zstd` compression; on Windows, directly modifies `app.asar`. |

---

## 📦 Bundled Plugins

### 1. `auto-continue.js` — Auto-Continue Assistant
* **Collapsible & Draggable UI**: Collapses into a sleek 32px fast-forward spark icon (`⏩`) with terracotta active glow; smoothly expands on hover or input focus.
* **Titlebar Protected**: Clamped below the draggable window header so it never becomes unclickable.
* **Position Persistence**: Drag anywhere on screen; coordinates are remembered across restarts.
* **Custom Phrase Input**: Editable prompt phrase (e.g. `Continue`, `Go on`, `Please proceed to the next step`).
* **Delay Selector**: Select between `2s`, `3s`, `5s`, `10s`, or `15s` before auto-continuing.
* **Live Countdown Badge**: Displays `⏳ In 5s [Cancel]` giving you one-click abort before submission.
* **Typing & Focus Abort Guard**: Automatically cancels if you click into the chatbox or start typing manually.
* **Runaway Guard**: Caps consecutive automatic triggers to prevent loops.

---

## 🛠️ Developing Custom Plugins

To create a new plugin, simply create a new `.js` file inside your user plugins directory:
* **Linux**: `~/.config/Claude/plugins/my-plugin.js`
* **Windows**: `%APPDATA%\Claude\plugins\my-plugin.js`

```javascript
// Example Plugin
(function() {
  console.log('[MyCustomPlugin] Loaded into Claude Desktop!');
  
  // Access the DOM, inject styles, or hook into chat events
  const style = document.createElement('style');
  style.textContent = `
    /* Your custom CSS enhancements */
  `;
  document.head.appendChild(style);
})();
```

Any `.js` file placed in the plugins directory is automatically loaded into the renderer when Claude starts.

---

## 📄 License

MIT © [Bluscream](https://github.com/Bluscream)

# Claude Desktop Plugin System & Auto-Continue ⚡

A lightweight, update-proof plugin framework and suite of enhancements for **Claude Desktop for Linux** (AppImage / Debian).

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20(AppImage%2FDeb)-orange.svg)

---

## ⚡ One-Liner Install & Setup

Run this single command in your terminal to install the plugin loader, the Auto-Continue plugin, and patch your installed Claude Desktop AppImage:

```bash
curl -fsSL https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/install.sh | bash
```

---

## 🔄 One-Liner Repatch (After Claude Desktop Updates)

Whenever you update or download a new version of `Claude_Desktop.AppImage`, run:

```bash
patch-claude-desktop.sh
```
*(Or via remote one-liner without having the script in `$PATH`:)*
```bash
curl -fsSL https://raw.githubusercontent.com/Bluscream/claude-desktop-plugin-system/main/scripts/patch-claude-desktop.sh | bash
```

---

## 🌟 Highlights

* **Decoupled Architecture**: All your plugins and customization logic live cleanly in `~/.config/Claude/plugins/` (outside the app binary).
* **Update-Proof (3-Second Repatching)**: When Claude Desktop updates, simply run the patch script. It injects a 1-line hook into `app.asar` without needing to recreate or re-write your plugins.
* **Low CPU / Non-Blocking**: Throttled AppImage repacking using multi-core limits (`2` cores) and fast `zstd` compression with `nice` and `ionice` priority.
* **Universal Plugin Loader**: Automatically loads and injects all `.js` scripts in `~/.config/Claude/plugins/` into Claude's WebContents upon page load.

---

## 📦 Bundled Plugins

### 1. `auto-continue.js` — Auto-Continue Assistant
* **Collapsible & Draggable UI**: Collapses into a sleek 32px fast-forward spark icon (`⏩`) with terracotta active glow; smoothly expands on hover or input focus.
* **Position Persistence**: Drag anywhere on screen; coordinates are remembered across restarts.
* **Custom Phrase Input**: Editable prompt phrase (e.g. `Continue`, `Go on`, `Please proceed to the next step`).
* **Delay Selector**: Select between `2s`, `3s`, `5s`, `10s`, or `15s` before auto-continuing.
* **Live Countdown Badge**: Displays `⏳ In 5s [Cancel]` giving you one-click abort before submission.
* **Typing & Focus Abort Guard**: Automatically cancels if you click into the chatbox or start typing manually.
* **Runaway Guard**: Caps consecutive automatic triggers to prevent loops.

---

## 🛠️ Developing Custom Plugins

To create a new plugin, simply create a new `.js` file inside `~/.config/Claude/plugins/`:

```javascript
// ~/.config/Claude/plugins/my-custom-plugin.js
(function() {
  console.log('[MyCustomPlugin] Loaded into Claude Desktop!');
  
  // Access the DOM, add custom styles, or hook events
  const style = document.createElement('style');
  style.textContent = `
    /* Your custom CSS enhancements */
  `;
  document.head.appendChild(style);
})();
```

Any `.js` file placed in `~/.config/Claude/plugins/` is automatically executed in the web context when Claude loads.

---

## 📄 License

MIT © [Bluscream](https://github.com/Bluscream)

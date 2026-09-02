// Claude Desktop Universal Plugin Loader (Cross-Platform)
// Supports Linux, Windows, and macOS
// Loaded via index.pre.js / index.js inside Electron Main Process

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

// Universal user directory:
// Linux:   ~/.config/Claude/plugins
// Windows: %APPDATA%\Claude\plugins
// macOS:   ~/Library/Application Support/Claude/plugins
const PLUGINS_DIR = path.join(app.getPath('userData'), 'plugins');

function getPluginFiles() {
  if (!fs.existsSync(PLUGINS_DIR)) return [];
  try {
    return fs.readdirSync(PLUGINS_DIR)
      .filter(file => file.endsWith('.js') && file !== 'loader.js')
      .map(file => path.join(PLUGINS_DIR, file));
  } catch (err) {
    console.error('[ClaudePluginLoader] Failed to read plugins directory:', err);
    return [];
  }
}

function injectPluginsIntoContents(contents) {
  if (!contents || contents.isDestroyed()) return;

  const url = contents.getURL() || '';
  // Skip devtools windows
  if (url.startsWith('devtools://')) return;

  const plugins = getPluginFiles();
  for (const pluginPath of plugins) {
    try {
      const code = fs.readFileSync(pluginPath, 'utf8');
      const filename = path.basename(pluginPath);
      contents.executeJavaScript(`
        try {
          (function() {
            ${code}
          })();
        } catch (e) {
          console.error('[ClaudePluginLoader] Runtime error in plugin ${filename}:', e);
        }
      `).catch(err => {
        // Can happen if page navigates while executing; ignore safely
      });
    } catch (err) {
      console.error(`[ClaudePluginLoader] Failed reading ${pluginPath}:`, err);
    }
  }
}

function registerLoader() {
  app.on('web-contents-created', (event, contents) => {
    contents.on('did-finish-load', () => {
      injectPluginsIntoContents(contents);
    });
    contents.on('dom-ready', () => {
      injectPluginsIntoContents(contents);
    });
  });
}

// Initialize
try {
  registerLoader();
  console.log('[ClaudePluginLoader] Initialized successfully. Watching directory:', PLUGINS_DIR);
} catch (e) {
  console.error('[ClaudePluginLoader] Error initializing:', e);
}

module.exports = {
  injectPluginsIntoContents,
  getPluginFiles,
};

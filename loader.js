// Claude Desktop Universal Plugin Loader (Cross-Platform)
// Supports Linux, Windows, and macOS
// Loaded via index.pre.js / index.js inside Electron Main Process
//
// Two kinds of plugin are supported:
//   *.main.js  -> require()d once here, in the ELECTRON MAIN PROCESS.
//                 Use for anything that must touch Electron APIs, the app
//                 object, session/network internals, or outbound headers.
//   *.js       -> read and injected into every page's RENDERER via
//                 executeJavaScript. Use for anything that touches the DOM.
//
// Main plugins load first, and are loaded exactly once at startup, so they can
// patch APIs before the app's own code observes them.

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

// Universal user directory:
// Linux:   ~/.config/Claude/plugins
// Windows: %APPDATA%\Claude\plugins
// macOS:   ~/Library/Application Support/Claude/plugins
const PLUGINS_DIR = path.join(app.getPath('userData'), 'plugins');

function listPluginFiles() {
  if (!fs.existsSync(PLUGINS_DIR)) return { main: [], renderer: [] };
  try {
    const files = fs.readdirSync(PLUGINS_DIR)
      .filter(file => file.endsWith('.js') && file !== 'loader.js')
      .sort();
    return {
      main: files.filter(f => f.endsWith('.main.js')).map(f => path.join(PLUGINS_DIR, f)),
      renderer: files.filter(f => !f.endsWith('.main.js')).map(f => path.join(PLUGINS_DIR, f)),
    };
  } catch (err) {
    console.error('[ClaudePluginLoader] Failed to read plugins directory:', err);
    return { main: [], renderer: [] };
  }
}

// Backwards-compatible: callers of the old API get the renderer set, which is
// what this function always meant.
function getPluginFiles() {
  return listPluginFiles().renderer;
}

function loadMainPlugins() {
  for (const pluginPath of listPluginFiles().main) {
    try {
      require(pluginPath);
      console.log('[ClaudePluginLoader] main plugin loaded:', path.basename(pluginPath));
    } catch (err) {
      console.error(`[ClaudePluginLoader] main plugin failed ${pluginPath}:`, err);
    }
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
  loadMainPlugins();
  registerLoader();
  console.log('[ClaudePluginLoader] Initialized successfully. Watching directory:', PLUGINS_DIR);
} catch (e) {
  console.error('[ClaudePluginLoader] Error initializing:', e);
}

module.exports = {
  injectPluginsIntoContents,
  getPluginFiles,
  listPluginFiles,
  loadMainPlugins,
};

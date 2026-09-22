// Version Spoof — Claude Desktop (MAIN process plugin)
//
// Overrides Electron's app.getVersion() so the app reports a different version
// number than the one baked into its package.json.
//
// WHAT THIS ACTUALLY CHANGES
// --------------------------
// app.getVersion() is the single source for the version the app tells Anthropic
// about. In the bundle it feeds:
//
//   {"anthropic-client-platform":"desktop_app",
//    "anthropic-client-app":"com.anthropic.claudefordesktop",
//    "anthropic-client-version": app.getVersion(), ...}
//
// ...the OAuth authorize call's headers, and the
// `anthropic-client-version: <v>` line handed to spawned sub-processes.
// It also drives the client-side `availableInVersion` feature gates that the
// settings system uses to decide which options to show.
//
// WHAT THIS DOES *NOT* DO
// -----------------------
// It does NOT unlock models such as Opus 5.5. Model availability is not a
// version comparison — the client greys out any model ID that is missing from
// the Claude Code runtime compiled into this app. Desktop 2.2553.1 embeds
// claude-code/0.3.275, and the string `claude-opus-5-5` does not occur anywhere
// in its bundle. No version string can conjure a model the binary cannot name.
// Only a build that actually ships the model ID will offer it.
//
// CONFIG:  ~/.config/Claude/plugins/version-spoof.config.json
//   { "enabled": false, "version": "2.2553.1" }
// Created with defaults (disabled) on first run. Restart Claude to apply.

const { app } = require('electron');
const path = require('path');
const fs = require('fs');

const TAG = '[VersionSpoof]';
const CONFIG_PATH = path.join(app.getPath('userData'), 'plugins', 'version-spoof.config.json');

// Electron versions are compared segment-wise elsewhere in the app, so keep to
// a plain dotted numeric form. Anything else is rejected rather than shipped to
// the server, where a malformed value could fail in non-obvious ways.
const VERSION_RE = /^\d+(\.\d+){1,3}$/;

const DEFAULTS = {
  enabled: false,
  version: '2.2553.1',
};

function readConfig() {
  try {
    if (!fs.existsSync(CONFIG_PATH)) {
      const seeded = { ...DEFAULTS, version: app.getVersion() };
      fs.writeFileSync(CONFIG_PATH, JSON.stringify(seeded, null, 2) + '\n', 'utf8');
      console.log(`${TAG} wrote default config to ${CONFIG_PATH} (disabled)`);
      return seeded;
    }
    return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')) };
  } catch (err) {
    console.error(`${TAG} config unreadable, staying inert:`, err);
    return { ...DEFAULTS, enabled: false };
  }
}

function apply() {
  const cfg = readConfig();
  const real = app.getVersion();

  if (!cfg.enabled) {
    console.log(`${TAG} disabled; reporting real version ${real}`);
    return;
  }
  if (typeof cfg.version !== 'string' || !VERSION_RE.test(cfg.version)) {
    console.error(`${TAG} refusing to spoof: ${JSON.stringify(cfg.version)} is not a dotted numeric version`);
    return;
  }
  if (cfg.version === real) {
    console.log(`${TAG} configured version matches real version ${real}; nothing to do`);
    return;
  }

  // Keep the genuine value reachable for anything that needs ground truth
  // (crash reports, bug reports, our own logging).
  app.getRealVersion = () => real;

  app.getVersion = () => cfg.version;

  console.log(`${TAG} active: reporting ${cfg.version} (real: ${real})`);
}

try {
  apply();
} catch (err) {
  console.error(`${TAG} failed to apply:`, err);
}

module.exports = { apply, readConfig, CONFIG_PATH };

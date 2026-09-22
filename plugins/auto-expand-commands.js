// Auto-Expand Commands — Claude Desktop (RENDERER plugin)
//
// Automatically expands the collapsed "Ran N commands" summary when N is at or
// above a threshold (default 2), so multi-command steps are readable without a
// click.
//
// The chat UI is served remotely and its class names are build-generated, so
// this deliberately keys on the visible *text* ("Ran 3 commands") and then
// walks up to the nearest genuinely clickable ancestor, rather than hardcoding
// selectors that would rot on the next deploy.
//
// It clicks each toggle at most once, ever. If you collapse one by hand it
// stays collapsed — the plugin will not fight you.
//
// CONFIG (localStorage key `claude_auto_expand_settings`):
//   { "enabled": true, "minCommands": 2 }

(function () {
  const PLUGIN_ID = 'claude-auto-expand-commands';
  if (window[PLUGIN_ID]) return; // already initialised in this frame
  window[PLUGIN_ID] = true;

  const STORAGE_KEY = 'claude_auto_expand_settings';
  const defaults = { enabled: true, minCommands: 2 };

  let settings = { ...defaults };
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) settings = { ...defaults, ...JSON.parse(raw) };
  } catch (e) {
    /* corrupt or unavailable storage: fall back to defaults */
  }

  // "Ran 2 commands", "Ran 12 commands". Singular ("Ran 1 command") never
  // matches the >= 2 threshold, but is parsed anyway so the regex stays honest.
  const LABEL_RE = /^Ran\s+(\d+)\s+commands?$/i;

  // Toggles we have already acted on. WeakSet so detached nodes are collectable
  // and so a manual re-collapse is never undone.
  const handled = new WeakSet();

  function isVisible(el) {
    if (!el.isConnected) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  // Walk up from the text node's element to the thing that actually toggles.
  // Prefer explicit semantics; fall back to a pointer cursor; give up rather
  // than click a random container.
  function findToggle(el) {
    let node = el;
    for (let depth = 0; node && depth < 6; depth++, node = node.parentElement) {
      if (node.hasAttribute && node.hasAttribute('aria-expanded')) return node;
      const role = node.getAttribute && node.getAttribute('role');
      if (node.tagName === 'BUTTON' || role === 'button') return node;
      if (node.tagName === 'SUMMARY') return node;
      try {
        if (getComputedStyle(node).cursor === 'pointer') return node;
      } catch (e) {
        /* element went away mid-walk */
      }
    }
    return null;
  }

  function isCollapsed(toggle) {
    const expanded = toggle.getAttribute('aria-expanded');
    if (expanded !== null) return expanded === 'false';
    // <details>/<summary> pattern
    const details = toggle.closest && toggle.closest('details');
    if (details) return !details.open;
    // No signal available — treat first sighting as collapsed. The WeakSet
    // guarantees we only ever act on it once, so a wrong guess costs one click,
    // not a toggle loop.
    return true;
  }

  function scan(root) {
    if (!settings.enabled) return;

    const scope = root && root.querySelectorAll ? root : document;
    let candidates;
    try {
      candidates = scope.querySelectorAll('button, [role="button"], [aria-expanded], summary, div, span');
    } catch (e) {
      return;
    }

    for (const el of candidates) {
      // Only consider elements whose *own* rendered text is the label, so we
      // don't match a whole transcript container that happens to contain it.
      const text = (el.textContent || '').trim();
      if (text.length > 40) continue;
      const m = LABEL_RE.exec(text);
      if (!m) continue;

      const count = parseInt(m[1], 10);
      if (!Number.isFinite(count) || count < settings.minCommands) continue;

      const toggle = findToggle(el);
      if (!toggle || handled.has(toggle)) continue;
      if (!isVisible(toggle) || !isCollapsed(toggle)) {
        // Mark already-expanded toggles as handled too, so that a later manual
        // collapse is respected rather than re-expanded on the next mutation.
        if (toggle) handled.add(toggle);
        continue;
      }

      handled.add(toggle);
      try {
        toggle.click();
        console.log(`[AutoExpandCommands] expanded "${text}"`);
      } catch (e) {
        console.error('[AutoExpandCommands] click failed:', e);
      }
    }
  }

  // Coalesce bursts of mutations into one scan per frame.
  let queued = false;
  function schedule(root) {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      try {
        scan(root);
      } catch (e) {
        console.error('[AutoExpandCommands] scan failed:', e);
      }
    });
  }

  const observer = new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.addedNodes && m.addedNodes.length) {
        schedule(document);
        return;
      }
    }
  });

  function start() {
    observer.observe(document.body, { childList: true, subtree: true });
    schedule(document); // catch anything already on screen
    console.log('[AutoExpandCommands] active (minCommands=' + settings.minCommands + ')');
  }

  if (document.body) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }

  // Small console API for tuning without editing the file.
  window.claudeAutoExpand = {
    get settings() { return { ...settings }; },
    set(patch) {
      settings = { ...settings, ...patch };
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
      } catch (e) {
        console.error('[AutoExpandCommands] could not persist settings:', e);
      }
      return { ...settings };
    },
    rescan() { scan(document); },
  };
})();

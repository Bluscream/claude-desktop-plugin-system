// Auto-Continue Plugin for Claude Desktop
// Injected into Claude WebContents

(function() {
  const PLUGIN_ID = 'claude-auto-continue-plugin';
  if (document.getElementById(PLUGIN_ID)) {
    return; // Already initialized in this frame/page
  }

  // Configuration & State (Single unified storage object)
  const STORAGE_KEY = 'claude_auto_continue_settings';

  const defaultSettings = {
    enabled: false,
    delaySeconds: 5,
    phrase: 'Continue',
    maxConsecutive: 10,
    position: null, // { top: number, left: number }
  };

  let settings = { ...defaultSettings };
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      settings = { ...defaultSettings, ...JSON.parse(saved) };
    }
  } catch (e) {
    console.warn('[AutoContinue] Failed loading settings:', e);
  }

  function saveSettings() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch (e) {}
  }

  let isGenerating = false;
  let countdownTimer = null;
  let countdownRemaining = 0;
  let consecutiveCount = 0;
  let lastTriggerTime = 0;

  // UI Injection
  const container = document.createElement('div');
  container.id = PLUGIN_ID;

  // Initial Position
  const pos = settings.position;
  const initialTop = pos && typeof pos.top === 'number' ? `${pos.top}px` : 'auto';
  const initialLeft = pos && typeof pos.left === 'number' ? `${pos.left}px` : 'auto';
  const initialBottom = pos && typeof pos.top === 'number' ? 'auto' : '80px';
  const initialRight = pos && typeof pos.left === 'number' ? 'auto' : '24px';

  container.innerHTML = `
    <style>
      #claude-auto-continue-plugin {
        position: fixed;
        top: ${initialTop};
        left: ${initialLeft};
        bottom: ${initialBottom};
        right: ${initialRight};
        z-index: 99999;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        font-size: 12px;
        color: #e5e5e5;
        user-select: none;
      }
      .ac-container {
        display: flex;
        align-items: center;
        background: rgba(28, 28, 30, 0.88);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        border: 1px solid rgba(255, 255, 255, 0.14);
        border-radius: 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45);
        cursor: grab;
        padding: 5px;
        transition: width 0.28s cubic-bezier(0.16, 1, 0.3, 1),
                    padding 0.28s cubic-bezier(0.16, 1, 0.3, 1),
                    border-color 0.2s ease,
                    background 0.2s ease,
                    box-shadow 0.2s ease;
        overflow: hidden;
        white-space: nowrap;
        width: 32px;
        height: 32px;
        box-sizing: border-box;
      }
      .ac-container.ac-active-glow {
        border-color: rgba(217, 119, 87, 0.6);
        box-shadow: 0 0 14px rgba(217, 119, 87, 0.3), 0 8px 32px rgba(0, 0, 0, 0.45);
      }
      .ac-container:hover,
      .ac-container.ac-expanded,
      .ac-container.ac-counting {
        width: auto;
        height: auto;
        padding: 6px 12px;
        cursor: default;
        background: rgba(34, 34, 36, 0.96);
        border-color: rgba(217, 119, 87, 0.5);
      }
      .ac-container.is-dragging {
        cursor: grabbing !important;
        opacity: 0.9;
        transition: none !important;
      }
      /* Collapsed Icon */
      .ac-icon-handle {
        display: flex;
        align-items: center;
        justify-content: center;
        min-width: 22px;
        height: 22px;
        cursor: grab;
        color: #a1a1aa;
        transition: color 0.15s ease;
      }
      .ac-container.ac-active-glow .ac-icon-handle {
        color: #d97757;
      }
      .ac-icon-handle svg {
        width: 16px;
        height: 16px;
        fill: currentColor;
      }
      /* Expanded Content */
      .ac-content {
        display: flex;
        align-items: center;
        gap: 8px;
        opacity: 0;
        max-width: 0;
        pointer-events: none;
        transition: opacity 0.2s ease 0.05s, max-width 0.28s ease;
      }
      .ac-container:hover .ac-content,
      .ac-container.ac-expanded .ac-content,
      .ac-container.ac-counting .ac-content {
        opacity: 1;
        max-width: 450px;
        pointer-events: auto;
      }
      .ac-toggle-label {
        display: flex;
        align-items: center;
        gap: 6px;
        cursor: pointer;
        font-weight: 500;
        color: #d1d1d1;
      }
      .ac-checkbox {
        appearance: none;
        width: 14px;
        height: 14px;
        border: 1.5px solid #71717a;
        border-radius: 4px;
        outline: none;
        cursor: pointer;
        background: transparent;
        position: relative;
        transition: all 0.15s ease;
      }
      .ac-checkbox:checked {
        background-color: #d97757; /* Claude Terracotta Accent */
        border-color: #d97757;
      }
      .ac-checkbox:checked::after {
        content: '';
        position: absolute;
        left: 4px;
        top: 1px;
        width: 4px;
        height: 8px;
        border: solid white;
        border-width: 0 2px 2px 0;
        transform: rotate(45deg);
      }
      .ac-phrase-input {
        background: rgba(255, 255, 255, 0.08);
        border: 1px solid rgba(255, 255, 255, 0.12);
        color: #e5e5e5;
        border-radius: 6px;
        padding: 2px 6px;
        font-size: 11px;
        width: 75px;
        outline: none;
        transition: border-color 0.15s, width 0.2s ease;
      }
      .ac-phrase-input:focus {
        border-color: #d97757;
        width: 120px;
      }
      .ac-delay-select {
        background: rgba(255, 255, 255, 0.08);
        border: 1px solid rgba(255, 255, 255, 0.12);
        color: #d1d1d1;
        border-radius: 6px;
        padding: 2px 4px;
        font-size: 11px;
        cursor: pointer;
        outline: none;
      }
      .ac-delay-select option {
        background: #202022;
        color: #e5e5e5;
      }
      .ac-countdown-badge {
        display: none;
        background: rgba(217, 119, 87, 0.22);
        border: 1px solid #d97757;
        color: #ff9b7a;
        padding: 2px 8px;
        border-radius: 10px;
        font-weight: 600;
        animation: ac-pulse 1s infinite alternate;
      }
      .ac-cancel-btn {
        background: transparent;
        border: none;
        color: #a1a1aa;
        cursor: pointer;
        font-size: 11px;
        text-decoration: underline;
        padding: 0 2px;
      }
      .ac-cancel-btn:hover {
        color: #ffffff;
      }
      @keyframes ac-pulse {
        0% { opacity: 0.8; }
        100% { opacity: 1; }
      }
    </style>
    <div class="ac-container ${settings.enabled ? 'ac-active-glow' : ''}" id="ac-container">
      <div class="ac-icon-handle" id="ac-drag-handle" title="Drag to move | Hover to configure">
        <svg viewBox="0 0 24 24">
          <path d="M5 4l10 8-10 8V4zm11 0l6 8-6 8V4z" />
        </svg>
      </div>
      <div class="ac-content" id="ac-content">
        <label class="ac-toggle-label" title="Auto-Continue (Enable/Disable)">
          <input type="checkbox" class="ac-checkbox" id="ac-enabled-check" ${settings.enabled ? 'checked' : ''} title="Auto-Continue (Enable/Disable)">
        </label>
        <input type="text" class="ac-phrase-input" id="ac-phrase-input" value="${settings.phrase}" title="Text to send automatically" placeholder="Phrase...">
        <select class="ac-delay-select" id="ac-delay-select" title="Delay before auto-continuing">
          <option value="2" ${settings.delaySeconds === 2 ? 'selected' : ''}>2s</option>
          <option value="3" ${settings.delaySeconds === 3 ? 'selected' : ''}>3s</option>
          <option value="5" ${settings.delaySeconds === 5 ? 'selected' : ''}>5s</option>
          <option value="10" ${settings.delaySeconds === 10 ? 'selected' : ''}>10s</option>
          <option value="15" ${settings.delaySeconds === 15 ? 'selected' : ''}>15s</option>
        </select>
        <div class="ac-countdown-badge" id="ac-countdown-badge">
          <span id="ac-countdown-text">In 5s</span>
          <button class="ac-cancel-btn" id="ac-cancel-btn" title="Cancel this auto-continue">Cancel</button>
        </div>
      </div>
    </div>
  `;

  document.body.appendChild(container);

  const mainWidget = document.getElementById('ac-container');
  const dragHandle = document.getElementById('ac-drag-handle');
  const checkEl = document.getElementById('ac-enabled-check');
  const phraseEl = document.getElementById('ac-phrase-input');
  const delayEl = document.getElementById('ac-delay-select');
  const badgeEl = document.getElementById('ac-countdown-badge');
  const countTextEl = document.getElementById('ac-countdown-text');
  const cancelBtn = document.getElementById('ac-cancel-btn');

  // Keep expanded while typing in phrase input
  phraseEl.addEventListener('focus', () => mainWidget.classList.add('ac-expanded'));
  phraseEl.addEventListener('blur', () => mainWidget.classList.remove('ac-expanded'));

  checkEl.addEventListener('change', (e) => {
    settings.enabled = e.target.checked;
    if (settings.enabled) {
      mainWidget.classList.add('ac-active-glow');
    } else {
      mainWidget.classList.remove('ac-active-glow');
      cancelAutoContinue();
    }
    saveSettings();
  });

  phraseEl.addEventListener('input', (e) => {
    settings.phrase = e.target.value.trim() || 'Continue';
    saveSettings();
  });

  delayEl.addEventListener('change', (e) => {
    settings.delaySeconds = parseInt(e.target.value, 10) || 5;
    saveSettings();
  });

  cancelBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    cancelAutoContinue();
  });

  // Draggable logic
  let isDragging = false;
  let dragStartX = 0;
  let dragStartY = 0;
  let elemStartX = 0;
  let elemStartY = 0;

  dragHandle.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return; // Left click only
    isDragging = true;
    mainWidget.classList.add('is-dragging');

    const rect = container.getBoundingClientRect();
    dragStartX = e.clientX;
    dragStartY = e.clientY;
    elemStartX = rect.left;
    elemStartY = rect.top;

    e.preventDefault();
  });

  document.addEventListener('mousemove', (e) => {
    if (!isDragging) return;

    const dx = e.clientX - dragStartX;
    const dy = e.clientY - dragStartY;

    let newX = elemStartX + dx;
    let newY = elemStartY + dy;

    // Viewport boundaries
    newX = Math.max(10, Math.min(window.innerWidth - 60, newX));
    newY = Math.max(10, Math.min(window.innerHeight - 60, newY));

    container.style.left = `${newX}px`;
    container.style.top = `${newY}px`;
    container.style.right = 'auto';
    container.style.bottom = 'auto';
  });

  document.addEventListener('mouseup', () => {
    if (isDragging) {
      isDragging = false;
      mainWidget.classList.remove('is-dragging');

      // Save coordinates directly into settings
      const rect = container.getBoundingClientRect();
      settings.position = {
        left: Math.round(rect.left),
        top: Math.round(rect.top),
      };
      saveSettings();
    }
  });

  function cancelAutoContinue() {
    if (countdownTimer) {
      clearInterval(countdownTimer);
      countdownTimer = null;
    }
    mainWidget.classList.remove('ac-counting');
    badgeEl.style.display = 'none';
  }

  // Find input element in Claude web interface
  function getInputElement() {
    return document.querySelector('div.ProseMirror[contenteditable="true"]') ||
           document.querySelector('div[contenteditable="true"]') ||
           document.querySelector('textarea[placeholder*="Reply"]');
  }

  // Find stop button if currently streaming/thinking
  function getStopButton() {
    return document.querySelector('button[aria-label*="Stop"]') ||
           document.querySelector('button[aria-label*="stop"]') ||
           document.querySelector('button svg.animate-spin');
  }

  // Find direct continue generating button if present
  function getContinueButton() {
    const buttons = Array.from(document.querySelectorAll('button'));
    return buttons.find(b => {
      const txt = (b.innerText || b.textContent || '').trim().toLowerCase();
      return txt === 'continue' || txt === 'continue generating' || txt === 'resume';
    });
  }

  // Find send message button
  function getSendButton() {
    return document.querySelector('button[aria-label*="Send message"]') ||
           document.querySelector('button[aria-label*="Send Message"]') ||
           document.querySelector('button[aria-label*="send"]') ||
           document.querySelector('fieldset button[type="submit"]');
  }

  function insertTextAndSubmit(text) {
    const directBtn = getContinueButton();
    if (directBtn) {
      console.log('[AutoContinue] Clicking direct continue button');
      directBtn.click();
      return true;
    }

    const input = getInputElement();
    if (!input) {
      console.warn('[AutoContinue] Input element not found');
      return false;
    }

    input.focus();
    // For contenteditable ProseMirror
    if (input.isContentEditable) {
      input.innerHTML = `<p>${text}</p>`;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      input.value = text;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    setTimeout(() => {
      const sendBtn = getSendButton();
      if (sendBtn && !sendBtn.disabled) {
        sendBtn.click();
        console.log('[AutoContinue] Sent message via submit button');
      } else {
        // Fallback Enter keypress
        const enterEvt = new KeyboardEvent('keydown', {
          key: 'Enter',
          code: 'Enter',
          keyCode: 13,
          which: 13,
          bubbles: true,
          cancelable: true,
        });
        input.dispatchEvent(enterEvt);
        console.log('[AutoContinue] Sent message via Enter key event');
      }
    }, 150);

    return true;
  }

  function startCountdown() {
    cancelAutoContinue();
    countdownRemaining = settings.delaySeconds;
    mainWidget.classList.add('ac-counting');
    badgeEl.style.display = 'inline-flex';
    countTextEl.textContent = `In ${countdownRemaining}s`;

    countdownTimer = setInterval(() => {
      countdownRemaining -= 1;
      if (countdownRemaining <= 0) {
        cancelAutoContinue();
        consecutiveCount += 1;
        lastTriggerTime = Date.now();
        insertTextAndSubmit(settings.phrase || 'Continue');
      } else {
        countTextEl.textContent = `In ${countdownRemaining}s`;
      }
    }, 1000);
  }

  // Cancel countdown if user manually interacts with chat box
  document.addEventListener('keydown', (e) => {
    const input = getInputElement();
    if (input && (e.target === input || input.contains(e.target))) {
      if (countdownTimer) {
        console.log('[AutoContinue] Cancelled due to user typing');
        cancelAutoContinue();
      }
      consecutiveCount = 0; // Reset consecutive counter on human interaction
    }
  });

  // Observe generation status
  const observer = new MutationObserver(() => {
    if (!settings.enabled) return;

    const stopBtn = getStopButton();
    const currentlyGenerating = !!stopBtn;

    // Transition from generating -> stopped/idle
    if (isGenerating && !currentlyGenerating) {
      isGenerating = false;
      const timeSinceLast = Date.now() - lastTriggerTime;
      if (timeSinceLast > 3000 && consecutiveCount < settings.maxConsecutive) {
        console.log('[AutoContinue] Generation finished. Triggering countdown...');
        setTimeout(() => {
          if (!getStopButton()) {
            startCountdown();
          }
        }, 500);
      }
    } else if (currentlyGenerating) {
      isGenerating = true;
      if (countdownTimer) {
        cancelAutoContinue();
      }
    }
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['disabled', 'aria-label', 'class'],
  });

  console.log('[AutoContinue] Unified storage plugin active.');
})();

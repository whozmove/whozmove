// The line under the header while Whozmove sets itself up, and when a new version is out (install.js says what it
// says), in its place between the
// header and a new conversation's card (#install, panel.html), where it takes the header's room from the list as a
// card there does (base.css). It eases open under the header, the rows moving down with it, and folds away the same
// way, with the strips' helpers (strips.js); when what it says changes, the old words fade before the new come in, the
// line easing to its new height. Its button asks the app (`install`, naming the action: the app holds the commands and
// the address) and waits until the app has done it (Copy Command, which only puts a command on the clipboard, says
// Copied a moment instead); its × puts the line away until things change. Saying all went
// well, it has a tick, and puts itself away once it has been in sight a few seconds, folding as it does for its ×.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({ install: null, installAway: store.get('installAway', {}) });
const installEl = document.getElementById('install');
const il = {
  shown: null,    // the line on show (installLine's: {text, button, action, close, busy, key, since, …}), or null
  moving: false,  // growing in, folding away or changing its words: what comes meanwhile is drawn once it's done
  at: 0,          // when its words came, as a press that comes too soon after doesn't count (FRESH_MS)
  seenAt: 0,      // since when a line that says all went well has been in sight, or 0
};
// How long a line that says all went well is in sight before it puts itself away.
const INSTALL_DONE_MS = 4000;

function installHTML(line) {
  return `<div class="notice in-line">${line.done ? DONE_ICON : ''}<span class="notice-text">${esc(line.text)}</span>`
    + (line.button ? `<button class="notice-button" data-action="${esc(line.action)}"`
      + `${line.session ? ` data-session="${esc(line.session)}"` : ''}${line.busy ? ' disabled' : ''}>`
      + `${esc(line.button)}</button>` : '')
    + (line.close ? `<button class="q-close" title="${esc(line.closeTitle || 'Not now')}">×</button>` : '') + '</div>';
}

const sameWords = (a, b) => a.text === b.text && a.button === b.button && a.close === b.close && a.done === b.done
  && a.session === b.session;
// No motion under reduced motion, nor out of sight, while the panel is folded into the cat.
const installQuiet = () => calm.matches || document.body.classList.contains('collapsed');

function installDraw() {
  if (il.moving) return;
  const line = installLine(state.install, state.installAway), was = il.shown;
  if (!line) {
    if (was) installFold();
    return;
  }
  il.shown = line;
  if (!line.done || (was && !sameWords(was, line))) il.seenAt = 0;
  if (!was) return installGrow(line);
  if (!sameWords(was, line)) return installSwap(line);
  installEl.querySelector('.notice-button')?.toggleAttribute('disabled', line.busy);
}

// A line that says all went well is put away once it has been in sight a few seconds, as its × would, so it folds the
// same way: the time counts only while the panel is open on its list side, so you never miss it folded or turned over.
// What comes meanwhile stops it. Looked at with each update from the app, every second.
function installDoneLater() {
  if (!il.shown?.done || il.moving) return;
  if (document.body.classList.contains('collapsed') || state.turned) {
    il.seenAt = 0;
    return;
  }
  il.seenAt ||= Date.now();
  if (Date.now() - il.seenAt >= INSTALL_DONE_MS) installPutAway();
}

function installPutAway() {
  state.installAway = putAway(state.installAway, installLine(state.install, state.installAway));
  store.set('installAway', state.installAway);
  installDraw();
}

// A button's words, changed: the old fade, then the new come in, as the line's own words do (installSwap).
function installLabel(button, words) {
  if (button.textContent === words) return;
  if (installQuiet()) {
    button.textContent = words;
    return;
  }
  button.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, easing: 'ease', fill: 'forwards' }).finished
    .then(() => {
      button.textContent = words;
      button.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: MORPH_EASE });
    }, () => { button.textContent = words; });
}

function installSettled() {
  il.moving = false;
  installDraw();
}

function installGrow(line) {
  installEl.innerHTML = installHTML(line);
  installEl.hidden = false;
  il.at = Date.now();
  if (installQuiet()) return reportHeight();
  il.moving = true;
  growIn(installEl, 0, installSettled);
}

// It fades as it eases away to nothing, the rows coming up with it; then it's out of the way, and the header's room is
// the list's again.
function installFold() {
  il.shown = null;
  const done = () => {
    installEl.hidden = true;
    installEl.innerHTML = '';
    reportHeight();
    syncHover();
    installSettled();
  };
  if (installQuiet()) return done();
  il.moving = true;
  foldAway(installEl, done);
}

// New words: the old fade first, then the new come in, lifting 3px, as the line eases to its new height.
function installSwap(line) {
  const old = installEl.firstElementChild;
  const put = () => {
    const before = installEl.offsetHeight;
    installEl.innerHTML = installHTML(line);
    il.at = Date.now();
    if (installQuiet()) {
      reportHeight();
      return installSettled();
    }
    easeHeight(installEl, before);
    installEl.firstElementChild.animate([{ opacity: 0, transform: 'translateY(3px)' },
                                         { opacity: 1, transform: 'none' }], { duration: 300, easing: MORPH_EASE })
      .finished.then(installSettled, installSettled);
  };
  if (installQuiet() || !old) return put();
  il.moving = true;
  old.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 150, easing: 'ease', fill: 'forwards' })
    .finished.then(put, put);
}

// mousedown, as the list's presses are. The button waits from the press until the app says how it went (but Copy
// Command and Take me there, which change nothing of setting up); the × keeps the line away for as long as things
// stand as they do, a new version's until a newer one.
installEl.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  if (il.moving || Date.now() - il.at < FRESH_MS) return;
  const go = e.target.closest('.notice-button');
  if (go) {
    if (go.disabled) return;
    // Take me there brings the session forward, as a press on its row does (the reader's does too).
    if (go.dataset.action === 'open') {
      const s = state.last.sessions?.find((one) => one.sessionId === go.dataset.session);
      if (s) openSession(s);
      return;
    }
    // Copy Command says it's copied, a moment, and stays pressable: it keeps its width, so nothing beside it moves,
    // and its words cross-fade.
    if (go.dataset.action === 'copyUpgrade') {
      native({ type: 'install', action: 'copyUpgrade' });
      go.style.minWidth = `${go.offsetWidth}px`;
      installLabel(go, 'Copied');
      setTimeout(() => { if (go.isConnected) installLabel(go, il.shown?.button || 'Copy Command'); }, 2000);
      return;
    }
    go.disabled = true;
    native({ type: 'install', action: go.dataset.action });
    return;
  }
  if (!e.target.closest('.q-close')) return;
  // A new version put away is kept in Whozmove's folder, so it stays away across launches until a newer one.
  if (il.shown?.key === 'update') native({ type: 'install', action: 'putAwayUpdate', version: il.shown.version });
  installPutAway();
});

// ---- What the app calls ----

// How Whozmove's setting itself up stands: {state, detail, since, busy, reload} (modules/install/README.md has each
// state, and what `reload` holds), whenever that changes, as a press sets something going, and when the page loads.
window.setInstall = (found) => {
  state.install = found && typeof found === 'object' ? found : null;
  installDraw();
};

core.strips.push('install');
core.updates.push(installDoneLater);
core.pointerTargets.push('#install .notice-button:not(:disabled)');

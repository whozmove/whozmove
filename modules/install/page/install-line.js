// The line under the header while Whozmove sets itself up (install.js says what it says), in its place between the
// header and a new conversation's card (#install, panel.html), where it takes the header's room from the list as a
// card there does (base.css). It eases open under the header, the rows moving down with it, and folds away the same
// way, with the strips' helpers (strips.js); when what it says changes, the old words fade before the new come in, the
// line easing to its new height. Its button asks the app (`install`, naming the action: the app holds the commands and
// the address) and waits until the app has done it; its × puts the line away until things change. Saying all went
// well, it has a tick, and puts itself away a few seconds after, folding as it does for its ×.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({ install: null, installAway: store.get('installAway', {}) });
const installEl = document.getElementById('install');
const il = {
  shown: null,    // the line on show ({text, button, action, close, busy}), or null
  moving: false,  // growing in, folding away or changing its words: what comes meanwhile is drawn once it's done
  at: 0,          // when its words came, as a press that comes too soon after doesn't count (FRESH_MS)
  doneTimer: 0,   // while a line that says all went well waits to put itself away
};
// How long a line that says all went well shows before it puts itself away.
const INSTALL_DONE_MS = 4000;

function installHTML(line) {
  return `<div class="notice in-line">${line.done ? DONE_ICON : ''}<span class="notice-text">${esc(line.text)}</span>`
    + (line.button ? `<button class="notice-button" data-action="${esc(line.action)}"${line.busy ? ' disabled' : ''}>`
      + `${esc(line.button)}</button>` : '')
    + (line.close ? '<button class="q-close" title="Not now">×</button>' : '') + '</div>';
}

const sameWords = (a, b) => a.text === b.text && a.button === b.button && a.close === b.close && a.done === b.done;
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
  installDoneLater(line);
  if (!was) return installGrow(line);
  if (!sameWords(was, line)) return installSwap(line);
  installEl.querySelector('.notice-button')?.toggleAttribute('disabled', line.busy);
}

// A line that says all went well is put away a few seconds after it shows, as its × would, so it folds the same way;
// what comes meanwhile stops it.
function installDoneLater(line) {
  if (!line.done) {
    clearTimeout(il.doneTimer);
    il.doneTimer = 0;
    return;
  }
  if (il.doneTimer) return;
  il.doneTimer = setTimeout(() => {
    il.doneTimer = 0;
    if (!il.shown?.done) return;
    installPutAway();
  }, INSTALL_DONE_MS);
}

function installPutAway() {
  state.installAway = putAway(state.installAway, state.install);
  store.set('installAway', state.installAway);
  installDraw();
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

// mousedown, as the list's presses are. The button waits from the press until the app says how it went; the × keeps
// the line away for as long as things stand as they do.
installEl.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  if (il.moving || Date.now() - il.at < FRESH_MS) return;
  const go = e.target.closest('.notice-button');
  if (go) {
    if (go.disabled) return;
    go.disabled = true;
    native({ type: 'install', action: go.dataset.action });
    return;
  }
  if (!e.target.closest('.q-close')) return;
  installPutAway();
});

// ---- What the app calls ----

// How Whozmove's setting itself up stands: {state, detail, since, busy} (modules/install/README.md has each state),
// whenever that changes, as a press sets something going, and when the page loads.
window.setInstall = (found) => {
  state.install = found && typeof found === 'object' ? found : null;
  installDraw();
};

core.strips.push('install');
core.pointerTargets.push('#install .notice-button:not(:disabled)');

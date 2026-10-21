// A session running since before Whozmove's hooks went in, which shows only part of what it does until it reloads them
// (s.reload, the install module's): at its work line's start, that it shows in part, with Reload, which reloads it
// alone, its conversation kept as it is (`install`, {action: reload, sessionId}); once pressed, or the line's Reload
// Them, its row says it's waiting for its turn, or reloading, in the work line's place, as a step's note does. One left
// for you says what to type in it: one the panel couldn't type into (its tab isn't certain, say), with Try Again, and
// one whose reload Claude Code held back, with the command that takes it anyway. Pointed at, each says why.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const RELOAD_TIP = "Whozmove's plugin went into Claude Code after this session started. Reload it to see what it's "
  + 'doing here, and answer its requests: its conversation stays as it is.';

// What a reason says, as a sentence of its own.
const sentence = (text) => `${String(text || '').trim().replace(/[.!?]+$/, '')}.`;

function reloadHTML(row) {
  const r = row.s.reload, sid = esc(row.s.sessionId);
  if (r?.state === 'byHand') {
    const tip = r.held ? `${sentence(r.why)} Typing ${r.command} there reloads it anyway, and its next message reads `
      + 'the whole conversation again.' : `${sentence(r.why)} Type ${r.command} in its tab to see it in full.`;
    return `<div class="nopr reload${r.held ? '' : '" data-reload="' + sid}" title="${esc(tip)}">`
      + `<span class="pt">Shown in part: type ${esc(r.command)} in it</span>`
      + (r.held ? '' : '<span class="create-pr">Try Again</span>') + '</div>';
  }
  if (r?.state !== 'needed') return '';
  return `<div class="nopr reload" data-reload="${sid}" title="${esc(RELOAD_TIP)}">`
    + '<span class="pt">Shown in part</span><span class="create-pr">Reload</span></div>';
}

// What its row says once it's on its way, or null.
function reloadNote(s) {
  const now = s.reload?.state;
  return now === 'reloading' ? { text: 'Reloading Whozmove\'s plugin…', quiet: true }
    : now === 'waiting' ? { text: 'Waiting its turn to reload Whozmove\'s plugin', quiet: true } : null;
}

// ---- What it plugs into ----

// Reload waits to be seen before it takes a press, and does so again once it's back.
core.rowLooks.push((row) => {
  const key = 'reload:' + row.s.sessionId, r = row.s.reload;
  if (r?.state === 'needed' || (r?.state === 'byHand' && !r.held)) state.shownAt[key] ??= Date.now();
  else delete state.shownAt[key];
});
core.forgotten.prefixes.push('reload');
core.slots.workStart.push(reloadHTML);
core.rowNotes.push((row) => reloadNote(row.s));
core.presses.push(['.reload[data-reload]', (el, e) => {
  e.preventDefault();
  if (!justShown('reload:' + el.dataset.reload))
    native({ type: 'install', action: 'reload', sessionId: el.dataset.reload });
}]);
core.pointerTargets.push('.reload[data-reload]');

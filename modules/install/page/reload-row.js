// A session running since before Whozmove's hooks went in, which shows only part of what it does until it reloads them
// (s.reload, the install module's): at its work line's start, that it started before Whozmove's update, with Reload to
// see its steps, which reloads it
// alone, its conversation kept as it is (`install`, {action: reload, sessionId}); once pressed, or the line's Reload
// Them, its row says it's waiting for its turn, or reloading, in the work line's place, as a step's note does. One left
// for you says what to type in it: one the panel couldn't type into (its tab isn't certain, say), with Try Again, and
// one whose reload Claude Code held back, with the command that takes it anyway. Pointed at, each says why. A row shown
// briefly has no work line, so there it's the row's note, given only when nothing else is said on the row (an ask's
// bubble stays in front), as the line under the header names Reload on the row.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const RELOAD_TIP = "Whozmove's plugin went into Claude Code after this session started. Reload it to see what it's "
  + 'doing here, and answer its requests: its conversation stays as it is.';

// What a reason says, as a sentence of its own.
const sentence = (text) => `${String(text || '').trim().replace(/[.!?]+$/, '')}.`;

function reloadHTML(row, tag = 'div', button = 'Reload to see its steps') {
  const r = row.s.reload, sid = esc(row.s.sessionId);
  if (r?.state === 'byHand') {
    const tip = r.held ? `${sentence(r.why)} Typing ${r.command} there reloads it anyway, and its next message reads `
      + 'the whole conversation again.' : `${sentence(r.why)} Type ${r.command} in its tab to see it in full.`;
    return `<${tag} class="nopr reload${r.held ? '' : '" data-reload="' + sid}" title="${esc(tip)}">`
      + `<span class="pt">Started before Whozmove's update: type ${esc(r.command)} in it</span>`
      + (r.held ? '' : '<span class="button quiet create-pr">Try Again</span>') + `</${tag}>`;
  }
  if (r?.state !== 'needed') return '';
  return `<${tag} class="nopr reload" data-reload="${sid}" title="${esc(RELOAD_TIP)}">`
    + '<span class="pt">Started before Whozmove\'s update</span>'
    + `<span class="button quiet create-pr">${button}</span></${tag}>`;
}

// The same on a row shown briefly, as its note, or null: its button just Reload, so its words read whole, the tip saying
// why, and nothing at its end (no context ring or Deploy, which would cut them short).
function reloadBriefNote(row) {
  const html = row.brief && !row.tools ? reloadHTML(row, 'span', 'Reload') : '';
  return html ? { html, cls: 'reload-note', quiet: true, end: false } : null;
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
core.rowNotesLast.push(reloadBriefNote);
core.presses.push(['.reload[data-reload]', (el, e) => {
  e.preventDefault();
  if (!justShown('reload:' + el.dataset.reload))
    native({ type: 'install', action: 'reload', sessionId: el.dataset.reload });
}]);
core.pointerTargets.push('.reload[data-reload]');

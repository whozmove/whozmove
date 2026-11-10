// How a project works, on the page: a session's draft of its project's note waits on its row (row.processDraft, from
// the app) for your Keep It or Not Now, after the tickets' own cards. The app keeps the note, marks what changed and
// takes drafts back (ProcessNotesModule.m); this draws what it's told (process-words.js) and sends your press.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const processKey = (sid, d) => `pndraft:${sid}:${d.at}:${processDraftState(d)}`;

// After the tickets' own cards (Use It 25, Move It 26, Create Ticket 27), as a ticket's own questions come first.
core.rowCards.push({
  name: 'processDraft', order: 28,
  wants: (row) => !!row.s.processDraft?.lines?.length,
  html: (row) => {
    // Kept by when it was drafted and what it shows, so a press can't land on a card that has just changed to another
    // draft, or from Keep It to Try Again.
    const d = row.s.processDraft;
    state.shownAt[processKey(row.s.sessionId, d)] ??= Date.now();
    return processDraftHTML(row.s.sessionId, d, Date.now());
  },
  away: (row) => {
    for (const key of Object.keys(state.shownAt))
      if (key.startsWith(`pndraft:${row.s.sessionId}:`)) delete state.shownAt[key];
  },
});
core.presses.push(['.perm[data-pndraft]', (card, e) => {
  const button = e.target.closest('button[data-act]'), sid = card.dataset.pndraft;
  if (!button) return;
  e.preventDefault();
  if (justShown(`pndraft:${sid}:${card.dataset.at}:${card.dataset.state}`)) return;
  native({ type: 'processAnswer', sessionId: sid, at: Number(card.dataset.at), act: button.dataset.act });
}]);
core.pointerTargets.push('.pn-draft button');
core.forgotten.prefixes.push('pndraft');

// Pressed, the card takes the keys as a request does: Return is Keep It (or Try Again), and Esc lets the keyboard go,
// answering nothing. A step's number is only text, so a number key does nothing here, never picking a step as it
// would a question's option.
core.keyCards.push({
  card: '.perm[data-pndraft]:not([data-state="keeping"])',
  id: (card) => `pndraft:${card.dataset.pndraft}:${card.dataset.at}:${card.dataset.state}`,
  open: (card) => card.dataset.state !== 'keeping',
  takes: (card, target) => !target.closest('button'),
  key: (card, e) => /^[0-9]$/.test(e.key),
});

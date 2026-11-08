// Compact at Breaks on the page: what it did for a session, from then until the session's next message (the row's
// compactedFor), so you can tell what happened while you were away. Quietly after the context ring on its bottom line,
// "Compacted at 1:12", which pointed at says why and the size before and after, or "Couldn't compact", and why; and in
// the row's note, that it stopped part-way, with Take me there, as part of its command may be left in the prompt.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The clock time it happened, in the Mac's own way of writing times ("1:12 AM", "1:12"). `locale` and `timeZone` are
// for tests; the page leaves them out.
function compactedClock(at, locale, timeZone) {
  return new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(at);
}

// What the bottom line says, {words, tip}, or null: once it compacted it, or couldn't. A stop part-way is the row's
// note instead (compactedStopped).
function compactedForYou(done, locale, timeZone) {
  if (!(done?.at > 0) || done.stopped) return null;
  const at = compactedClock(done.at, locale, timeZone);
  if (done.failed) return { words: "Couldn't compact", tip: `Couldn't compact for you at ${at}: ${done.failed}` };
  const size = done.after != null ? ` · ${kTokens(done.before)} → ${kTokens(done.after)}` : '';
  return { words: `Compacted at ${at}`, tip: `Compacted for you at ${at}: ${done.why || 'at a natural break'}${size}` };
}

// The row's note once it stopped part-way, or null: what to do, on one line with Take me there, which waits to be seen
// before it takes a press; why, in the button's tip.
function compactedStopped(s) {
  if (!(s.compactedFor?.at > 0) || !s.compactedFor.stopped) return null;
  state.shownAt['for-you:' + s.sessionId] ??= Date.now();
  return { html: 'Compacting stopped part-way: check its prompt '
    + `<button class="button quiet small for-you-go" data-for-you="${esc(s.sessionId)}" title="Part of /compact may be `
    + 'left in its prompt, and what you had typed there is kept aside">Take me there</button>' };
}

function compactedForYouHTML(s) {
  const said = compactedForYou(s.compactedFor);
  return said ? `<span class="for-you" title="${esc(said.tip)}">${esc(said.words)}</span>` : '';
}

// After the context ring, on the row's bottom line, fading in as it comes. While it's there, where the session runs
// (its branch) makes way for it first (the row part's `place-gives-way`).
core.slots.setup.push((row) => compactedForYouHTML(row.s));
core.slots.rowClass.push((row) => (compactedForYou(row.s.compactedFor) ? ' place-gives-way' : ''));
core.swaps.push(':scope > .main > .where .for-you');
core.rowNotes.push((row) => compactedStopped(row.s));
// Take me there opens the session, once its button has been up long enough to be seen.
core.presses.push(['.for-you-go', (button, e) => {
  const sid = button.dataset.forYou, s = state.last.sessions.find((x) => x.sessionId === sid);
  e.preventDefault();
  if (s && !justShown('for-you:' + sid)) openSession(s);
}]);
core.forgotten.prefixes.push('for-you');

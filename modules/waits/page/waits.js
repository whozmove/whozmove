// The waits module's part of the page: a session waiting on someone else says so on its row, quietly, as where things
// stand (core.rowNotesLast), so any other note (an ask it handed you in One Task, a step that didn't go) shows over
// it; and, while what came waits for a seat in the gear, what came, that it waits for one, and where the gear is
// changed, in the usage module's own words. The words are the app's (the row's `wait`, docs/reference/rows.md), and
// the gear's are the usage module's (core.gear); this only draws them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The note for a session's row, or null: its words as `text`, which a full row's work line says (cut to one line, all
// of it on pointing), and as `html`, made safe here, with the same for VoiceOver, for a line of its own.
function waitNote(s) {
  const wait = s.wait;
  if (!wait || wait.closed || wait.missed) return null;
  const held = wait.held && wait.came;
  const where = held ? core.gear?.words?.where?.(core.gear.facts?.()) : null;
  const says = held ? `${wait.came} · next free seat${where ? `. ${where}` : ''}` : wait.says;
  if (!says) return null;
  const spoken = held ? `${wait.cameSpoken || wait.came}, waiting for a free seat in the gear${where ? `. ${where}` : ''}`
    : wait.spoken || says;
  return { text: says, html: `<span class="wait-says" aria-label="${esc(spoken)}">${esc(says)}</span>`, quiet: true };
}

core.rowNotesLast.push((row) => waitNote(row.s));

// Resume's mark: a play triangle, in the kit's action icons' shape.
const RESUME_ICON = ACT_ICON('<path d="M4 2.6v6.8L9.4 6z"/>');

// A conversation that closed while it waited: its ask line, in your move's colour once something came for it ("#12
// approved", "+1" when more did), else quiet ("Stopped, waiting on #12"), ending in Resume. Resume takes no press of
// its own: a press on it is its row's own press, which opens the conversation again with the words the app has for it.
function closedWaitNote(row) {
  const wait = row.s.wait;
  if (!wait?.closed) return null;
  const came = wait.cameFirst || '', more = wait.cameMore || 0;
  const words = came || wait.says;
  if (!words) return null;
  const label = `${wait.cameSpoken || words}. Resume: carry on the conversation`;
  const html = askActHTML(RESUME_ICON, 'Resume: carry on the conversation', '');
  return { text: words, html: askLineHTML(words, more, more === 1 ? '1 more came' : `${more} more came`, '', label),
           tone: came ? 'turn' : undefined, quiet: !came, cls: 'ask-note', line: true, look: came ? 'normal' : 'low',
           act: { want: 'resume', html } };
}

core.rowNotes.push(closedWaitNote);

// A conversation run again that hasn't asked in its while (Take Me There opened it to look, say): its ask line, "Not
// waiting on #12 any more", or once something came, what did ("#12 approved · not waiting any more", "+1" when more
// did) in your move's colour, ending in Resume, whose own press has the app type Resume's words in, as you'd send them,
// where Send says that's safe.
function missedWaitNote(row) {
  const wait = row.s.wait;
  if (!wait?.missed || !wait.says) return null;
  const came = !!wait.cameFirst, more = came ? wait.cameMore || 0 : 0;
  const words = came ? `${wait.cameFirst} · not waiting any more` : wait.says;
  const tip = came ? 'Resume: tell it to hear what came' : 'Resume: carry on the conversation';
  const label = came ? `${wait.cameSpoken || wait.cameFirst}, not waiting any more. ${tip}`
    : `${wait.spoken || wait.says}. ${tip}`;
  const html = askActHTML(RESUME_ICON, tip, ` data-wait-say="${esc(row.s.sessionId)}"`);
  return { text: words, html: askLineHTML(words, more, more === 1 ? '1 more came' : `${more} more came`, '', label),
           tone: came ? 'turn' : undefined, quiet: !came, cls: 'ask-note', line: true, look: came ? 'normal' : 'low',
           act: { want: 'resume', html } };
}

core.rowNotes.push(missedWaitNote);
// A Resume that has only just come waits to be seen before it takes a press, as a press meant for what was there may
// land on it.
let waitSayShown = new Set();
core.beforeDraw.push(() => {
  const now = new Set((state.last?.sessions || []).filter((s) => s.wait?.missed).map((s) => s.sessionId));
  for (const sid of now) if (!waitSayShown.has(sid)) state.shownAt['wait-say:' + sid] = Date.now();
  waitSayShown = now;
});
core.forgotten.prefixes.push('wait-say');
core.presses.push(['[data-wait-say]', (button, e) => {
  e.preventDefault();
  const sid = button.dataset.waitSay;
  if (!sid || justShown('wait-say:' + sid)) return;
  native({ type: 'waitSay', sessionId: sid });
}]);

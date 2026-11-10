// The Keep It card's words and drawing, in plain functions (process-notes.js puts it on the row): a session's draft of
// how its project works, whole, as numbered steps of text, for your Keep It or Not Now. Every word of the note is the
// session's, so each goes in escaped. The app marks each line added or taken out against the note as kept now, so Keep
// It changes exactly what the card shows; this only draws what it's given.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What a mark says, in words beside where the line came from: never colour alone.
const PROCESS_MARKS = { added: 'new', removed: 'taken out' };

// When something was, as the Mac writes a time here: "at 17:02" (or "at 5:02 PM") today, "on 18 May at 17:02" on
// another day, with the year once it's another year, so a note kept weeks ago never reads as kept today.
function processWhen(at, now, locale, timeZone) {
  const time = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(at);
  const day = (t) => new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone })
    .format(t);
  if (day(at) === day(now)) return `at ${time}`;
  const year = day(at).slice(0, 4) !== day(now).slice(0, 4);
  const date = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', ...(year ? { year: 'numeric' } : {}),
    timeZone }).format(at);
  return `on ${date} at ${time}`;
}

// A line as the session wrote it, in its parts: "Checks: npm test passes. (CONTRIBUTING.md)" is the step's name
// (before the first colon), what it asks, and where it came from (the bracket at its end). A line without a name or a
// source is shown whole.
function processLineParts(text) {
  const t = String(text ?? '').trim();
  const from = t.match(/\s*\(([^()]+)\)$/);
  const body = from ? t.slice(0, from.index) : t;
  const named = body.match(/^([^:]{1,60}):\s+(.+)$/s);
  return { name: named ? named[1] : '', says: named ? named[2] : body, from: from ? from[1] : '' };
}

// One step of the note, drawn as text to read, never as a choice: its number as plain text, its name in bold inside
// the sentence, and where it came from after it, quieter. A step new or taken out says so in words, in its colour, with
// no box, fill or round mark, so nothing in the note looks like a question's options or anything to press. A line taken
// out has no number, as Keep It drops it. VoiceOver reads each step as one line.
function processStepHTML(line, n) {
  const p = processLineParts(line.text), mark = PROCESS_MARKS[line.mark];
  const said = [mark, n ? `step ${n}` : ''].filter(Boolean).join(', ');
  const from = [mark ? `<span class="pn-mark">${mark}</span>` : '', p.from ? esc(p.from) : ''].filter(Boolean)
    .join(' · ');
  return `<li class="pn-step${mark ? ` pn-${line.mark}` : ''}" aria-label="${said}: ${esc(line.text)}">`
    + `<span class="pn-n" aria-hidden="true">${n ? `${n}.` : '–'}</span>`
    + `<span class="pn-body" aria-hidden="true"><span class="pn-says">${p.name ? `<b>${esc(p.name)}:</b> ` : ''}`
    + `${esc(p.says)}</span>${from ? ` <span class="pn-from">${from}</span>` : ''}</span></li>`;
}

// The note as a numbered list, in the order the session wrote it, which is the order the work goes in.
function processStepsHTML(lines) {
  let n = 0;
  return `<ol class="pn-note">${(lines || []).map((l) => processStepHTML(l, l.mark === 'removed' ? 0 : ++n)).join('')}`
    + '</ol>';
}

// What changed, in words: "1 line added, 1 removed".
function processChangeWords(lines) {
  const n = (mark) => (lines || []).filter((l) => l.mark === mark).length;
  const parts = [[n('added'), 'added'], [n('removed'), 'removed']].filter(([k]) => k);
  return parts.map(([k, w], i) => `${k}${i ? '' : k === 1 ? ' line' : ' lines'} ${w}`).join(', ');
}

// What the card shows now, so a press can't land on a card that has just changed: waiting, keeping, or couldn't keep.
const processDraftState = (d) => (d.keeping ? 'keeping' : d.problem ? 'problem' : 'waiting');

// The card: the note whole, what it is (or, against a note kept already, what changed), and its foot: Keep It and Not
// Now, "Keeping it…" while it's written, or why it couldn't be, with Try Again. `now` says which day it is; `locale`
// and `timeZone` are for tests, and the page leaves them out.
function processDraftHTML(sid, d, now, locale, timeZone) {
  if (!d?.at || !d.lines?.length) return '';
  const project = esc(d.project);
  const title = d.keptAt ? `Keep the change to how ${project} works?` : `Keep this as how ${project} works?`;
  const what = d.keptAt
    ? `Against the note kept ${esc(processWhen(d.keptAt, now, locale, timeZone))}: ${processChangeWords(d.lines)}.`
    : `What ${project}’s own pages don’t say. Every session on ${project} and its worktrees gets it with its ticket, `
      + 'beside those pages.';
  const back = d.declinedAt ? `<div class="q-help">You said Not Now ${esc(processWhen(d.declinedAt, now, locale,
    timeZone))}. This one has a change that wasn’t there then.</div>` : '';
  const foot = d.keeping ? '<div class="q-help pn-busy">Keeping it…</div>'
    : (d.problem ? `<div class="perm-why pn-warn">Couldn’t keep it: ${esc(d.problem)}.</div>` : '')
      + '<div class="perm-actions"><button data-act="notNow">Not Now</button>'
      + `<button class="perm-allow" data-act="keep">${d.problem ? 'Try Again' : 'Keep It'}</button></div>`;
  return `<div class="perm pn-draft" data-pndraft="${esc(sid)}" data-at="${esc(String(d.at))}" `
    + `data-state="${processDraftState(d)}"><div class="q-top"><span class="card-title">${title}</span></div>`
    + `<div class="q-help">${what}</div>${back}${processStepsHTML(d.lines)}`
    + (d.keeping ? '' : '<div class="q-help">To change anything, say so in the conversation, and it shows here again.'
      + '</div>')
    + `${foot}</div>`;
}

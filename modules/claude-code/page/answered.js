// What shows on a Claude Code session's row once a request is answered: the line that takes the card's place just after
// you answer it here, and the card for what a session you allow answered for you (row.answeredFor).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The line where a request's card was, once you've answered it here (answered, by how): what you said and what about
// ("✓ Allowed once · npm install"; for a question, the answer sent, "✓ Answered · Under the total"), for as long as the
// request is still listed, until Claude goes on. One still there after a few seconds, the answer not having landed
// yet, offers the way to its session, where it can be answered too; that button waits to be seen before it takes a
// press. Its own state (data-stage), so the card cross-fades into it.
const RECEIPT_GO_AFTER_MS = 5000, RECEIPT_NO = ['deny', 'dismissed', 'stopped', 'skipped'];
const receiptLate = (ask) => Date.now() - (state.answeredAt[ask.id] || 0) >= RECEIPT_GO_AFTER_MS;
const receiptSubject = (ask, how) => (how === 'answered' && state.quiz[ask.id]?.sent) || askSubject(ask);
function receiptHTML(ask, sid) {
  const how = state.answering[ask.id], no = RECEIPT_NO.includes(how), subject = receiptSubject(ask, how);
  const late = receiptLate(ask);
  if (late) state.shownAt[`receipt:${ask.id}`] ??= Date.now();
  return `<div class="perm ask-receipt${no ? ' denied' : ''}" data-stage="answered" data-receipt="${esc(sid)}" `
    + `data-for="${esc(ask.id)}">${DONE_ICON}<span class="ask-receipt-words">${esc(receiptWords(how))}</span>`
    + (subject ? `<span class="ask-obj">${esc(subject)}</span>` : '')
    + (late ? '<button class="button quiet small ask-receipt-go">Take me there</button>' : '') + '</div>';
}

// What a session you allow answered for this one, for a while after (its agent's module keeps it for 30 minutes): who
// answered and how long ago, and what it did: sent the plan back with its note, answered its questions with what was
// picked, or approved its plan, with the plan to read and the way to its tab; and says so, in the colour of something
// to put right, where Claude Code didn't take the approval and it still waits there. Its buttons wait to be seen
// before they take a press.
const SPEECH_ICON = '<svg class="ask-for-mark" width="11" height="11" viewBox="0 0 11 11" aria-hidden="true"><path '
  + 'd="M2 1.5h7a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H5L2.5 9.5V7.5H2a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z" fill="none" '
  + 'stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/></svg>';
function answeredForHTML(s, now) {
  const a = s.answeredFor, words = answeredForWords(a);
  if (!words) return '';
  const key = `approved:${s.sessionId}:${a.at}`, at = `data-sid="${esc(s.sessionId)}" data-at="${esc(String(a.at))}"`;
  if (words.plan) state.shownAt[key] ??= Date.now();
  const buttons = !words.plan ? '' : '<div class="perm-actions">'
    + (words.warn ? '' : `<button class="af-read" ${at} data-wid="${esc(a.planId || '')}">Read plan</button>`)
    + `<button class="af-go${words.warn ? ' perm-allow' : ''}" ${at}>Take me there</button></div>`;
  const tone = words.warn ? ' warn' : words.turn ? ' turn' : '';
  return `<div class="perm ask-for"><div class="card-head"><span>${SPEECH_ICON} ${esc(words.head)}</span>`
    + `<span class="end" data-ago="${esc(String(a.at || now))}">${ago(now - (a.at || now))}</span></div>`
    + `<div class="perm-why${tone}">${esc(words.what)}</div>${buttons}</div>`;
}

// What Claude's line on a chat beside the folded panel says once you've answered its request there, while the request
// is still listed (core.agent.answeredLine): what you said and what about, as the line on the list says it ("✓ Answered
// · Under the total"), and whether it was turned down (`no`); null while it isn't answered here. Null again once the
// answer is late: the chat goes back to asking, with the late line and its way to the session under it, so the answer
// is said in one place.
function answeredLine(ask) {
  const how = state.answering[ask.id];
  if (!how || receiptLate(ask)) return null;
  const subject = receiptSubject(ask, how);
  return { text: `✓ ${receiptWords(how)}${subject ? ` · ${subject}` : ''}`, no: RECEIPT_NO.includes(how) };
}
core.agent.answeredLine = answeredLine;

// Once answered, the line saying so takes the request card's place, while the request is still listed. Not in a chat
// beside the folded panel (row.chat) until the answer has gone unlanded for a while (the late line, with the way to its
// session): the request is about to go, and a line that came and went a second later would make the chat shrink twice,
// the chats after it closing up twice, so answering takes the card away, Claude's line saying what you answered in its
// place (answeredLine), and the chat goes straight to its height without it. Late, the line says it there instead.
core.rowCards.push({
  name: 'answered', order: 11,
  wants: (row) => !!row.s.ask && !!state.answering[row.s.ask.id] && (!row.chat || receiptLate(row.s.ask)),
  html: (row) => receiptHTML(row.s.ask, row.s.sessionId),
});
// What a session you allow answered shows under the chat while no request waits on the row, after every card that asks
// something of you (Switch model?, Compact, Deploy's set-up), so it never keeps one of them from showing.
core.rowCards.push({
  name: 'answeredFor', order: 90,
  wants: (row) => !row.s.ask && !!answeredForWords(row.s.answeredFor),
  html: (row) => answeredForHTML(row.s, row.now),
});
// Take me there on a line that says an answer went: the session, where the request can be answered too.
core.presses.push(['.ask-receipt .ask-receipt-go', (button, e) => {
  e.preventDefault();
  const receipt = button.closest('.ask-receipt');
  if (justShown(`receipt:${receipt.dataset.for}`)) return;
  const s = state.last.sessions.find((x) => x.sessionId === receipt.dataset.receipt);
  if (s) openSession(s);
}]);
core.forgotten.prefixes.push('receipt');
core.forgotten.prefixes.push('approved');
// An approved plan's card's buttons: the plan in the reader, or its session's tab.
core.presses.push(['.ask-for .af-read, .ask-for .af-go', (button, e) => {
  e.preventDefault();
  if (justShown(`approved:${button.dataset.sid}:${button.dataset.at}`)) return;
  const sid = button.dataset.sid;
  if (button.classList.contains('af-read')) return openReader(sid, button.dataset.wid || null, 'writings');
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (s) openSession(s);
}]);

// "Switch model?" (switching re-reads a cached conversation), asked on its row instead of where Claude asks it, as the
// card under its chat, for as long as the row's switchAsk says it's asked: before /model goes to a Claude Desktop
// conversation, once Claude's own box asks it there, or while a terminal session's hook waits for the answer.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Per session: whether Don't ask again is ticked, and your answer, { ok, to, at }, which the card gives way to until
// the row says the question's gone (a moment, while the app passes it on).
moduleState({ switchNever: {}, switchAnswered: {} });

// An answer given here lasts this long on the page, the row's question going within it.
const SWITCH_ANSWER_MS = 4000;

function switchAnswered(sid) {
  const answered = state.switchAnswered[sid];
  return answered && Date.now() - answered.at < SWITCH_ANSWER_MS ? answered : null;
}

// How much the conversation holds, when that's known (`tokens`), says what re-reading it costs. Don't ask again is
// offered only where the app keeps that answer (`never`: Claude Desktop).
function switchHTML(s) {
  const q = s.switchAsk, sid = s.sessionId;
  state.shownAt['switch:' + sid] ??= Date.now();
  const was = esc(core.agent.modelName(q.from) || 'its model'), now = esc(core.agent.modelName(q.to) || q.to);
  const size = q.tokens > 0 ? ` (about ${kTokens(q.tokens)} tokens)` : '';
  return `<div class="perm switch-ask" data-switch="${esc(sid)}" data-stage="switch">`
    + '<div class="perm-title">Switch model?</div>'
    + `<div class="perm-why">This session is cached for ${was}. Switching to ${now} means Claude re-reads the whole`
    + ` session${size} on your next message, which uses more of your limit.</div>`
    + (q.never ? `<div class="never${state.switchNever[sid] ? ' on' : ''}"><span class="box"></span>Don't ask again</div>`
      : '')
    + '<div class="perm-actions"><button class="cancel">Cancel</button>'
    + '<button class="go perm-allow">Switch model</button></div></div>';
}

// Don't ask again ticks on and off; Switch model or Cancel answers, once the card has been up long enough to be seen.
// Switching, the card turns into the pick going in at once (commands.js), while the app passes the answer on.
function pressSwitchCard(card, e) {
  const sid = card.dataset.switch, s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s?.switchAsk) return;
  if (e.target.closest('.never')) {
    e.preventDefault();
    state.switchNever[sid] = !state.switchNever[sid];
    render();
    return;
  }
  const button = e.target.closest('button');
  if (!button || justShown('switch:' + sid)) return;
  e.preventDefault();
  const ok = button.classList.contains('go');
  native({ type: 'switchAnswer', sessionId: sid, ok, never: ok && !!state.switchNever[sid] });
  state.switchAnswered[sid] = { ok, to: s.switchAsk.to, at: Date.now() };
  delete state.switchNever[sid];
  render();
}

// It comes after a request waiting on the row, and before a pick going in, whose place it takes while it asks.
core.rowCards.push({
  name: 'switch', order: 12,
  wants: (row) => !!row.s.switchAsk && !switchAnswered(row.s.sessionId),
  html: (row) => switchHTML(row.s),
  away: (row) => { delete state.shownAt['switch:' + row.s.sessionId]; },
});
core.presses.push(['.perm[data-switch]', pressSwitchCard]);
core.forgotten.keys.push('switchNever', 'switchAnswered');
core.forgotten.prefixes.push('switch');

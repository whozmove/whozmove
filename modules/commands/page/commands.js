// The commands a row offers its agent: its model, effort and mode on the details' second line, each opening the app's
// menu to change it, and the context ring, which opens the Compact card; and a card while a pick goes into a terminal
// session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The Compact card, per session: open, its note ({text, way}: why it didn't compact, and the words of a button past
// that, or null), and the focus typed in it. The session whose context ring is pointed at. The sessions whose ring has
// opened by itself to say now is a good time to compact (compactNow), once it has. The sessions whose ring was last
// drawn turning, as they compact, and those whose compaction has just ended ({at, angle}: when, and where its arc was
// then), whose ring settles at its new size; and those whose size is still the one from before ({at, tokens}).
moduleState({ compactOpen: {}, compactNotes: {}, compactFocus: {}, hoverCtx: null, compactNowShown: {},
              ringTurning: {}, ringSettling: {}, sizeBefore: {} });

// ---- The setup line ----

// How the row's agent is set up: its model, effort and mode, each a label that opens the app's menu below it, and its
// context ring.
function agentSetupHTML(s) {
  const a = s.agent || {}, mode = core.agent.modeName(a.mode);
  const inClaude = hostOf(s).inName;
  const pick = (field, label, cls = '') =>
    `<span class="pick${cls}" data-pick="${field}" title="Change ${field}${inClaude}">${label}</span>`;
  const agent = [core.agent.modelName(a.model) && pick('model', esc(core.agent.modelName(a.model))),
                 a.effort && pick('effort', esc(a.effort)),
                 mode && pick('mode', esc(mode), a.mode === 'bypassPermissions' ? ' bypass' : '')]
    .filter(Boolean).join(' · ');
  return (agent ? `<span class="agent">${agent}</span>` : '') + contextRing(s);
}

// Whether now is a good time to compact, and why, or null: only while the session sits idle, and then once its
// context is nearly full or long, or, once it's big, when its work has just been saved (a turn that committed or went
// further, or its edits in its checkout with nothing left to commit there), or when neither it nor you have been on it
// for an hour, after which the next message has Claude read all of it again. Compacting then is cheap and loses
// nothing half done, where auto-compact comes in the middle of a task. Never where the app says a compaction couldn't
// go in (`noCompact`: it runs in no terminal the panel can type into, or it's open twice), as the card would only
// say why.
const COMPACT_SAVED = new Set(['Committed', 'Pushed', 'PR raised', 'Merged', 'On staging', 'Deployed']);
function compactNow(s, now) {
  const a = s.agent || {}, tokens = a.tokens;
  if (!tokens || s.status !== 'idle' || s.ask || s.compacting || s.noCompact) return null;
  const window = core.agent.contextWindow(a.model, tokens), pct = Math.round(tokens / window * 100);
  if (pct >= 85) return "it's nearly full, and would soon compact by itself";
  if (tokens >= Math.min(400000, window * 0.75)) return "it's getting long";
  if (tokens < Math.min(200000, window / 2)) return null;
  const edited = editedAt(s, (s.git || s.workGit)?.root);
  if (COMPACT_SAVED.has(s.outcome) || (edited && s.checkout?.changes === 0)) return 'your work is saved';
  const moved = Math.max(s.lastReplyAt || 0, s.messageAt || 0, onItAt(s));
  if (moved && !s.focused && now - moved >= 3600000)
    return "you've been away from it for an hour, so Claude would read all of it again with your next message";
  return null;
}

// A ring filling up with the context in use. Neutral below 60%, amber from 60% (filling up), red-orange from 85%
// (near auto-compact: start fresh or compact). Pointed at, it widens into a Compact button that is the same gauge
// (its fill is the context in use) and says how full it is first, where the ring was; a click opens the Compact card
// (compactHTML). It's drawn open while pointed at or while its card is up, so the rebuild every second doesn't replay
// the widening. When it's a good time to compact (compactNow), it opens by itself and stays open, saying "Compact
// now", and why in its tip: drawn closed the first time (`now-soon`), it widens in the next frame, as it does
// pointed at; once it no longer is, it's drawn open once more (`now-going`) and folds in the next frame, as it does
// pointed away. While the conversation compacts, by itself or asked for, the ring is a short arc going round
// (`compacting`), the turn's phase taken from the clock so the rebuild every second carries it on; it doesn't widen
// then, as Claude's line says what it's doing and for how long. When the compaction ends, the arc fades where it was
// as the ring fills from empty to the new size (`settling`), once.
const RING_TURN_MS = 1200, RING_SETTLE_MS = 700;
function contextRing(s) {
  const a = s.agent || {}, tokens = a.tokens, model = a.model;
  if (!tokens) return '';
  const compacting = !!s.compacting, settle = ringSettle(s.sessionId, compacting, tokens);
  const window = core.agent.contextWindow(model, tokens), pct = Math.min(100, Math.round(tokens / window * 100));
  const color = pct >= 85 ? GAUGE.limit : pct >= 60 ? GAUGE.warning : GAUGE.normal;
  const r = 5, length = 2 * Math.PI * r, left = Math.max(0, core.agent.compactLimit(a) - tokens);
  const sid = s.sessionId, why = sizeBefore(sid, tokens) ? null : compactNow(s, state.last.now);
  const was = !!state.compactNowShown[sid], going = !why && was && !calm.matches;
  if (!why && !going) delete state.compactNowShown[sid];
  else if (why && calm.matches) state.compactNowShown[sid] = true;
  const shown = !!why && !!state.compactNowShown[sid];
  const open = !compacting && (state.hoverCtx === sid || state.compactOpen[sid] || shown || going) ? ' open' : '';
  const now = why ? (shown ? ' now' : ' now now-soon') : going ? ' now-going' : '';
  const title = compacting ? `Compacting the conversation · it was ${pct}% full`
    : (why ? `A good time to compact: ${why} · ` : '')
      + `${pct}% · ${kTokens(tokens)} of ${kTokens(window)} tokens in context`
      + ` · ${kTokens(left)} left before auto-compact`;
  const arc = (part, more = '') => `<circle class="ctx-arc"${more} cx="6" cy="6" r="${r}" fill="none"`
    + ` style="stroke:${color}" stroke-width="1.6" stroke-linecap="round"`
    + ` stroke-dasharray="${(length * part).toFixed(2)} ${length.toFixed(2)}"/>`;
  const svg = compacting ? `<svg width="12" height="12" viewBox="0 0 12 12" style="${phase(RING_TURN_MS)}">`
    : `<svg width="12" height="12" viewBox="0 0 12 12"${settle ? ` style="--since:-${settle.since}ms"` : ''}>`;
  return `<span class="ctx${open}${now}${compacting ? ' compacting' : settle ? ' settling' : ''}"`
    + ` data-ctx="${esc(s.sessionId)}" title="${title}" style="color:${color};--fill:${pct}%">${svg}`
    + `<circle cx="6" cy="6" r="${r}" fill="none" style="stroke:var(--ring-track)" stroke-width="1.6"/>`
    + (compacting ? arc(0.28) : (settle ? arc(0.28, ` transform="rotate(${settle.angle} 6 6)"`) : '')
                                + arc(pct / 100).replace('ctx-arc', 'ctx-fill'))
    + `</svg><span class="ctx-label">${pct}% · Compact${why || going ? ' now' : ''}</span></span>`;
}

// Whether the session's ring is settling after a compaction, and for how long it has been and where its arc was then
// ({since, angle}), or null; noting, as it's drawn, whether it's compacting, and the size it had as it ended.
function ringSettle(sid, compacting, tokens) {
  const t = performance.now();
  if (compacting) {
    state.ringTurning[sid] = true;
    delete state.ringSettling[sid];
    return null;
  }
  if (state.ringTurning[sid]) {
    delete state.ringTurning[sid];
    state.sizeBefore[sid] = { at: state.last.now, tokens };
    if (!calm.matches) state.ringSettling[sid] = { at: t, angle: Math.round((t % RING_TURN_MS) / RING_TURN_MS * 360) };
  }
  const settle = state.ringSettling[sid];
  if (settle && t - settle.at < RING_SETTLE_MS) return { since: Math.round(t - settle.at), angle: settle.angle };
  delete state.ringSettling[sid];
  return null;
}

// Whether the session's context size is still the one from before the compaction that has just ended: the new size
// comes with the transcript's next read, a moment later, and until then it isn't a good time to compact again. Once
// the size has changed, or after 30s (one stopped with Esc keeps its size), it's the size it says.
function sizeBefore(sid, tokens) {
  const before = state.sizeBefore[sid];
  if (before && (tokens !== before.tokens || state.last.now - before.at > 30000)) delete state.sizeBefore[sid];
  return !!state.sizeBefore[sid];
}

// A row's model, effort or mode: the app's menu for it, below the label.
function pressPick(pick) {
  const s = state.last.sessions.find((x) => x.sessionId === pick.closest('.row')?.dataset.id);
  if (!s) return;
  const r = pick.getBoundingClientRect();
  native({ type: 'pick', field: pick.dataset.pick, sessionId: s.sessionId, x: r.left - 4, y: r.bottom + 4 });
}

// ---- The Compact card ----

// Claude Code has one compaction, `/compact`, whose optional words steer its summary: the three choices say how much
// it keeps (the last two add instructions), and the box takes a focus in your own words. A choice goes in as it would
// be typed, while the session is idle. A refusal, or a compaction that doesn't go through, comes back as a note on the
// card.
const COMPACT_LEVELS = [
  ['', 'Compact', 'Summarize the conversation so far'],
  ['Keep the current task in full detail: what is being worked on, the latest changes, file paths, code and '
   + 'open questions. Summarize earlier work briefly.',
   'Keep details', 'Older work summarized; the current task kept in detail'],
  ['Keep only what is needed to continue: decisions made, open tasks, key file paths and constraints. '
   + 'Drop exploration, tool output and settled discussion.',
   'Keep essentials', 'Only decisions, open tasks and key files'],
];
function toggleCompact(sid) {
  // A request waiting for an OK on the same row comes first.
  if (!state.compactOpen[sid] && state.last.sessions.find((x) => x.sessionId === sid)?.ask) return;
  if (state.compactOpen[sid]) delete state.compactOpen[sid];
  else { state.compactOpen[sid] = true; state.shownAt['compact:' + sid] = Date.now(); }
  delete state.compactNotes[sid];
  render();
}
function sendCompact(sid, focus) {
  delete state.compactOpen[sid];
  delete state.compactNotes[sid];
  delete state.compactFocus[sid];
  native({ type: 'compact', sessionId: sid, focus });
  render();
}
function compactHTML(s) {
  const a = s.agent || {}, note = state.compactNotes[s.sessionId];
  const left = Math.max(0, core.agent.compactLimit(a) - (a.tokens || 0));
  const options = COMPACT_LEVELS.map(([, label, desc], i) =>
    `<button class="opt" data-level="${i}"><span class="opt-label">${label}</span>`
    + `<span class="opt-desc">${desc}</span></button>`).join('');
  return `<div class="perm compact" data-compact="${esc(s.sessionId)}">`
    + '<div class="q-top"><span class="q-head">Compact the conversation</span>'
    + `<span class="c-left" title="before auto-compact">${kTokens(left)} left</span>`
    + '<button class="q-close" title="Close">×</button></div>'
    + `<div class="q-opts">${options}</div>`
    + '<input class="q-type c-focus" placeholder="Or your own focus, then Return"'
    + ` value="${esc(state.compactFocus[s.sessionId] || '')}">`
    + (note ? `<div class="c-note">${esc(note.text)}</div>` : '')
    + (note?.way ? `<div class="perm-actions"><button class="c-way">${esc(note.way)}</button></div>` : '') + '</div>';
}

// A choice sends /compact, once the card has been up long enough to be seen, as its button past a reason is taken; ×
// closes it; a press in its box puts the caret there, as usual.
function pressCompactCard(card, e) {
  const sid = card.dataset.compact, button = e.target.closest('button');
  if (!button) return;
  e.preventDefault();
  if (button.classList.contains('q-close')) return toggleCompact(sid);
  if (justShown('compact:' + sid)) return;  // only just opened: not seen yet
  if (button.classList.contains('c-way')) {
    if (state.compactNotes[sid]) state.compactNotes[sid].way = null;
    native({ type: 'wayPast', sessionId: sid });
    return render();
  }
  const level = COMPACT_LEVELS[+button.dataset.level];
  if (level) sendCompact(sid, level[0]);
}

// A pick on its way into a terminal session (goingIn), from the moment it's typed until its result: going in, with a
// dot fading on and off as a working row's does, started partway in so the list's rebuild each second doesn't restart
// it; or, once no result has come, Claude Code asking about it in the terminal, which only the terminal can answer (its
// "Change effort level?", say), and the way there. Right after Switch model is pressed on the row's "Switch model?",
// it shows the switch going in at once, while the app passes the answer on. Each of its states is its own (data-stage),
// so changing from one to another cross-fades, and a button that has only just come counts as only just shown.
function goingOf(s) {
  if (s.goingIn) return s.goingIn;
  const answered = switchAnswered(s.sessionId);
  return answered?.ok ? { field: 'model', value: answered.to, inTerminal: false } : null;
}

function goingHTML(s) {
  const { field, value, inTerminal } = goingOf(s), sid = esc(s.sessionId);
  const stage = inTerminal ? 'terminal' : 'going';
  state.shownAt[`going:${s.sessionId}:${stage}`] ??= Date.now();
  const name = field === 'model' ? esc(core.agent.modelName(value) || value) : esc(value);
  if (!inTerminal) {
    const what = field === 'model' ? `Switching to ${name}…` : `Changing the ${esc(field)} to ${name}…`;
    return `<div class="perm going" data-going="${sid}" data-stage="going">`
      + `<div class="going-line"><span class="dot" style="${phase(1400)}"></span>`
      + `<span class="perm-title">${what}</span></div></div>`;
  }
  const what = field === 'model' ? `switches to ${name}` : `changes the ${esc(field)} to ${name}`;
  return `<div class="perm going in-terminal" data-going="${sid}" data-stage="terminal">`
    + `<div class="perm-title">Claude is asking in the terminal before it ${what}</div>`
    + '<div class="perm-actions"><button class="perm-go">Take me there</button></div></div>';
}

// Take me there goes to the session, once its button has been up long enough to be seen.
function pressGoingCard(card, e) {
  const sid = card.dataset.going, s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s || !e.target.closest('.perm-go') || justShown(`going:${sid}:terminal`)) return;
  e.preventDefault();
  openSession(s);
}

// A /compact sent from the Compact card didn't go through: the card opens again, saying why, with a button past that
// when its terminal has one (iTerm2's Python API, turned on).
window.compactNote = (sid, text, way) => {
  state.compactOpen[sid] = true;
  state.compactNotes[sid] = { text, way };
  state.shownAt['compact:' + sid] = Date.now();  // its button is new: it waits to be seen before it takes a press
  render();
};

// ---- What it plugs into ----

// At the start of the bottom line. The model, effort and mode cross-fade as they change, not the ring.
core.slots.setup.push((row) => agentSetupHTML(row.s));
core.swaps.push(':scope > .main > .where .agent');
// The Compact card comes after a request waiting on the row, and closes for Deploy's set-up card.
// A pick going in comes after a request waiting on the row, and before the Compact card. Away, what it showed is
// forgotten, so a button that comes back waits again before it takes a press.
core.rowCards.push({
  name: 'going', order: 15,
  wants: (row) => !!goingOf(row.s),
  html: (row) => goingHTML(row.s),
  away: (row) => {
    for (const stage of ['going', 'terminal']) delete state.shownAt[`going:${row.s.sessionId}:${stage}`];
  },
});
core.rowCards.push({
  name: 'compact', order: 20,
  wants: (row) => !!state.compactOpen[row.s.sessionId],
  html: (row) => compactHTML(row.s),
  close(sid) { delete state.compactOpen[sid]; },
});
core.presses.push(['.pick[data-pick]', pressPick],
                  ['.ctx[data-ctx]', (ring, e) => { e.preventDefault(); toggleCompact(ring.dataset.ctx); }],
                  ['.perm[data-compact]', pressCompactCard],
                  ['.perm[data-going]', pressGoingCard]);
// Words typed in the card's box are kept the same way as an answer's; Return sends them as the focus.
core.typing.push(['.c-focus', (box) => { state.compactFocus[box.closest('.perm').dataset.compact] = box.value; }]);
core.returns.push(['.c-focus', (box) => {
  if (box.value.trim()) sendCompact(box.closest('.perm').dataset.compact, box.value.trim());
}]);
core.pointerTargets.push('.pick');
// The ring pointed at widens into its Compact button, and stays wide while its card is up, or while it says now is a
// good time to compact; never while it's turning, as the conversation compacts.
core.pointerWatchers.push((el) => {
  state.hoverCtx = el?.closest('.ctx[data-ctx]')?.dataset.ctx || null;
  for (const ring of document.querySelectorAll('.ctx[data-ctx]')) {
    const sid = ring.dataset.ctx;
    ring.classList.toggle('open', !ring.classList.contains('compacting')
                                  && (sid === state.hoverCtx || !!state.compactOpen[sid]
                                  || (ring.classList.contains('now') && !!state.compactNowShown[sid])
                                  || ring.classList.contains('now-going')));
  }
});
// A ring that has only just become a good time to compact is drawn closed, then widens once that's been laid out; one
// that no longer is is drawn open, then folds, unless it's pointed at or its card is up. The copy of the row you're on
// held at the list's edge (sticky.js) is made from the row before this, without the row's data, so it's found by its
// mark alone and moves in the same frame.
core.afterDraw.push(() => {
  const soon = [...document.querySelectorAll('.ctx.now-soon')];
  const going = [...document.querySelectorAll('.ctx.now-going')];
  if (!soon.length && !going.length) return;
  for (const ring of [...soon, ...going]) void ring.offsetWidth;
  requestAnimationFrame(() => {
    for (const ring of soon) {
      if (ring.dataset.ctx) state.compactNowShown[ring.dataset.ctx] = true;
      ring.classList.remove('now-soon');
      ring.classList.add('open');
    }
    for (const ring of going) {
      const sid = ring.dataset.ctx;
      if (sid) delete state.compactNowShown[sid];
      ring.classList.remove('now-going');
      if (!sid || (sid !== state.hoverCtx && !state.compactOpen[sid])) ring.classList.remove('open');
    }
  });
});
core.forgotten.keys.push('compactOpen', 'compactNotes', 'compactFocus', 'compactNowShown', 'ringTurning',
                         'ringSettling', 'sizeBefore');
core.forgotten.prefixes.push('compact', 'going');

// The commands a row offers its agent: its model, effort and mode on the details' second line, each opening the app's
// menu to change it, and the context ring, which opens the Compact card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The Compact card, per session: open, its note, and the focus typed in it. The session whose context ring is pointed
// at.
moduleState({ compactOpen: {}, compactNotes: {}, compactFocus: {}, hoverCtx: null });

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

// A ring filling up with the context in use. Neutral below 60%, amber from 60% (filling up), red-orange from 85%
// (near auto-compact: start fresh or compact). Pointed at, it widens into a Compact button that is the same gauge
// (its fill is the context in use); a click opens the Compact card (compactHTML). It's drawn open while pointed at
// or while its card is up, so the rebuild every second doesn't replay the widening.
function contextRing(s) {
  const a = s.agent || {}, tokens = a.tokens, model = a.model;
  if (!tokens) return '';
  const window = core.agent.contextWindow(model, tokens), pct = Math.min(100, Math.round(tokens / window * 100));
  const color = pct >= 85 ? GAUGE.limit : pct >= 60 ? GAUGE.warning : GAUGE.normal;
  const r = 5, length = 2 * Math.PI * r, left = Math.max(0, core.agent.compactLimit(a) - tokens);
  const open = state.hoverCtx === s.sessionId || state.compactOpen[s.sessionId] ? ' open' : '';
  const title = `${pct}% · ${kTokens(tokens)} of ${kTokens(window)} tokens in context`
    + ` · ${kTokens(left)} left before auto-compact`;
  return `<span class="ctx${open}" data-ctx="${esc(s.sessionId)}" title="${title}"`
    + ` style="color:${color};--fill:${pct}%">
      <svg width="12" height="12" viewBox="0 0 12 12">`
    + `<circle cx="6" cy="6" r="${r}" fill="none" style="stroke:var(--ring-track)" stroke-width="1.6"/>
      <circle cx="6" cy="6" r="${r}" fill="none" style="stroke:${color}" stroke-width="1.6" stroke-linecap="round"
              stroke-dasharray="${(length * pct / 100).toFixed(2)} ${length.toFixed(2)}"/></svg>`
    + '<span class="ctx-label">Compact</span></span>';
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
    + (note ? `<div class="c-note">${esc(note)}</div>` : '') + '</div>';
}

// A choice sends /compact, once the card has been up long enough to be seen; × closes it; a press in its box puts the
// caret there, as usual.
function pressCompactCard(card, e) {
  const sid = card.dataset.compact, button = e.target.closest('button');
  if (!button) return;
  e.preventDefault();
  if (button.classList.contains('q-close')) return toggleCompact(sid);
  if (justShown('compact:' + sid)) return;  // only just opened: not seen yet
  const level = COMPACT_LEVELS[+button.dataset.level];
  if (level) sendCompact(sid, level[0]);
}

// A /compact sent from the Compact card didn't go through: the card opens again, saying why.
window.compactNote = (sid, text) => { state.compactOpen[sid] = true; state.compactNotes[sid] = text; render(); };

// ---- What it plugs into ----

core.slots.setup.push((row) => agentSetupHTML(row.s));
// The setup line counts as changed when the model, effort or mode does (its labels cross-fade), not the ring.
core.lines['.setup'] = { text: (el) => el.querySelector('.agent')?.textContent,
                         swap: (el) => el.querySelector('.agent') };
// The Compact card comes after a request waiting on the row, and closes for Deploy's set-up card.
core.rowCards.push({
  name: 'compact', order: 20,
  wants: (row) => !!state.compactOpen[row.s.sessionId],
  html: (row) => compactHTML(row.s),
  close(sid) { delete state.compactOpen[sid]; },
});
core.presses.push(['.pick[data-pick]', pressPick],
                  ['.ctx[data-ctx]', (ring, e) => { e.preventDefault(); toggleCompact(ring.dataset.ctx); }],
                  ['.perm[data-compact]', pressCompactCard]);
// Words typed in the card's box are kept the same way as an answer's; Return sends them as the focus.
core.typing.push(['.c-focus', (box) => { state.compactFocus[box.closest('.perm').dataset.compact] = box.value; }]);
core.returns.push(['.c-focus', (box) => {
  if (box.value.trim()) sendCompact(box.closest('.perm').dataset.compact, box.value.trim());
}]);
core.pointerTargets.push('.pick');
// The ring pointed at widens into its Compact button, and stays wide while its card is up.
core.pointerWatchers.push((el) => {
  state.hoverCtx = el?.closest('.ctx[data-ctx]')?.dataset.ctx || null;
  for (const ring of document.querySelectorAll('.ctx[data-ctx]'))
    ring.classList.toggle('open', ring.dataset.ctx === state.hoverCtx || !!state.compactOpen[ring.dataset.ctx]);
});
core.forgotten.keys.push('compactOpen', 'compactNotes', 'compactFocus');
core.forgotten.prefixes.push('compact');

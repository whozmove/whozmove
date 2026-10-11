// The cards on a row (a request, a question, Compact) and "Switch model?": their HTML and what they send back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The Compact card. Claude Code has one compaction, `/compact`, whose optional words steer its summary: the three
// choices say how much it keeps (the last two add instructions), and the box takes a focus in your own words. A
// choice goes in as it would be typed, while the session is idle. A refusal, or a compaction that doesn't go
// through, comes back as a note on the card.
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
  const left = Math.max(0, compactLimit(a) - (a.tokens || 0));
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

// A tool waiting for an OK, from the permission hook (Claude shows its own prompt too; whichever is answered first
// counts), with Deny and Allow once, never "always". A click on a card that has only just appeared doesn't count:
// it may have taken the place of the one being answered, and it hasn't been seen yet. An answered card folds away
// at once, and comes back after 5s if the request is still waiting.
const FRESH_MS = 800;
function justShown(id) { return Date.now() - (state.shownAt[id] || 0) < FRESH_MS; }
function answered(id, how) { state.answering[id] = how; state.answeredAt[id] = Date.now(); }
function folded(id) { return state.answering[id] && Date.now() - state.answeredAt[id] < 5000; }
// What a request would do, in full, since Allow once allows exactly that: the command (and, in its title, whether
// it would run in the background or outside the sandbox), the change to a file (the lines it takes out, −, and
// puts in, +), the whole of a file being written, the page and what's asked of it. A request the panel got cut
// short (very long input) can't be allowed here, only in Claude.
function askHTML(ask) {
  if (ask.tool === 'AskUserQuestion') return quizHTML(ask);
  state.shownAt[ask.id] ??= Date.now();
  const i = ask.input || {}, tool = ask.tool || '', name = (p) => esc(base(p || ''));
  const lines = (text, cls, mark) =>
    String(text ?? '').split('\n').map((l) => `<span class="${cls}">${mark} ${esc(l)}</span>`).join('\n');
  const change = (e) => (e.replace_all ? '(every occurrence)\n' : '')
    + lines(e.old_string, 'ln-del', '−') + '\n' + lines(e.new_string, 'ln-add', '+');
  let title, detail = esc(i.file_path || i.notebook_path || i.path || i.url || i.query || i.command || '');
  if (tool === 'Bash') {
    const how = [i.run_in_background && 'in the background', i.dangerouslyDisableSandbox && 'outside the sandbox']
      .filter(Boolean).join(', ');
    title = `Run a command${how ? ' ' + how : ''}?`;
  } else if (tool === 'Edit') { title = `Edit ${name(i.file_path)}?`; detail += '\n\n' + change(i); }
  else if (tool === 'MultiEdit') {
    title = `Edit ${name(i.file_path)}?`;
    detail += (i.edits || []).map((e) => '\n\n' + change(e)).join('');
  }
  else if (tool === 'NotebookEdit') {
    title = `Edit ${name(i.notebook_path)}?`;
    const where = [i.edit_mode, i.cell_type, i.cell_id && `cell ${i.cell_id}`].filter(Boolean).join(' · ');
    detail += `\n\n${esc(where)}\n${esc(i.new_source ?? '')}`;
  } else if (tool === 'Write') { title = `Write ${name(i.file_path)}?`; detail += '\n\n' + esc(i.content ?? ''); }
  else if (tool === 'Read') title = `Read ${name(i.file_path)}?`;
  else if (tool === 'WebFetch') {
    title = `Fetch from ${esc((/\/\/([^/]+)/.exec(i.url || '') || [])[1] || 'the web')}?`;
    if (i.prompt) detail += '\n\n' + esc(i.prompt);
  } else if (tool === 'WebSearch') title = 'Search the web?';
  else if (tool.startsWith('mcp__')) {
    const [, server, action] = tool.split('__');
    title = `Use ${esc(server)}: ${esc((action || '').replace(/_/g, ' '))}?`;
    detail = esc(JSON.stringify(i, null, 2));
  } else { title = `Use ${esc(tool)}?`; detail = esc(JSON.stringify(i, null, 2)); }
  const why = tool === 'Bash' && i.description ? `<div class="perm-why">${esc(i.description)}</div>` : '';
  const sent = state.answering[ask.id];
  const allow = ask.truncated ? '<span class="perm-sent">Too long to show in full: allow it in Claude</span>'
                              : '<button class="perm-allow">Allow once</button>';
  const actions = sent ? `<span class="perm-sent">${sent === 'allow' ? 'Allowing…' : 'Denying…'}</span>`
                       : `<button class="perm-deny">Deny</button>${allow}`;
  return `<div class="perm" data-ask="${esc(ask.id)}"><div class="perm-title">${title}</div>${why}
      <pre class="perm-detail">${detail}</pre>
      <div class="perm-actions">${actions}</div></div>`;
}

// Claude's questions (its question tool, through the same hook), one at a time as in Claude's own box: options to
// pick from or a box to type an answer in, then Next or Skip, and Submit on the last. Back returns to the one
// before, its answer still there to change; × dismisses them all. Picks, typing and the step are kept in the page's
// state (quiz), so the rebuild every second keeps them.
function quizState(id) { return state.quiz[id] || (state.quiz[id] = { step: 0, picks: {}, typed: {}, skipped: {} }); }
// A question's kind (choice, text or number) and default, by Claude Code's names for them (kind,
// defaultValue) or the older ones (type, default).
const kindOf = (q) => q.kind || q.type || 'choice';
const defaultOf = (q) => q.defaultValue ?? q.default;

function quizHTML(ask) {
  state.shownAt[ask.id] ??= Date.now();
  const input = ask.input || {}, questions = (input.questions || []).slice(0, 4), st = quizState(ask.id);
  const qi = Math.min(st.step || 0, questions.length - 1), q = questions[qi] || {}, final = qi === questions.length - 1;
  const type = kindOf(q), typed = st.typed[qi] ?? '';
  const count = questions.length > 1 ? `<span class="q-count">${qi + 1}/${questions.length}</span>`
              : q.header ? `<span class="q-chip">${esc(q.header)}</span>` : '';
  // Once the answers are sent, there's nothing to dismiss.
  const close = state.answering[ask.id] ? '' : `<button class="q-close" title="Dismiss without answering">×</button>`;
  const head = `<div class="q-top">${count}<span class="q-head">${esc(q.question)}</span>${close}</div>`
    + (q.description ? `<div class="q-help">${esc(q.description)}</div>` : '');
  let answer;
  if (type === 'number') {
    const value = st.typed[qi] !== undefined ? typed : (defaultOf(q) ?? q.min ?? '');
    const unit = q.unit ? `<span class="q-unit">${esc(q.unit)}</span>` : '';
    answer = `<div class="q-number"><input class="q-type" type="number" data-q="${qi}" min="${esc(q.min ?? '')}"`
      + ` max="${esc(q.max ?? '')}"
        step="${esc(q.step ?? 1)}" value="${esc(value)}">${unit}</div>`;
  } else {
    const picks = st.picks[qi] || [];
    const option = (o, oi) => `<button class="opt${picks.includes(oi) ? ' on' : ''}" data-q="${qi}" data-o="${oi}">`
      + `<span class="opt-label">${esc(o.label)}</span>`
      + (o.description ? `<span class="opt-desc">${esc(o.description)}</span>` : '') + '</button>';
    const options = type === 'text' ? ''
      : `<div class="q-opts${q.multiSelect ? ' multi' : ''}">` + (q.options || []).map(option).join('') + '</div>';
    const placeholder = type === 'text' ? (q.placeholder || 'Your answer') : 'Or type your own answer';
    const value = type === 'text' && st.typed[qi] === undefined ? defaultOf(q) ?? '' : typed;
    answer = `${options}<input class="q-type" data-q="${qi}" placeholder="${esc(placeholder)}" value="${esc(value)}">`;
  }
  const sent = state.answering[ask.id];
  const next = `<button class="q-next perm-allow"${hasAnswer(q, st, qi) ? '' : ' disabled'}>`
    + `${final ? 'Submit' : 'Next'}</button>`;
  const actions = sent ? `<span class="perm-sent">${sent === 'deny' ? 'Dismissing…' : 'Sending…'}</span>`
    : (qi > 0 ? '<button class="q-back">Back</button>' : '') + '<button class="q-skip">Skip</button>' + next;
  const title = input.title ? `<div class="q-title">${esc(input.title)}</div>` : '';
  return `<div class="perm quiz" data-ask="${esc(ask.id)}">${title}
      <div class="q" data-q="${qi}">${head}${answer}</div><div class="perm-actions">${actions}</div></div>`;
}

// A question's answer as Claude's question box sends it, or '' if there isn't one yet. Words typed in win over a
// pick, and several picks are joined with commas; a number is a plain number within its range, and a number or
// text question left as it was answers with its default.
function answerTo(q, st, qi) {
  const typed = String(st.typed[qi] ?? '').trim(), kind = kindOf(q);
  if (kind === 'number') {
    const value = st.typed[qi] !== undefined ? typed : String(defaultOf(q) ?? q.min ?? '').trim(), n = Number(value);
    const inRange = Number.isFinite(n) && !(q.min != null && n < q.min) && !(q.max != null && n > q.max);
    return value !== '' && inRange ? String(n) : '';
  }
  if (kind === 'text') return st.typed[qi] !== undefined ? typed : String(defaultOf(q) ?? '').trim();
  return typed || (st.picks[qi] || []).map((oi) => q.options?.[oi]?.label).filter(Boolean).join(', ');
}

// Whether the question on screen has an answer yet: Next / Submit wait for one (Skip is there to leave it).
function hasAnswer(q, st, qi) { return answerTo(q, st, qi) !== ''; }

// The answers as Claude's question box sends them: question text -> answer. Skipped ones are left out.
function quizAnswers(ask) {
  const st = quizState(ask.id), answers = {};
  (ask.input?.questions || []).slice(0, 4).forEach((q, qi) => {
    const value = st.skipped[qi] ? '' : answerTo(q, st, qi);
    if (value) answers[q.question] = value;
  });
  return answers;
}

// Claude's "Switch model?" (switching re-reads a cached conversation), asked in the panel instead of in Claude.
const ask = document.getElementById('ask');

function showSwitchQuestion({ sessionId, from, to }) {
  state.asking = { sessionId, never: false };
  const was = esc(modelName(from) || 'its model'), now = esc(modelName(to) || to);
  ask.innerHTML = `<h3>Switch model?</h3>
      <p>This session is cached for ${was}. Switching to ${now} means
        Claude re-reads the whole session on your next message, which uses more of your limit.</p>
      <div class="never"><span class="box"></span>Don't ask again</div>
      <div class="buttons"><button class="cancel">Cancel</button><button class="go">Switch model</button></div>`;
  ask.hidden = false;
  placeAsk();
  reportHeight();
}

// Just below its row, or above it when there's no room below.
function placeAsk() {
  const row = [...document.querySelectorAll('.row')].find((r) => r.dataset.id === state.asking.sessionId);
  const r = row?.getBoundingClientRect(), h = ask.offsetHeight;
  let top = r ? r.bottom + 4 : 56;
  if (top + h + 8 > state.panelMax) top = Math.max(6, (r ? r.top : 56) - h - 4);
  ask.style.top = top + 'px';
  state.askBottom = Math.ceil(top + h + 8);
}

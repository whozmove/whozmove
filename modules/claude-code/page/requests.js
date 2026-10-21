// A Claude Code session's requests on its row: a tool waiting for your OK, its questions, and a plan waiting for your
// OK; and your answers, which go back through the permission hook (answerAsk).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each question card's step, picks, typing and skips, by ask id (quizState).
moduleState({ quiz: {} });

// A tool waiting for an OK, from the permission hook (Claude shows its own prompt too; whichever is answered first
// counts), with Deny and Allow once, never "always". A click on a card that has only just appeared doesn't count
// (justShown): it may have taken the place of the one being answered, and it hasn't been seen yet. An answered card
// folds away at once, and comes back after 5s if the request is still waiting (folded).
//
// What a request would do, in full, since Allow once allows exactly that: the command (and, in its title, whether
// it would run in the background or outside the sandbox), the change to a file (the lines it takes out, −, and
// puts in, +), the whole of a file being written, the page and what's asked of it, and any other tool's input
// field by field. A request the panel got cut short (very long input) says so, and Allow once still allows all
// of it, as Claude's own prompt does.
function askHTML(ask) {
  if (ask.tool === 'AskUserQuestion') return quizHTML(ask);
  if (ask.tool === 'ExitPlanMode') return planAskHTML(ask);
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
    detail = fieldsHTML(i);
  } else { title = `Use ${esc(tool)}?`; detail = fieldsHTML(i); }
  const why = tool === 'Bash' && i.description ? `<div class="perm-why">${esc(i.description)}</div>` : '';
  const sent = state.answering[ask.id];
  const actions = sent ? `<span class="perm-sent">${sent === 'allow' ? 'Allowing…' : 'Denying…'}</span>`
                       : '<button class="perm-deny">Deny</button><button class="perm-allow">Allow once</button>';
  // A tool that asks with no input at all has nothing to show but its title.
  const box = detail ? `<pre class="perm-detail">${detail}</pre>` : '';
  const cut = ask.truncated ? '<div class="perm-cut">Content too large to show in full</div>' : '';
  return `<div class="perm" data-ask="${esc(ask.id)}"><div class="perm-title">${title}</div>${why}
      ${box}${cut}
      <div class="perm-actions">${actions}</div></div>`;
}

// A plan waiting for your OK: its title, and the way to it. Approving happens in the session, since Claude Code takes
// a plan's approval only from its own prompt; the reader can send it back with notes, or stop it.
function planAskHTML(ask) {
  state.shownAt[ask.id] ??= Date.now();
  const title = (String(ask.input?.plan || '').match(/^\s*#+\s*(.+)$/m) || [])[1] || 'Its plan';
  const sent = state.answering[ask.id];
  const actions = sent ? '<span class="perm-sent">Sent</span>'
    : '<button class="perm-go">Take me there</button><button class="perm-read perm-allow">Read plan</button>';
  return `<div class="perm plan-ask" data-ask="${esc(ask.id)}"><div class="perm-title">Claude wants your OK on its plan</div>
      <div class="perm-why">${esc(title)}</div><div class="perm-why">Approving happens in the session; from the plan you
      can send it back with notes, or stop it.</div>
      <div class="perm-actions">${actions}</div></div>`;
}

// A tool's input as Claude's own prompt lists it: each field under its name ("chart_code" as "Chart code"), a
// text as it is, line breaks and all, a list of texts one to a line, and anything else as JSON. The app doesn't
// keep the order the tool gave them in, so the shortest come first and the long ones (the code, the message) last.
function fieldsHTML(input) {
  const label = (key) => {
    const words = key.replace(/_+/g, ' ').replace(/([a-z\d])([A-Z])/g, '$1 $2').trim().split(/\s+/)
      .map((w) => (/^[A-Z][a-z]/.test(w) ? w.toLowerCase() : w)).join(' ');  // "maxResults" too, but "URL" stays
    return words.charAt(0).toUpperCase() + words.slice(1);
  };
  const text = (v) => (typeof v === 'string' ? v
    : Array.isArray(v) && v.length && v.every((x) => typeof x === 'string') ? v.join('\n')
    : v && typeof v === 'object' ? JSON.stringify(v, null, 2) : String(v));
  return Object.entries(input).map(([key, v]) => [key, text(v)]).sort((a, b) => a[1].length - b[1].length)
    .map(([key, v]) => `<span class="perm-field">${esc(label(key))}</span>${esc(v)}`).join('');
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

// ---- Presses ----

// A request or a question on a row. A button that has only just appeared doesn't count yet. Reading the card
// (scrolling, selecting) doesn't open the conversation.
function pressRequest(card, e) {
  const button = e.target.closest('button');
  if (button && justShown(card.dataset.ask)) return e.preventDefault();
  const option = e.target.closest('.opt[data-o]');
  if (option) return pickOption(option, e);
  const step = e.target.closest('.q-back, .q-skip, .q-next, .q-close');
  if (step) return stepQuestion(step, e);
  // A plan: read it beside the list (the reader opens on the plan waiting), or go to the session to approve it.
  const s = state.last.sessions.find((x) => x.ask?.id === card.dataset.ask);
  if (button?.classList.contains('perm-read') && s) {
    e.preventDefault();
    return openReader(s.sessionId, null, 'writings');
  }
  if (button?.classList.contains('perm-go') && s) { e.preventDefault(); return openSession(s); }
  if (button) answerRequest(button, e);
}

// An option of a question: one pick, or several where the question takes them.
function pickOption(option, e) {
  e.preventDefault();
  const id = option.closest('.perm').dataset.ask, st = quizState(id), qi = +option.dataset.q, oi = +option.dataset.o;
  const multi = !!option.closest('.multi'), picks = st.picks[qi] || [];
  if (multi) setPicks(id, qi, picks.includes(oi) ? picks.filter((x) => x !== oi) : [...picks, oi]);
  else setPicks(id, qi, picks.includes(oi) ? [] : [oi]);
}

// A question's picks, from a press or a key. They replace words typed for that question, and answering a question
// that was skipped (after Back) un-skips it.
function setPicks(id, qi, picks) {
  const st = quizState(id);
  st.picks[qi] = picks;
  st.typed[qi] = '';
  delete st.skipped[qi];
  render();
}

// The picks a key makes among a question's `count` options, given the ones made: 1 to 9 picks that option, or where
// the question takes several, adds it or takes it out; ↓ and ↑ move a single pick to the next option or the one before
// (from none, the first or the last). null for any other key, a number past the options, or a move with nowhere to go.
function keyPick(count, multi, picks, key) {
  if (/^[1-9]$/.test(key)) {
    const oi = +key - 1;
    if (oi >= count) return null;
    return multi ? (picks.includes(oi) ? picks.filter((x) => x !== oi) : [...picks, oi]) : [oi];
  }
  if (multi || !count || (key !== 'ArrowDown' && key !== 'ArrowUp')) return null;
  const down = key === 'ArrowDown', at = picks.length ? picks[0] : down ? -1 : count;
  const to = Math.max(0, Math.min(count - 1, at + (down ? 1 : -1)));
  return to === picks[0] ? null : [to];
}

// Keys on a request or question card once it's been pressed (core.keyCards): on a question with options, 1 to 9 and
// ↓ ↑ pick (keyPick). Return presses its main button (Next, Submit or Allow once) and Esc lets the keyboard go, as the
// core does for any such card.
function keyOnRequest(card, e) {
  const q = card.querySelector('.q[data-q]'), count = card.querySelectorAll('.opt[data-o]').length;
  if (!q || !count) return false;
  const id = card.dataset.ask, qi = +q.dataset.q;
  const picks = keyPick(count, !!card.querySelector('.q-opts.multi'), quizState(id).picks[qi] || [], e.key);
  if (picks) setPicks(id, qi, picks);
  return !!picks || /^[1-9]$/.test(e.key) || e.key === 'ArrowDown' || e.key === 'ArrowUp';
}

// Whether a press on a request or question card answers it, rather than only picking or moving between its questions:
// Allow once or Deny, ×, or Submit or Skip on the last question. Such a press doesn't take the keyboard, and gives it
// back if the card had it.
function pressAnswers(card, target) {
  const button = target.closest('button');
  if (!button || button.disabled || button.matches('.opt, .q-back')) return false;
  if (!button.matches('.q-next, .q-skip')) return true;
  const n = (state.last.sessions.find((x) => x.ask?.id === card.dataset.ask)?.ask?.input?.questions || []).slice(0, 4)
    .length;
  return quizState(card.dataset.ask).step >= n - 1;
}

// Back, Skip, Next or Submit, and × (which dismisses all the questions). Once sent, the first answer stands.
function stepQuestion(step, e) {
  e.preventDefault();
  if (step.disabled) return;  // Next / Submit wait for an answer
  const id = step.closest('.perm').dataset.ask, st = quizState(id);
  const ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  const n = (ask?.input?.questions || []).slice(0, 4).length;
  if (state.answering[id]) return;
  if (step.classList.contains('q-back')) {
    st.step = Math.max(0, st.step - 1);  // answers stay as they were, to change or keep
  } else if (step.classList.contains('q-close')) {
    answered(id, 'deny');
    native({ type: 'answerAsk', id, allow: false });
  } else {
    if (step.classList.contains('q-skip')) {
      delete st.picks[st.step];
      delete st.typed[st.step];
      st.skipped[st.step] = true;
    } else {
      delete st.skipped[st.step];
    }
    if (st.step < n - 1) st.step++;
    else if (ask) { answered(id, 'allow'); native({ type: 'answerAsk', id, allow: true, answers: quizAnswers(ask) }); }
  }
  render();
}

// Deny or Allow once on a request; on a question card, the answers go with it.
function answerRequest(button, e) {
  e.preventDefault();
  const card = button.closest('.perm'), id = card.dataset.ask, allow = button.classList.contains('perm-allow');
  const ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  answered(id, allow ? 'allow' : 'deny');
  const answers = allow && card.classList.contains('quiz') && ask ? { answers: quizAnswers(ask) } : {};
  native({ type: 'answerAsk', id, allow, ...answers });
  render();
}

// An answer typed in: kept in the question's state (so rebuilds keep it), and it replaces that question's picks.
function typeAnswer(box) {
  const id = box.closest('.perm').dataset.ask, st = quizState(id), qi = +box.dataset.q;
  st.typed[qi] = box.value;
  delete st.skipped[qi];
  if (box.value && box.type !== 'number' && (st.picks[qi] || []).length) {
    st.picks[qi] = [];
    box.closest('.q').querySelectorAll('.opt.on').forEach((o) => o.classList.remove('on'));
  }
  const q = state.last.sessions.find((x) => x.ask?.id === id)?.ask?.input?.questions?.[qi];
  const next = box.closest('.perm').querySelector('.q-next');
  if (next && q) next.disabled = !hasAnswer(q, st, qi);
}

// ---- What it plugs into ----

// The most pressing of a row's cards: while a request waits, it takes the place under the chat, even folded away just
// after an answer.
core.rowCards.push({
  name: 'request', order: 10,
  wants: (row) => !!row.s.ask,
  html: (row) => (folded(row.s.ask.id) ? '' : askHTML(row.s.ask)),
});
core.presses.push(['.perm[data-ask]', pressRequest]);
// A request or a question takes the keyboard once pressed, but where the press answers it, so its keys answer it here
// rather than going to the app in front, where Claude's own copy of it waits; a plan's card has nothing to key.
core.keyCards.push({
  card: '.perm[data-ask]:not(.plan-ask)',
  id: (card) => card.dataset.ask,
  open: (card) => !state.answering[card.dataset.ask],
  takes: (card, target) => !pressAnswers(card, target),
  key: keyOnRequest,
});
core.typing.push(['.perm[data-ask] .q-type', typeAnswer]);
core.forgotten.keys.push('quiz');

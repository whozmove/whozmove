// What a press, a key or typing does: one small handler for each kind of thing pressed.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

function toggleIdle() {
  state.showIdle = !state.showIdle;
  store.set('showIdle', state.showIdle);
  slideGroup(document.querySelector('.group.toggle'), !state.showIdle);
}

function toggleProject(key) {
  if (state.closedProjects[key]) delete state.closedProjects[key];
  else state.closedProjects[key] = true;
  store.set('closedProjects', state.closedProjects);
  const header = [...document.querySelectorAll('.project')].find((p) => p.dataset.key === key);
  slideGroup(header, !!state.closedProjects[key]);
}

// What a press on the list does, by the kind of thing pressed: the first of these the press is inside handles it
// (so a project's ＋ comes before the project, and a PR before its row). mousedown, not click: the list is rebuilt
// every second, and a click whose press and release land on different (rebuilt) elements never fires.
const list = document.getElementById('list');
const PRESSES = [
  ['.group.toggle', () => toggleIdle()],
  ['.add[data-folder]', (add, e) => native({ type: 'newSession', folder: add.dataset.folder, terminal: e.altKey })],
  ['.project[data-key]', (project) => toggleProject(project.dataset.key)],
  ['.pr[data-url]', (pr) => native({ type: 'openPR', url: pr.dataset.url })],
  ['.ctx[data-ctx]', (ring, e) => { e.preventDefault(); toggleCompact(ring.dataset.ctx); }],
  ['.perm[data-compact]', pressCompactCard],
  ['.perm[data-ask]', pressRequest],
  ['.row', pressRow],
];

list.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  for (const [selector, press] of PRESSES) {
    const target = e.target.closest(selector);
    if (target) return press(target, e);
  }
});

// The Compact card: a choice sends /compact, once the card has been up long enough to be seen; × closes it; a press
// in its box puts the caret there, as usual.
function pressCompactCard(card, e) {
  const sid = card.dataset.compact, button = e.target.closest('button');
  if (!button) return;
  e.preventDefault();
  if (button.classList.contains('q-close')) return toggleCompact(sid);
  if (justShown('compact:' + sid)) return;  // only just opened: not seen yet
  const level = COMPACT_LEVELS[+button.dataset.level];
  if (level) sendCompact(sid, level[0]);
}

// A request or a question on a row. A button that has only just appeared doesn't count yet. Reading the card
// (scrolling, selecting) doesn't open the conversation.
function pressRequest(card, e) {
  const button = e.target.closest('button');
  if (button && justShown(card.dataset.ask)) return e.preventDefault();
  const option = e.target.closest('.opt[data-o]');
  if (option) return pickOption(option, e);
  const step = e.target.closest('.q-back, .q-skip, .q-next, .q-close');
  if (step) return stepQuestion(step, e);
  if (button) answerRequest(button, e);
}

// An option of a question: one pick, or several where the question takes them. A pick replaces words typed for
// that question, and answering a question that was skipped (after Back) un-skips it.
function pickOption(option, e) {
  e.preventDefault();
  const id = option.closest('.perm').dataset.ask, st = quizState(id), qi = +option.dataset.q, oi = +option.dataset.o;
  const multi = !!option.closest('.multi'), picks = st.picks[qi] || [];
  if (multi) st.picks[qi] = picks.includes(oi) ? picks.filter((x) => x !== oi) : [...picks, oi];
  else st.picks[qi] = picks.includes(oi) ? [] : [oi];
  st.typed[qi] = '';
  delete st.skipped[qi];
  render();
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

// A row: its model, effort or mode opens the app's menu below the label; anywhere else opens the session, which
// becomes the one you're on (held there if it was under Your turn; the one you were on before is marked idle).
function pressRow(row, e) {
  const s = state.last.sessions.find((x) => x.sessionId === row.dataset.id);
  if (!s) return;
  const pick = e.target.closest('.pick[data-pick]');
  if (pick) {
    const r = pick.getBoundingClientRect();
    native({ type: 'pick', field: pick.dataset.pick, sessionId: s.sessionId, x: r.left - 4, y: r.bottom + 4 });
    return;
  }
  state.seen[s.sessionId] = Date.now();
  store.set('seen', state.seen);
  if (s.entrypoint === 'claude-desktop') state.opening = { sessionId: s.sessionId, at: Date.now() };
  goTo(s.sessionId);
  native({ type: 'open', sessionId: s.sessionId, hostSessionId: s.hostSessionId, pid: s.pid, entrypoint: s.entrypoint,
           cwd: s.cwd, name: s.name });
  render();
}

// The header's chevron folds the panel to its header, and opens it again.
document.querySelector('header .chev').addEventListener('click', () => toggleCollapsed());

// "Switch model?": Don't ask again ticks on and off; Switch model or Cancel answers, and the card goes.
ask.addEventListener('mousedown', (e) => {
  if (!state.asking) return;
  if (e.target.closest('.never')) {
    state.asking.never = !state.asking.never;
    ask.querySelector('.never').classList.toggle('on', state.asking.never);
    return;
  }
  const go = !!e.target.closest('.go');
  if (!go && !e.target.closest('.cancel')) return;
  native({ type: 'switchAnswer', sessionId: state.asking.sessionId, ok: go, never: go && state.asking.never });
  state.asking = null;
  ask.hidden = true;
  reportHeight();
});

// An answer typed in: kept in the question's state (so rebuilds keep it), and it replaces that question's picks.
// Words typed in the Compact card's box are kept the same way.
list.addEventListener('input', (e) => {
  const box = e.target.closest('.q-type');
  if (!box) return;
  if (box.classList.contains('c-focus')) {
    state.compactFocus[box.closest('.perm').dataset.compact] = box.value;
    return;
  }
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
});

// The panel takes the keyboard only while one of its own text boxes (an answer, a compact focus) is typed in, and
// gives it back on leaving the box, so a click on the panel never keeps keystrokes from the app being typed in.
// Leaving waits a moment: the rebuild every second swaps the box for a fresh one, and focuses that.
function wantKeyboard(on) {
  clearTimeout(state.keyboardTimer);
  if (on && !state.keyboardWanted) { state.keyboardWanted = true; native({ type: 'keyboard', on: true }); }
  if (!on) state.keyboardTimer = setTimeout(() => {
    if (document.activeElement?.closest?.('.q-type') || !state.keyboardWanted) return;
    state.keyboardWanted = false;
    native({ type: 'keyboard', on: false });
  }, 150);
}
// A press on a box asks for it before the press focuses the box (a window without the keyboard gets no focus
// events, so they can't be what asks); a press anywhere else here gives it back.
document.addEventListener('mousedown', (e) => {
  if (e.button === 0) wantKeyboard(!!e.target.closest?.('.q-type'));
}, true);
list.addEventListener('focusin', (e) => { if (e.target.closest('.q-type')) wantKeyboard(true); });
list.addEventListener('focusout', (e) => { if (e.target.closest('.q-type')) wantKeyboard(false); });

// While a word is being composed (an input method for Japanese, Chinese, …), the list isn't rebuilt: a
// rebuild would throw the half-composed word away.
list.addEventListener('compositionstart', () => { state.composing = true; });
list.addEventListener('compositionend', () => {
  state.composing = false;
  if (!state.sliding) render();
});

// Return in an answer box presses the card's Next, Submit or Allow; in the Compact card's box it sends that focus.
list.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.isComposing || e.keyCode === 229 || !e.target.closest('.q-type')) return;
  e.preventDefault();
  if (e.target.classList.contains('c-focus')) {
    if (e.target.value.trim()) sendCompact(e.target.closest('.perm').dataset.compact, e.target.value.trim());
    return;
  }
  const allow = e.target.closest('.perm').querySelector('.perm-allow');
  allow?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
});

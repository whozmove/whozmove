// What a press, a key or typing does on the list: the modules' handlers first (core.presses, core.typing,
// core.returns), then the core's own; and when the panel takes the keyboard.
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

// What a press on the list does, by the kind of thing pressed: the first of these the press is inside handles it. The
// modules' come first (core.presses), as what they draw sits inside a row or a project's header (a project's ＋, a PR,
// a card), and the core's last: a group's header, a project's, and the row itself. mousedown, not click: the list is
// rebuilt every second, and a click whose press and release land on different (rebuilt) elements never fires.
const list = document.getElementById('list');
const PRESSES = [
  ['.group.toggle', () => toggleIdle()],
  ['.project[data-key]', (project) => toggleProject(project.dataset.key)],
  ['.row', pressRow],
];

list.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  keepInPlace(e.target.closest('.row[data-id]')?.dataset.id);  // whatever the press does, its row stays where it is
  for (const [selector, press] of [...core.presses, ...PRESSES]) {
    const target = e.target.closest(selector);
    if (target) return press(target, e);
  }
});

// A row, anywhere a module doesn't take the press: opens the session, which becomes the one you're on.
function pressRow(row) {
  const s = state.last.sessions.find((x) => x.sessionId === row.dataset.id);
  if (s) openSession(s);
}

// Brings a session forward in its app, and makes it the one you're on: a row's press, and the reader's Take me there.
// Its row stays where it is (keepInPlace).
function openSession(s) {
  markRead(s.sessionId, Date.now());
  if (hostOf(s).marksOpenAtOnce) state.opening = { sessionId: s.sessionId, at: Date.now() };
  keepInPlace(s.sessionId);
  goTo(s.sessionId);
  native({ type: 'open', sessionId: s.sessionId, hostSessionId: s.hostSessionId, pid: s.pid, entrypoint: s.entrypoint,
           cwd: s.cwd, name: s.name });
  render();
}

// The header's chevron folds the panel to its header, and opens it again.
document.querySelector('header .chev').addEventListener('click', () => toggleCollapsed());

// A card's boxes on the list (an answer, a focus for /compact, a command for Deploy): what's typed in one is kept by
// the module whose card it is (core.typing), so rebuilds keep it.
const TEXT_BOX = '.q-type';
list.addEventListener('input', (e) => {
  const box = e.target.closest(TEXT_BOX);
  if (!box) return;
  for (const [selector, typed] of core.typing) if (box.matches(selector)) return typed(box, e);
});

// Return in a card's box does what its module says (core.returns), or presses the card's main button: Next, Submit,
// Allow once, Use this.
list.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.isComposing || e.keyCode === 229 || !e.target.closest(TEXT_BOX)) return;
  e.preventDefault();
  for (const [selector, returned] of core.returns) if (e.target.matches(selector)) return returned(e.target, e);
  const allow = e.target.closest('.perm').querySelector('.perm-allow');
  allow?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
});

// The panel takes the keyboard only while one of its own text boxes (a card's, or a module's elsewhere, as a new
// conversation's words: core.textBoxes) is typed in, and gives it back on leaving the box, so a click on the panel
// never keeps keystrokes from the app being typed in. Leaving waits a moment: the rebuild every second swaps the box
// for a fresh one, and focuses that.
const textBoxes = () => [TEXT_BOX, ...core.textBoxes].join(', ');
function wantKeyboard(on) {
  clearTimeout(state.keyboardTimer);
  if (on && !state.keyboardWanted) { state.keyboardWanted = true; native({ type: 'keyboard', on: true }); }
  if (!on) state.keyboardTimer = setTimeout(() => {
    if (document.activeElement?.closest?.(textBoxes()) || !state.keyboardWanted) return;
    state.keyboardWanted = false;
    native({ type: 'keyboard', on: false });
  }, 150);
}
// A press on a box asks for it before the press focuses the box (a window without the keyboard gets no focus
// events, so they can't be what asks), even if the page thinks it has it: Claude Desktop, brought forward to send a
// new conversation, takes it without the page knowing. A press anywhere else here gives it back.
document.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  const box = !!e.target.closest?.(textBoxes());
  if (box) state.keyboardWanted = false;
  wantKeyboard(box);
}, true);
list.addEventListener('focusin', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(true); });
list.addEventListener('focusout', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(false); });

// While a word is being composed (an input method for Japanese, Chinese, …), the list isn't rebuilt: a
// rebuild would throw the half-composed word away.
list.addEventListener('compositionstart', () => { state.composing = true; });
list.addEventListener('compositionend', () => {
  state.composing = false;
  if (!state.sliding) render();
});

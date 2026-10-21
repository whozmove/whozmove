// What a press, a key or typing does on the list: the modules' handlers first (core.presses, core.typing,
// core.returns), then the core's own; and when the panel takes the keyboard.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

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
  ['.step-note .note-way', pressNoteWay],
  ['.project[data-key]', (project) => toggleProject(project.dataset.key)],
  ['.row', pressRow],
];

// The button past why a step couldn't go in (a step's note, rows.js): the app takes the way past, and says how it went
// in the note's place. It waits to be seen first, as the note has only just come.
function pressNoteWay(button, e) {
  e.preventDefault();
  const sid = button.dataset.way, note = state.stepNotes[sid];
  if (!note || Date.now() - note.at < FRESH_MS) return;
  note.way = null;
  native({ type: 'wayPast', sessionId: sid });
  render();
}

// A row, anywhere a module doesn't take the press: opens the session, which becomes the one you're on.
function pressRow(row) {
  const s = state.last.sessions.find((x) => x.sessionId === row.dataset.id);
  if (s) openSession(s);
}

// Brings a session forward in its app, and makes it the one you're on: a row's press, and the reader's Take me there.
// Its row stays where it is (keepInPlace).
function openSession(s) {
  noteOnIt(s, Date.now(), Date.now());
  state.opening = { sessionId: s.sessionId, at: Date.now() };  // the one you're on at once (openedNow)
  keepInPlace(s.sessionId);
  goTo(s.sessionId);
  native({ type: 'open', sessionId: s.sessionId, hostSessionId: s.hostSessionId, pid: s.pid, entrypoint: s.entrypoint,
           cwd: s.cwd, name: s.name });
  render();
}

// The header's chevron folds the panel into the cat.
document.querySelector('header .chev').addEventListener('click', () => toggleCollapsed());

// The header's four squares turn the panel over to the apps on its back (app/core/PanelWindow.m), as they're pressed,
// as the back's rows turn it back. An open reader folds back first, and the panel turns once it has (readerClosed, in
// reader.js).
document.querySelector('header .apps').addEventListener('mousedown', (e) => { if (e.button === 0) turnToApps(); });
function turnToApps() {
  if (state.turned) return;
  if (state.reading) {
    state.turnAfterReader = true;
    return closeReader();
  }
  native({ type: 'turn', on: true });
}

// A card's boxes on the list (an answer, a focus for /compact, a command for Deploy): what's typed in one is kept by
// the module whose card it is (core.typing), so rebuilds keep it.
const TEXT_BOX = '.q-type';

// The panel takes the keyboard only while one of its own text boxes (a card's, or a module's elsewhere, as a new
// conversation's words: core.textBoxes) is typed in, or a card that answers to keys has been pressed (heldCard), and
// gives it back on leaving it, so a click on the panel never keeps keystrokes from the app being typed in. Leaving
// waits a moment: the rebuild every second swaps the box for a fresh one, and focuses that.
const textBoxes = () => [TEXT_BOX, ...core.textBoxes].join(', ');
const keepsKeyboard = () => !!document.activeElement?.closest?.(textBoxes()) || !!heldCard();
function wantKeyboard(on) {
  clearTimeout(state.keyboardTimer);
  if (on && !state.keyboardWanted) { state.keyboardWanted = true; native({ type: 'keyboard', on: true }); }
  if (!on) state.keyboardTimer = setTimeout(() => {
    if (keepsKeyboard() || !state.keyboardWanted) return;
    state.keyboardWanted = false;
    native({ type: 'keyboard', on: false });
  }, 150);
}

// The card pressed last that answers to keys (core.keyCards: a request or a question on a row), while it's still on
// the list and waits for you: found again by its id, as the list is rebuilt every second, and never on the copy of the
// row held at the list's edge. Once it's answered or gone, it's let go of.
function heldCard() {
  const held = state.keyCard;
  if (!held) return null;
  const card = [...list.querySelectorAll(held.kind.card)]
    .find((c) => c.closest('.row[data-id]') && held.kind.id(c) === held.id);
  if (card && held.kind.open(card)) return card;
  state.keyCard = null;
  return null;
}

// What a press on the list makes of the keyboard: a box asks for it before the press focuses the box (a window without
// the keyboard gets no focus events, so they can't be what asks), even if the page thinks it has it: Claude Desktop,
// brought forward to send a new conversation, takes it without the page knowing. So does a card that answers to keys,
// pressed anywhere but where the press answers it, once it has been seen (justShown: a card that has only just come
// may have taken the place of the one meant); only in the list, as a chat beside the folded cat (chats.js) is
// answered by its presses. A press anywhere else here gives it back.
document.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  const box = !!e.target.closest?.(textBoxes());
  state.keyCard = null;
  if (!box) {
    for (const kind of core.keyCards) {
      const card = e.target.closest?.(kind.card);
      if (!card?.closest('.row[data-id]') || !list.contains(card)) continue;
      const id = kind.id(card);
      if (kind.open(card) && kind.takes(card, e.target) && !justShown(id)) state.keyCard = { kind, id };
      break;
    }
  }
  if (box || state.keyCard) state.keyboardWanted = false;
  wantKeyboard(box || !!state.keyCard);
}, true);

// Keys on the card that has the keyboard, but for ⌘, ⌃ and ⌥ ones (copying what's selected on it): what its module
// says (core.keyCards' key), else Return presses its main button, as in its box, and Esc lets go of the keyboard,
// answering nothing.
document.addEventListener('keydown', (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey || e.isComposing || e.target.closest?.(textBoxes())) return;
  const card = heldCard();
  if (!card) return;
  if (state.keyCard.kind.key(card, e)) return e.preventDefault();
  if (e.key === 'Escape') {
    e.preventDefault();
    state.keyCard = null;
    wantKeyboard(false);
  } else if (e.key === 'Enter') {
    e.preventDefault();
    card.querySelector('.perm-allow')?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
  }
});
// The card that has the keyboard shows it, by its edge; once it's answered or gone, the keyboard goes back.
core.afterDraw.push(() => {
  const card = heldCard();
  for (const c of list.querySelectorAll('.has-keys')) if (c !== card) c.classList.remove('has-keys');
  card?.classList.add('has-keys');
  if (state.keyboardWanted && !keepsKeyboard()) wantKeyboard(false);
});

// The list, and wherever else a session's row is shown (the chats beside the folded cat, chats.js), takes presses,
// typing and Return the same way, so a row does the same wherever it is. While a word is being composed (an input
// method for Japanese, Chinese, …) in one of its boxes, nothing is rebuilt: a rebuild would throw the word away.
function takesPresses(el) {
  el.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    keepInPlace(e.target.closest('.row[data-id]')?.dataset.id);  // whatever the press does, its row stays where it is
    for (const [selector, press] of [...core.presses, ...PRESSES]) {
      const target = e.target.closest(selector);
      if (target) return press(target, e);
    }
  });
  el.addEventListener('input', (e) => {
    const box = e.target.closest(TEXT_BOX);
    if (!box) return;
    for (const [selector, typed] of core.typing) if (box.matches(selector)) return typed(box, e);
  });
  // Return in a card's box does what its module says (core.returns), or presses the card's main button: Next, Submit,
  // Allow once, Use this.
  el.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing || e.keyCode === 229 || !e.target.closest(TEXT_BOX)) return;
    e.preventDefault();
    for (const [selector, returned] of core.returns) if (e.target.matches(selector)) return returned(e.target, e);
    const allow = e.target.closest('.perm').querySelector('.perm-allow');
    allow?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
  });
  el.addEventListener('focusin', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(true); });
  el.addEventListener('focusout', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(false); });
  el.addEventListener('compositionstart', () => { state.composing = true; });
  el.addEventListener('compositionend', () => {
    state.composing = false;
    if (!state.sliding) render();
  });
}
takesPresses(list);

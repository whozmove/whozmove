// What a press, a key or typing does on the list: the modules' handlers first (core.presses, core.typing,
// core.returns), then the list's own. When the panel takes the keyboard is the keyboard part's (parts/keyboard).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

function toggleProject(key) {
  if (state.closedProjects[key]) delete state.closedProjects[key];
  else state.closedProjects[key] = true;
  store.set('closedProjects', state.closedProjects);
  const header = [...document.querySelectorAll('.project')].find((p) => p.dataset.key === key);
  // Drawn afresh once it has slid, even if the group is back as it was: the slide's sizes are on the group itself, not
  // in what's drawn.
  slideGroup(header, !!state.closedProjects[key], () => { state.drawing = null; render(); });
}

// What a press on the list does, by the kind of thing pressed: the first of these the press is inside handles it. The
// modules' come first (core.presses), as what they draw sits inside a row or a project's header (a project's ＋, a PR,
// a card), and the list's last: a group's header, a project's, and the row itself. mousedown, not click: the list is
// rebuilt whenever what it shows changes, any second, and a click whose press and release land on different (rebuilt)
// elements never fires.
const list = document.getElementById('list');
const PRESSES = [
  ['.step-note .note-way', pressNoteWay],
  ['.project[data-key]', (project) => toggleProject(project.dataset.key)],
  ['.row', pressRow],
];

// The button past why a step couldn't go in (a step's note, rows.js): the app takes the terminal's way past, and says
// how it went in the note's place; or, for a note whose button does something on the page (`go`), Take me there opens
// the session, as a press on its row does, and a module's does its own (core.noteWays). It waits to be seen first, as
// the note has only just come.
function pressNoteWay(button, e) {
  e.preventDefault();
  const sid = button.dataset.way, note = state.stepNotes[sid];
  if (!note || Date.now() - note.at < FRESH_MS) return;
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (note.go) {
    delete state.stepNotes[sid];
    if (s && note.go === 'open') return openSession(s);
    if (s) core.noteWays[note.go]?.(s);
    return render();
  }
  note.way = null;
  native({ type: 'wayPast', sessionId: sid });
  render();
}

// A row, anywhere a module doesn't take the press: opens the session, which becomes the one you're on.
function pressRow(row) {
  const s = state.last.sessions.find((x) => x.sessionId === row.dataset.id);
  if (s) openSession(s, { carryOn: true });
}

// Brings a session forward in its app, and makes it the one you're on: a row's press, and the reader's Take me there.
// Its row stays where it is (keepInPlace). Only a row's own press carries it on (`carryOn`): what a module has to say
// to a conversation opened again goes in then, never on a press only to look at it.
function openSession(s, { carryOn = false } = {}) {
  noteOnIt(s, Date.now(), Date.now());
  state.opening = { sessionId: s.sessionId, at: Date.now() };  // the one you're on at once (openedNow)
  keepInPlace(s.sessionId);
  goTo(s.sessionId);
  native({ type: 'open', sessionId: s.sessionId, hostSessionId: s.hostSessionId, pid: s.pid, entrypoint: s.entrypoint,
           cwd: s.cwd, name: s.name, ...(carryOn ? { carryOn: true } : {}) });
  render();
}

// The header's chevron folds the panel into the cat.
document.querySelector('header .chev').addEventListener('click', () => toggleCollapsed());

// The header's four squares turn the panel over to the apps on its back (PanelWindow+Turn.m), as they're pressed,
// as the back's rows turn it back; the pawn menu's Settings… turns it too (modules/apps). An open reader folds back
// first, and the panel turns once it has (readerClosed, in reader.js).
document.querySelector('header .apps').addEventListener('mousedown', (e) => { if (e.button === 0) turnToApps(); });
function turnToApps() {
  if (state.turned) return;
  if (state.reading) {
    state.turnAfterReader = true;
    return closeReader();
  }
  native({ type: 'turn', on: true });
}

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
  // Esc in a card's box goes to its module (core.escapes), the first that matches taking it, so nothing else does too.
  // An entry gets Esc only from a box inside its own card (its selector names its card's own box), so no module takes
  // Esc from another's. None matching: Esc does what it did before. Never while composing, where Esc is the input
  // method's.
  el.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || e.isComposing || e.keyCode === 229 || !e.target.closest(TEXT_BOX)) return;
    for (const [selector, escaped] of core.escapes) {
      if (!e.target.matches(selector)) continue;
      e.preventDefault();
      e.stopPropagation();
      return escaped(e.target, e);
    }
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

// The keyboard on the page: the boxes that take it, the card that has it once pressed, and asking the app for it
// or giving it back; and the keys on that card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A card's boxes on the list (an answer, a focus for /compact, a command for Deploy): what's typed in one is kept by
// the module whose card it is (core.typing), so rebuilds keep it.
const TEXT_BOX = '.q-type';

// The panel takes the keyboard only while one of its own text boxes (a card's, or a module's elsewhere, as a new
// conversation's words: core.textBoxes) is typed in, or a card that answers to keys has been pressed (heldCard), and
// gives it back on leaving it, so a click on the panel never keeps keystrokes from the app being typed in. Leaving
// waits a moment: a rebuild of the list swaps the box for a fresh one, and focuses that.
const textBoxes = () => [TEXT_BOX, ...core.textBoxes].join(', ');
const keepsKeyboard = () => !!document.activeElement?.closest?.(textBoxes()) || !!heldCard() || viewHasKeys();
function wantKeyboard(on) {
  clearTimeout(state.keyboardTimer);
  if (on && !state.keyboardWanted) { state.keyboardWanted = true; native({ type: 'keyboard', on: true }); }
  if (!on) state.keyboardTimer = setTimeout(() => {
    if (keepsKeyboard() || !state.keyboardWanted) return;
    state.keyboardWanted = false;
    native({ type: 'keyboard', on: false });
  }, 150);
}
// Whether the panel has the keyboard now: it gives it back about 150ms after you leave what took it (wantKeyboard).
const hasKeyboard = () => !!state.keyboardWanted;

// The places where a row's cards take keys once pressed: the list, and any a module draws rows in beside it
// (core.keyPlaces), each as { el, open(card, pressing) }: whether a card there can have the keys now, and with
// `pressing`, whether a press on it counts. A place given as its element alone, as the list is, is always open.
const keyPlaces = () => [list, ...core.keyPlaces].map((p) => (p.el ? p : { el: p, open: () => true }));

// The card pressed last that answers to keys (core.keyCards: a request, a question or a card like it on a row), while
// it waits for you in the place it was pressed in: found again there by its id, as the list is rebuilt whenever what
// it shows changes, so a copy of the same request drawn in another place is never it, nor the copy of the row held at
// the list's edge. Once it's answered or gone, or its place is no longer one or says it can't have them, it's let go of.
function heldCard() {
  const held = state.keyCard;
  if (!held) return null;
  const place = keyPlaces().find((p) => p.el === held.place);
  const card = place && [...place.el.querySelectorAll(held.kind.card)]
    .find((c) => c.closest('.row[data-id]') && held.kind.id(c) === held.id);
  if (card && held.kind.open(card) && place.open(card, false)) return card;
  state.keyCard = null;
  return null;
}

// The card that answers to keys a press on `target` gives them to, as { kind, id, place }, or null: one pressed
// anywhere but where the press answers it, once it has been seen (justShown: a card that has only just come may have
// taken the place of the one meant), on a row in one of the keyPlaces where a press counts now.
function keyCardPressed(target) {
  for (const kind of core.keyCards) {
    const card = target.closest?.(kind.card);
    const place = card?.closest('.row[data-id]') && keyPlaces().find((p) => p.el.contains(card));
    if (!place) continue;
    const id = kind.id(card);
    return kind.open(card) && place.open(card, true) && kind.takes(card, target) && !justShown(id)
      ? { kind, id, place: place.el } : null;
  }
  return null;
}

// The view beside the list (the reader, One Task: parts/pane) has the keyboard once pressed in, so Esc can close it:
// never as it opens, as a row's tag leaves the keys with the app in front, and not by its ✕, which closes it. Only the
// view pressed has them, what it showed then, so one opened since, or turned to another session or mode by a tag or
// the pawn menu, has none until it's pressed in too.
function viewPressed(target) {
  const r = state.reading;
  return r && !r.closing && reader.contains(target) && !target.closest?.('.r-close')
    ? { reading: r, mode: r.mode, sessionId: r.sessionId } : null;
}
function viewHasKeys() {
  const v = state.viewKeys, r = state.reading;
  return !!v && v.reading === r && v.mode === r.mode && v.sessionId === r.sessionId && !r.closing;
}

// What a press on the panel makes of the keyboard: a box asks for it before the press focuses the box (a window
// without the keyboard gets no focus events, so they can't be what asks), even if the page thinks it has it: Claude
// Desktop, brought forward to send a new conversation, takes it without the page knowing. So do a card that answers
// to keys (keyCardPressed) and the view beside the list (viewPressed). A press anywhere else here gives it back.
document.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  const box = !!e.target.closest?.(textBoxes());
  state.keyCard = box ? null : keyCardPressed(e.target);
  state.viewKeys = viewPressed(e.target);
  const wants = box || !!state.keyCard || !!state.viewKeys;
  if (wants) state.keyboardWanted = false;
  wantKeyboard(wants);
}, true);

// Keys on the card that has the keyboard, but for ⌘, ⌃ and ⌥ ones (copying what's selected on it): what its module
// says (core.keyCards' key), else Return presses its main button, as in its box, and Esc lets go of the keyboard,
// answering nothing.
function keyOnHeldCard(e) {
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
}
document.addEventListener('keydown', keyOnHeldCard);

// Esc closes the view beside the list, as its ✕ does, whenever the panel has the keyboard and nothing takes Esc first:
// a card that has the keys lets go of them (keyOnHeldCard), a box of a module's own card or the new conversation's card
// does what its module says, and a box with words typed in it is left, keeping them, with the view still holding the
// keys, so the next Esc closes it. The keyboard goes back to the app in front as the view closes. Never while
// composing, where Esc is the input method's.
function escClosesView(e) {
  if (e.key !== 'Escape' || e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || e.isComposing
      || e.keyCode === 229 || !state.reading || state.reading.closing) return;
  const box = e.target.closest?.(textBoxes());
  e.preventDefault();
  box?.blur();
  if (box?.value?.trim()) return;
  state.viewKeys = null;
  closeReader();
}
document.addEventListener('keydown', escClosesView);

// While the view has the keys from a press alone (no box typed in, no card holding them), only Esc acts there: Tab,
// Return and Space are taken before anything hears them, so typing meant for the app you were in ("git st", Tab,
// Return) never moves the focus, presses a button, or sends a comment or an answer.
function viewKeyOnly(e) {
  if (!viewHasKeys() || heldCard() || e.target.closest?.(textBoxes())) return;
  if (e.key !== 'Tab' && e.key !== 'Enter' && e.key !== ' ') return;
  e.preventDefault();
  e.stopPropagation();
}
document.addEventListener('keydown', viewKeyOnly, true);

// The card that has the keyboard shows it, by its edge, and no other copy of it does; once it's answered or gone, the
// keyboard goes back. After the list is drawn, and by a place beside it (core.keyPlaces) drawn after that, so its copy
// shows it at once.
function showHeldCard() {
  const card = heldCard();
  for (const place of keyPlaces()) {
    for (const c of place.el.querySelectorAll('.has-keys')) if (c !== card) c.classList.remove('has-keys');
  }
  card?.classList.add('has-keys');
  if (state.keyboardWanted && !keepsKeyboard()) wantKeyboard(false);
}
core.afterDraw.push(showHeldCard);

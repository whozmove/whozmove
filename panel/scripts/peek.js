// The folded cat's list while it's pointed at. Resting on the cat a moment, the panel opens as a press on the cat
// opens it, where a press opens it, the glass spreading out from behind the cat; the chats beside the cat go in first
// (chats.js). It's the open panel but for its header: a head as tall stands in for it, the cat in it as it is, where
// the name's o is, and at its other end how many are waiting on you. It all works as the open panel does. Moving off
// the panel, it folds back round the cat as the panel folds, and the chats come back out. Pressing the cat, or the
// head, only finishes opening it, as the panel opening does once its glass has spread: the cat shrinks into the
// name's o, the name coming in round it, and the header's buttons come in where the head's words were, once they've
// gone.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How long the pointer rests on the cat before its list comes out, and how long it's off the panel before it goes; and
// how long the panel takes to fold back round the cat, after which the header is back in the head's place, out of
// sight.
const PEEK_REST = 250, PEEK_LEAVE = 250, PEEK_FOLD = 500;

// What the head says, with `n` sessions waiting on you (the menu bar's count).
function peekTitle(n) {
  return n ? `${n} waiting on you` : 'Nothing waiting on you';
}

const peekHead = document.getElementById('peekHead');

// Whether the list may come out now: folded, with nothing else moving the cat or its glass, the reader not on its way,
// and the pointer having left the cat once since it folded.
function peekMay() {
  const body = document.body.classList;
  return body.contains('collapsed') && !body.contains('departing') && !state.cat.arriving && !state.cat.fromSide
    && !state.cat.waitForLeave && !state.chats.moving && !state.reading;
}

// Where the pointer is on the page (hoverAt and hoverEnd, in panel.js; null once it's off the panel): resting on the
// folded cat, its list comes out, but not while the cat is pressed (a press opens the panel or drags it); off the
// panel, it goes, but not while one of its boxes is typed in, nor while the pointer is `kept` with the panel off its
// page (on Spotify's token or the usage card, or not moved since the panel's edge went past it). The cat looks up at
// the pointer on it, and while its list is out.
function peekPointer(x, y, kept = false) {
  const pk = state.peek, onCat = x !== null && document.body.classList.contains('collapsed') && pointOnCat(x, y);
  catHover(onCat || pk.open);
  if (x === null) pk.kept = kept;
  if (!onCat || pk.pressed) {
    if (pk.rest) clearTimeout(pk.rest);
    pk.rest = 0;
  } else if (!pk.open && !pk.rest && peekMay()) {
    pk.rest = setTimeout(() => { pk.rest = 0; peekOpen(); }, PEEK_REST);
  }
  if (!pk.open) return;
  const typed = !!document.activeElement?.closest?.(textBoxes());
  if (x !== null || typed || kept) {
    clearTimeout(pk.leave);
    pk.leave = 0;
  } else if (!pk.leave) pk.leave = setTimeout(() => { pk.leave = 0; peekGoes(); }, PEEK_LEAVE);
}

// The head's words, as the list is drawn.
function peekNamed() {
  const waiting = Object.values(state.kinds).filter(waitsOnYou).length;
  peekHead.firstElementChild.textContent = peekTitle(waiting);
}

// The panel opens round the cat. As it does from a press, the list comes in as the glass spreads out from behind the
// cat (peek.css), and the chats beside the cat go into their rows (chatsLand, in chats.js), but the cat stays as it
// is, and how the panel was left isn't kept.
function peekOpen() {
  const pk = state.peek, body = document.body.classList;
  if (pk.open || !peekMay()) return;
  pk.open = true;
  peekNamed();
  clearTimeout(pk.folding);
  body.add('peeking');
  if (!calm.matches) body.add('peek-wait');
  foldPanel(false, true);
  if (calm.matches) return;
  catOnGlass(() => {
    body.remove('peek-wait');
    body.add('peek-in');
    pk.coming = setTimeout(() => body.remove('peek-in'), 560);
  }, 400);
}

// Moving off it, the panel folds back round the cat as it folds from a press, the cat being the folded cat already,
// and the chats still out are pulled back out from their rows beside it meanwhile (chatsLeave, in chats.js), the app
// keeping the room they go to as it folds. Says whether it was out.
function peekGoes() {
  const pk = state.peek, body = document.body.classList;
  peekTimersOff();
  if (!pk.open) return false;
  pk.open = false;
  body.remove('peek-wait', 'peek-in');
  const room = chatsLeave();
  foldPanel(true, true, room);
  drawChats(chatsPlaced, state.last.now);
  pk.folding = setTimeout(() => body.remove('peeking'), PEEK_FOLD);
  return true;
}

// The cat or the head pressed with the list out: the panel is open already, so it only finishes opening, the cat
// shrinking into the name's o at once (catOpening), and it's kept open.
function peekStays() {
  const pk = state.peek, body = document.body.classList;
  peekTimersOff();
  pk.open = false;
  body.remove('peek-wait', 'peek-in');
  store.set('collapsed', false);
  native({ type: 'keepOpen' });  // and the app, for next launch
  catOpening(() => body.remove('peeking'), true);
  drawChats(chatsPlaced, state.last.now);
}

// The header back in the head's place at once, for an opening from a press while the list was going back in.
function peekHeaderBack() {
  clearTimeout(state.peek.folding);
  document.body.classList.remove('peeking');
}

function peekTimersOff() {
  const pk = state.peek;
  for (const timer of ['rest', 'leave', 'coming']) {
    clearTimeout(pk[timer]);
    pk[timer] = 0;
  }
}

// The folded cat pressed, and let go (the app's drag strip over it, app/core/PanelWindow.m): its list doesn't come out
// meanwhile, and doesn't once it's let go until the pointer moves on the cat again.
window.catPressed = (down) => {
  const pk = state.peek;
  pk.pressed = down;
  clearTimeout(pk.rest);
  pk.rest = 0;
};

// A box in the list let go of the keyboard (you clicked into another app, or the card it was in went) with the pointer
// already off the panel: it folds back now, as it would have as the pointer left.
document.addEventListener('focusout', () => setTimeout(() => {
  if (state.peek.open && !state.pointer) peekPointer(null, null, state.peek.kept);
}, 0));

// A press on the head (the drag strip over its left part takes one there, and the app passes it on: toggleCollapsed).
peekHead.addEventListener('mousedown', (e) => {
  if (e.button !== 0 || !state.peek.open) return;
  e.preventDefault();
  peekStays();
});
core.afterDraw.push(() => { if (state.peek.open) peekNamed(); });

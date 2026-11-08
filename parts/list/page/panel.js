// The panel: render, and what it keeps for it. What the app calls on the page is the bridge's (parts/bridge,
// app-calls.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

if (store.get('collapsed', false)) document.body.classList.add('collapsed');
// The app makes the window the folded cat's, or the open panel's, as the page was left (fold:instant: in
// PanelWindow+Fold.m).
native({ type: 'fold', on: document.body.classList.contains('collapsed'), instant: true });

// ---- Keeping rows in place ----

// The session you're on: last opened from here, or switched to in Claude Desktop or in a terminal's tabs, where a
// new conversation starts unless you choose another place (starts.js). Its row goes where it belongs, as every row does
// but one you've pressed.
function goTo(sid) { state.current = sid; }
// The app marks the session you're on (`focused`): the conversation Claude Desktop shows, or the session in the
// terminal tab you're looking at (Ghostty's or iTerm2's), whichever of those apps you were in last. When the mark
// moves, so does goTo's: as the page shows it, so a session just opened here counts at once (openedNow).
function followClaude() {
  const sid = state.last.sessions.map(openedNow).find((s) => s.focused)?.sessionId || null;
  if (sid && sid !== state.claudeShowed) goTo(sid);
  state.claudeShowed = sid;
}
// When you were last on each session while it was yours (stillOnIt in whose-move.js): you opened it here, the app saw
// you on it in Claude, Ghostty or iTerm2 (its seenAt, which it forgets when it restarts), or you wrote to it. What it
// replied before then is read (classify).
// Kept across launches: written down at once when it moves past something new (a reply, or your message), and otherwise
// at most once a minute while you stay on it, so a restart loses no more than that.
function noteOnIt(s, at, now) {
  const kept = state.seen[s.sessionId] || 0, next = stillOnIt(s, kept, at, now, state.readBefore);
  if (next === kept) return;
  state.seen[s.sessionId] = next;
  if (kept < Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0) || now - state.seenKeptAt >= 60 * 1000) {
    state.seenKeptAt = now;
    store.set('seen', state.seen);
  }
}
function keepSeen(sessions, now) {
  for (const s of sessions) noteOnIt(s, onItAt(s), now);
  keepToRead(sessions);
}
// Each session's reply to you that you haven't read yet, by when it came (stillToRead in whose-move.js), so one that
// goes elsewhere since doesn't read it for you. Kept across launches, written down as it changes.
function keepToRead(sessions) {
  const read = view();
  let changed = false;
  for (const s of sessions) {
    const kept = state.toRead[s.sessionId] || 0, next = stillToRead(s, kept, read);
    if (next === kept) continue;
    if (next) state.toRead[s.sessionId] = next;
    else delete state.toRead[s.sessionId];
    changed = true;
  }
  if (changed) store.set('toRead', state.toRead);
}
// A row you press (to open it, answer it, or run a step or Deploy from it, or in the reader beside it) keeps its place,
// so it doesn't move away while you watch what your press did: until you've moved on from the panel, your pointer off
// it (and moved, when the panel's edge went past it) and none of the panel's boxes with the keyboard.
function keepInPlace(sid) { if (sid) state.pressedRows.add(sid); }
// Which rows keep the place they were last shown in (placeRows in whose-move.js): the ones you've pressed.
function heldNow() {
  if (!state.pointer && !state.pointerStill && !state.keyboardWanted) state.pressedRows.clear();
  return (sid) => state.pressedRows.has(sid);
}
// How the panel is set up right now, as classify in whose-move.js needs it.
function view() { return { seen: state.seen, readBefore: state.readBefore, toRead: state.toRead }; }

// ---- Rendering ----

// A session clicked here shows as the one you're on at once, rather than when the app says so: a second or so later for
// Claude Desktop, whose log says which conversation it shows; once the rows have been read again for a terminal's tab;
// later still while the list is mid-move, as the rows wait for it. So the row you're on takes its tint as you press
// it. It stays so until the data agrees, or for 4s (a terminal the app can't follow never does). Meanwhile it's the
// only one marked: until its app is in front, the session you were on in the other still is.
function openedNow(s) {
  if (!state.opening) return s;
  const it = s.sessionId === state.opening.sessionId;
  return it === !!s.focused ? s : { ...s, focused: it };
}

// The list, rebuilt from the newest update, with the folded cat's counts (cat.js) and the count beside the pawn in the
// menu bar, the sessions that need your input.
function render() {
  if (state.opening && (Date.now() - state.opening.at > 4000
      || state.last.sessions.some((s) => s.sessionId === state.opening.sessionId && s.focused))) {
    state.opening = null;
  }
  followClaude();
  // The box or the card that had the keyboard went away (its card folded, or it was answered).
  if (state.keyboardWanted && !keepsKeyboard()) wantKeyboard(false);
  const now = state.last.now, listed = state.last.sessions.map((s) => openedNow(steady(s, now)));
  // With them, the rows the modules add that the app hasn't listed yet: the conversations started here (starts.js).
  const sessions = listed.concat(...core.moreRows.map((more) => more(listed)));
  state.owners = checkoutOwners(listed);
  // What each session is now, and where it's shown: the rows you've pressed where you last saw them, the rest in place.
  keepSeen(listed, now);
  const read = view();
  state.kinds = Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, now, read)]));
  const placed = placeRows(sessions.map((s) => ({ s, kind: state.kinds[s.sessionId] })), state.placed, heldNow());
  for (const { s, latest, quiet } of placed) state.placed[s.sessionId] = { latest, quiet };
  for (const before of core.beforeDraw) before(listed);

  const kinds = Object.values(state.kinds);
  // The folded cat (cat.js): it looks at you while something waits on you, and watches while something works, its
  // agents in the background among them.
  drawCat({ needs: placed.filter((p) => waitsOnYou(p.kind)).length,
            working: placed.filter((p) => p.kind === 'busy' || p.kind === 'background').length });
  // And beside it, while folded, what needs you comes out as its row, by itself (chats.js).
  drawChats(placed, now);
  // Grouped by project, by a module's grouping while it has something to group by, or newest first; drawn as
  // listDrawing says.
  const list = document.getElementById('list');
  let html = '', drawing = null;
  if (state.shown) {
    const grouped = state.groupBy !== 'project' && core.groupings[state.groupBy]?.groups(placed);
    html = state.groupBy === 'project' ? projectsHTML(placed, now) : grouped ? groupsHTML(grouped, now)
      : rowsHTML(placed, now);
    if (!sessions.length) html = '<div class="empty">No Claude Code sessions running</div>';
    drawing = drawingOf(html);
  }
  const how = listDrawing({ shown: state.shown, stale: state.listStale,
                            same: drawing === state.drawing && !!state.drawnFirst
                              && list.firstElementChild === state.drawnFirst });
  if (how === 'none') state.listStale = true;
  else if (how === 'tick') {
    tickTimes(list, now);
    // A rebuild took off the marks that play a row's or a line's coming in (morph): kept, one would play again where
    // its row is shown again (a group opened), so each goes once it has played.
    for (const el of list.querySelectorAll('.swap, .arrive'))
      if (!el.getAnimations().length) el.classList.remove('swap', 'arrive');
  } else {
    // Drawn as it is now, as the first time, without moving. What comes into view as the panel does (a request that
    // came meanwhile, brought into view) moves as it would have had it come with the panel there.
    morph(list, html, { still: how === 'fresh' });
    Object.assign(state, { drawing, drawnFirst: list.firstElementChild, listStale: false });
  }
  revealOpenConversation();
  nameRunningBuild();

  // How many need you: the pawn's count. Whozmove beside the panel at its edge is told by notifications, after this
  // drawing (core.afterDraw).
  native({ type: 'badge', value: kinds.filter(waitsOnYou).length });
  // Nothing of the panel seen, there's nothing under the pointer, and no height to keep to: the next drawing says it.
  if (how !== 'none') syncHover();  // the rows under the pointer may just have been replaced
  for (const after of core.afterDraw) after();
  if (how !== 'none') reportHeight();
  if (state.reading) drawReader();
}

// How the list is drawn this time: not at all while nothing of the panel can be seen (`shown`: hidden, or the screen
// asleep or locked); afresh, without moving, the first time after that (`stale`); only its clocks set when it would
// draw the same as last time (`same`); else rebuilt, with its motion (morph). Plain, for the tests.
function listDrawing({ shown, stale, same }) {
  if (!shown) return 'none';
  if (stale) return 'fresh';
  return same ? 'tick' : 'morph';
}

// What a list's HTML draws, but for what changes in it by itself (tickTimes): how long ago, how long a step has run,
// how long is left and how much of a time counted down, and where each endless animation has got to (phase), which
// restarted with every rebuild.
function drawingOf(html) {
  return html.replace(/animation-delay:-\d+ms/g, '').replace(/(data-(?:since|ago|left)="[^"]*"[^>]*>)[^<]*/g, '$1')
    .replace(/(data-until="[^"]*" data-span="[^"]*" style=")--left:[\d.]+/g, '$1');
}

// The header's line under "Whozmove", while Show Build in Header is on: the build running now, and how long ago it was
// built. The first time the page names a build it hasn't named before (the app has just restarted on it), the old name
// rolls out as the new one rolls in. The name it last showed is kept across launches.
function nameRunningBuild() {
  const el = document.getElementById('build'), run = state.running;
  el.hidden = !(state.switches.build && run);
  if (el.hidden) return;
  const text = headerBuild(run, Date.now()), id = `${run.commit || ''}@${run.builtAt || 0}`;
  const shown = store.get('buildShown', null);
  if (shown?.id !== id) {
    store.set('buildShown', { id, text });
    if (shown?.text && !calm.matches) {
      el.textContent = shown.text;
      const was = { el: el.cloneNode(true), height: el.offsetHeight };
      el.textContent = text;
      rollLine(null, el, was, false);
    }
  }
  if (!el.querySelector('.roll-copy') && el.textContent !== text) el.textContent = text;  // not mid-roll
}

// Whether the list scrolls to show the row of the session you're on, `id` now and `was` at the last render: only when it
// changes, so it never fights a scroll of the list by hand, and never under a press. While rows you've pressed keep
// their place (`pressed`, keepInPlace), the list stays still, so what you pressed stays under your pointer, whatever
// the session you're on does meanwhile (one opened here that its app is slow to say it shows goes back for a moment to
// the one it still says, openedNow); but for one you pressed elsewhere (Take me there, in the reader) with none of its
// row in view (`shown`).
function revealsOpen(id, was, pressed, shown) {
  if (!id || id === was) return false;
  return !pressed.size || (pressed.has(id) && !shown);
}

// When the session you're on changes (the conversation open in Claude, or the terminal tab you're looking at), the
// list scrolls just enough to show its row (showInList), as revealsOpen says.
function revealOpenConversation() {
  const list = document.getElementById('list'), row = focusedRow(list), id = row?.dataset.id || null;
  const lr = list.getBoundingClientRect(), r = row?.getBoundingClientRect();
  const shown = !!r && r.bottom > lr.top + list.clientTop + headerInset()
    && r.top < lr.top + list.clientTop + list.clientHeight;
  if (row && revealsOpen(id, state.lastOpenId, state.pressedRows, shown)) requestAnimationFrame(() => showInList(row));
  state.lastOpenId = id;
}

// The panel grows to fit its content, and for a while to fit what hangs below it (the modules', core.overhangs).
// What it asks for is its content as it would be with the list at its usual limit (panelAsks), so the list filling a
// taller panel (fillList) never holds the panel at that height; with it, how tall the lines under the header are.
function reportHeight() {
  requestAnimationFrame(() => {
    stickyPlace();  // the row you're on, held at the list's edge, goes with whatever has moved the list
    // The reader sizes the panel until it closes (fitReader), the list's column as it changes included; beside it, the
    // list fills the panel by itself (glass.css).
    if (state.reading) { fillList(0); fitReader(); return; }
    const asked = Math.ceil(askedHeight()), below = hangingBelow();
    native({ type: 'height', value: Math.max(asked, below), under: Math.ceil(linesUnder()) });
    refill(asked, below);
  });
}

// The list filling what the panel has now, its content asking `asked` and what hangs below reaching `below`.
function refill(asked = Math.ceil(askedHeight()), below = hangingBelow()) {
  fillList(listFill(panelRoom(), asked, below, document.body.classList.contains('collapsed')));
}

// How tall the page's content is with the list at its usual limit: as it is, less however far the list goes past that
// limit filling a taller panel (panelAsks).
function askedHeight() {
  const list = document.getElementById('list'), fill = state.listFill || 0;
  const limit = parseFloat(getComputedStyle(list).maxHeight) - fill;
  return panelAsks(document.getElementById('root').getBoundingClientRect().height, list.offsetHeight, limit);
}

// The panel's height the page asks for: the page's content `root` tall, with the list `list` tall in it, held to its
// usual `limit` (--most, less the header's room when a line takes it). Plain, for the tests.
function panelAsks(root, list, limit) {
  return root - list + Math.min(list, limit);
}

// How far past its usual limit the list goes to fill the panel: what's left of the panel's height (`room`, from the
// list's top to the panel's foot) once its content (`asked`) is in, and none while the panel is folded. While something
// hangs below the list (`below`, over it), null: the list stays as it is, so nothing moves under what hangs there.
// Plain, for the tests.
function listFill(room, asked, below, folded) {
  if (folded) return 0;
  return below > 0 ? null : Math.max(0, Math.floor(room - asked));
}

// How tall the panel is from the page's top (the list's column) to its foot: the page is laid out in the window, from
// the room above the list down to the window's bottom (parts/glass).
function panelRoom() {
  return window.innerHeight - document.getElementById('root').getBoundingClientRect().top;
}

// The list's reach past its usual limit (--list-fill, glass.css), set only when it changes, as setting it lays the page
// out (null: kept as it is).
function fillList(fill) {
  if (fill == null || fill === (state.listFill || 0)) return;
  state.listFill = fill;
  document.getElementById('root').style.setProperty('--list-fill', fill + 'px');
}
// The window made taller or shorter by the app (for whatever reason): the list fills what it has, asking for nothing,
// so the panel's height stays the app's to decide.
addEventListener('resize', () => { if (!state.reading) requestAnimationFrame(() => refill()); });

// How tall the lines under the header are (the setup line, notifications' line and a new conversation's card), which
// the panel always has room for, with the header and a row, where the screen allows (RoomFor, parts/glass).
function linesUnder() {
  return ['install', 'notices', 'dock'].reduce((sum, id) => sum + (document.getElementById(id)?.offsetHeight || 0), 0);
}

// How far down what hangs below the list reaches (core.overhangs): the modules'.
function hangingBelow() {
  return Math.max(0, ...core.overhangs.map((reach) => reach()));
}

// What the page keeps for a session or a request goes once it has been gone from the list for a minute: a session
// that ended, a request answered or dismissed, and where its row was last shown. A moment's absence (a file caught
// mid-write) keeps it. What you've read stays for as long as it can still matter: the day a reply you've read waits.
// The modules name what they keep (core.forgotten).
const FORGET_MS = 60 * 1000;
function forgetGone(sessions) {
  const now = Date.now();
  for (const s of sessions) {
    state.listedAt[s.sessionId] = now;
    if (s.ask) state.listedAt[s.ask.id] = now;
  }
  const gone = (id) => now - (state.listedAt[id] ?? state.loadedAt) > FORGET_MS;
  for (const key of ['answering', 'answeredAt', 'stepNotes', 'placed', 'briefEnds', ...core.forgotten.keys])
    for (const id of Object.keys(state[key])) if (gone(id)) delete state[key][id];
  // A card, step or button first shown for a session ('compact:<id>', 'steps:<id>', …) goes with it, as does a
  // request's card, kept by the request's id.
  for (const key of Object.keys(state.shownAt)) if (gone(shownFor(key))) delete state.shownAt[key];
  const read = Object.keys(state.seen).filter((id) => gone(id) && now - state.seen[id] > IDLE_AFTER_MS);
  for (const id of read) delete state.seen[id];
  if (read.length) store.set('seen', state.seen);
  const unread = Object.keys(state.toRead).filter(gone);
  for (const id of unread) delete state.toRead[id];
  if (unread.length) store.set('toRead', state.toRead);
  for (const id of Object.keys(state.listedAt)) if (gone(id)) delete state.listedAt[id];
}

// Rebuilds the list now, or once what's moving has settled: a rebuild in the middle of an animation would cut it short,
// and one while an input method is mid-word would lose the word (the end of a slide, and of the word, rebuild). The
// wait is checked again when it's over, as something may have started moving meanwhile (a gauge opening).
function renderWhenSettled() {
  if (state.sliding || state.composing) return;
  clearTimeout(state.settleTimer);
  const wait = state.settleUntil - performance.now();
  if (wait > 0) state.settleTimer = setTimeout(renderWhenSettled, wait);
  else render();
}

// The panel folds into the cat, or opens out of it, the app moving the glass (fold:instant: in
// PanelWindow+Fold.m). `peek` for the folded cat's list coming out while it's pointed at, or going back in
// (peek.js): the cat stays as it is, how the panel was left isn't kept for next time, and asked the other way before
// it's done, the app turns it back from where it is. `room`, folding, is where the chats still out go back out to
// beside the cat (chatsLeave, in landing.js), which the app keeps as it folds.
function foldPanel(collapsed, peek = false, room = null) {
  const flip = () => document.body.classList.toggle('collapsed', collapsed);
  // The cat grows from the name's o, or shrinks onto it, where the header has it all there (header.js); folding round
  // Whozmove beside the panel, the header fades where it has gone. Opened before that fold has landed, the folded cat
  // goes back to the o first, and the panel opens round it there.
  if (!collapsed && state.cat.fromSide) catFromSideEnds();
  if (!collapsed || !state.cat.fromSide) headerAllThere();
  if (peek) flip();
  else if (collapsed) catFolding(flip);
  else catOpening(flip);
  // Opening, the chats out beside the cat go into their rows (landing.js).
  if (!collapsed) chatsLand();
  if (!peek) store.set('collapsed', collapsed);
  native({ type: 'fold', on: collapsed, ...(room ? { room } : {}), ...(peek ? { peek } : {}) });
  if (!collapsed && !peek) catHover(false);
  catLook();
  for (const folded of core.collapses) folded(collapsed);
  reportHeight();
}

// Whether the panel is folded into the cat for now: folded, or with the folded cat's list out while it's pointed at
// (peek.js), which a press that needs the panel open for good opens first (openFromCat).
function stillFolded() {
  return document.body.classList.contains('collapsed') || state.peek.open;
}

// Opens the panel for good, from the folded cat or its list out, for what's pressed there that needs it open (the
// reader, "Switch model?"), and then `then`.
function openFromCat(then) {
  if (stillFolded()) toggleCollapsed();
  then();
}

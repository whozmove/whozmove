// The panel: render, and the functions the app calls on the core. Each module defines its own (as window.setDeploys
// in deploy-row.js), beside what it draws.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

if (store.get('collapsed', false)) document.body.classList.add('collapsed');
// The app makes the window the folded cat's, or the open panel's, as the page was left (fold:instant: in
// app/core/PanelWindow.m).
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
// replied before then is read (classify), and a reply you've read stays in Your turn until you've moved on (sectionOf).
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
function view() { return { seen: state.seen, readBefore: state.readBefore }; }

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
  // The box that had the keyboard went away (its card folded).
  if (state.keyboardWanted && !document.activeElement?.closest?.(textBoxes())) wantKeyboard(false);
  const now = state.last.now, listed = state.last.sessions.map((s) => openedNow(steady(s, now)));
  // With them, the rows the modules add that the app hasn't listed yet: the conversations started here (starts.js).
  const sessions = listed.concat(...core.moreRows.map((more) => more(listed)));
  state.owners = checkoutOwners(listed);
  // What each session is now, and where it's shown: the rows you've pressed where you last saw them, the rest in place.
  keepSeen(listed, now);
  const read = view();
  state.kinds = Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, now, read)]));
  const placed = placeRows(sessions.map((s) => ({ s, kind: state.kinds[s.sessionId] })), state.placed, heldNow(), now,
                           read);
  for (const { s, section, key, tie, latest } of placed) state.placed[s.sessionId] = { section, key, tie, latest };
  for (const before of core.beforeDraw) before(listed);

  const kinds = Object.values(state.kinds);
  // The folded cat (cat.js): it looks at you while something is your turn, watches while something works, and has a
  // label for each session in the list's order: what's your turn by name, the rest as their dots.
  const inSection = (section) => placed.filter((p) => p.section === section).length;
  const counts = { needs: inSection('turn'), working: inSection('busy') };
  counts.idle = placed.length - counts.needs - counts.working;
  drawCat(counts, placed.map((p) => p.s), placed.map(({ kind, section }) => ({ kind, section })));
  let html = state.groupBy === 'project' ? projectsHTML(placed, now) : sectionsHTML(placed, now);
  if (!sessions.length) html = '<div class="empty">No Claude Code sessions running</div>';
  morph(document.getElementById('list'), html);
  revealOpenConversation();
  nameRunningBuild();

  native({ type: 'badge', value: kinds.filter((k) => k === 'needs' || k === 'turn').length });
  syncHover();  // the rows under the pointer were just replaced
  for (const after of core.afterDraw) after();
  reportHeight();
  if (state.reading) drawReader();
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

// When the session you're on changes (the conversation open in Claude, or the terminal tab you're looking at), the
// list scrolls just enough to show its row (showInList). Only on a change, so it never fights a scroll of the list by
// hand.
function revealOpenConversation() {
  const row = focusedRow(document.getElementById('list')), id = row?.dataset.id || null;
  if (row && id !== state.lastOpenId) requestAnimationFrame(() => showInList(row));
  state.lastOpenId = id;
}

// The panel grows to fit its content, and for a while to fit a card hanging below it (the modules' too).
function reportHeight() {
  requestAnimationFrame(() => {
    stickyPlace();  // the row you're on, held at the list's edge, goes with whatever has moved the list
    // The reader sizes the panel until it closes (fitReader), the list's column as it changes included.
    if (state.reading) { fitReader(); return; }
    const content = Math.ceil(document.getElementById('root').getBoundingClientRect().height);
    native({ type: 'height', value: Math.max(content, hangingBelow()) });
  });
}

// How far down what hangs below the list reaches: the card pointed at, or one held a moment after, and the modules'.
function hangingBelow() {
  const held = state.cardHeld && performance.now() < state.cardHeld.until ? state.cardHeld.bottom : 0;
  return Math.max(state.cardKey ? state.cardBottom : 0, held, ...core.overhangs.map((reach) => reach()));
}

// What the page keeps for a session or a request goes once it has been gone from the list for a minute: a session
// that ended, a request answered or dismissed, and where its row was last shown. A moment's absence (a file caught
// mid-write) keeps it. What you've read stays for as long as it can still matter: the hour a reply you've read waits.
// The modules name what they keep (core.forgotten).
const FORGET_MS = 60 * 1000;
function forgetGone(sessions) {
  const now = Date.now();
  for (const s of sessions) {
    state.listedAt[s.sessionId] = now;
    if (s.ask) state.listedAt[s.ask.id] = now;
  }
  const gone = (id) => now - (state.listedAt[id] ?? state.loadedAt) > FORGET_MS;
  for (const key of ['answering', 'answeredAt', 'stepNotes', 'placed', ...core.forgotten.keys])
    for (const id of Object.keys(state[key])) if (gone(id)) delete state[key][id];
  // A card, step or button first shown for a session ('compact:<id>', 'steps:<id>', …) goes with it, as does a
  // request's card, kept by the request's id.
  for (const key of Object.keys(state.shownAt)) if (gone(shownFor(key))) delete state.shownAt[key];
  const read = Object.keys(state.seen).filter((id) => gone(id) && now - state.seen[id] > IDLE_AFTER_MS);
  for (const id of read) delete state.seen[id];
  if (read.length) store.set('seen', state.seen);
  for (const id of Object.keys(state.listedAt)) if (gone(id)) delete state.listedAt[id];
}

// ---- What the app calls ----

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

// The newest rows, about once a second; while something moves, the newest data waits (renderWhenSettled), but for the
// session you're on changing in its app (another tab in a terminal, another conversation in Claude), which shows at once,
// as a press here does, cutting short what's moving. The strips under the list aren't in it, so they keep time on their
// own, each module's through core.updates (Spotify's song line).
window.update = (sessions, now) => {
  state.last = { sessions, now };
  if (!state.readBefore) store.set('readBefore', (state.readBefore = now - IDLE_AFTER_MS));
  forgetGone(sessions);
  for (const updating of core.updating) updating(sessions);
  const on = sessions.map(openedNow).find((s) => s.focused)?.sessionId || null;
  if (on !== state.claudeShowed && !state.sliding && !state.composing) {
    clearTimeout(state.settleTimer);
    render();
  } else renderWhenSettled();
  for (const updated of core.updates) updated(now);
};

// How tall the panel can grow where it is: down to where the screen ends below it (app/core/PanelWindow.m). Within
// that, the header and the list keep to 640pt (base.css), with what opens under them on top; where the screen ends
// first, the list gives way and scrolls.
window.setRoom = (h) => {
  state.panelMax = h;
  document.getElementById('root').style.maxHeight = h + 'px';
  reportHeight();
};

// The grouping chosen from the menu bar item (status or project), set before the first update.
window.setGroupBy = (mode) => {
  state.groupBy = mode;
  render();
};

// A click on the header folds the panel into the cat (cat.js), and a click on the cat opens it again (the chevron folds
// it too). The app moves the glass (fold:instant: in app/core/PanelWindow.m).
window.toggleCollapsed = () => {
  const collapsed = !document.body.classList.contains('collapsed');
  // Not while the reader is open: the panel folds from the list alone (app/core/PanelWindow.m).
  if (collapsed && state.reading) return;
  const flip = () => document.body.classList.toggle('collapsed', collapsed);
  // The cat grows from the name's o, or shrinks onto it, where the header has it all there (header.js); folding round
  // Whozmove beside the panel, the header fades where it has gone. Opened before that fold has landed, the folded cat
  // goes back to the o first, and the panel opens round it there.
  if (!collapsed && state.cat.fromSide) catFromSideEnds();
  if (!collapsed || !state.cat.fromSide) headerAllThere();
  if (collapsed) catFolding(flip); else catOpening(flip);
  store.set('collapsed', collapsed);
  native({ type: 'fold', on: collapsed });
  if (!collapsed) catHover(false);
  catLook();
  for (const folded of core.collapses) folded(collapsed);
  reportHeight();
};

// Where the pointer is over the panel, as the app polls it (see hover.js); folded, whether it's on the cat or a tag.
// Once it has left, the rows you pressed go to their places (heldNow), so the list is drawn again for them: here, as
// what watches the pointer runs as the list is drawn (syncHover), and drawing it from there would never end. Off the
// panel `still`, the panel's edge having moved past it (a card folding away, a menu of its own closing where you
// picked from it), it's taken to be still with the panel until the app says it has moved.
window.hoverAt = (x, y) => {
  state.pointerStill = false;
  pointerAt(x, y);
  catHover(document.body.classList.contains('collapsed') && catPointedAt(x, y));
};
window.hoverEnd = (still) => {
  pointerGone();
  catHover(false);
  state.pointerStill = !!still;
  if (state.pressedRows.size && !still) renderWhenSettled();
};

// The panel no longer has the keyboard: another app took it (you clicked into it), or the panel gave it back. The box
// it was typed into lets go of it too, so the list being drawn again doesn't put the keyboard back there, and the rows
// you pressed go once your pointer is off the panel.
window.keyboardGone = () => {
  if (document.activeElement?.closest?.(textBoxes())) document.activeElement.blur();
  state.keyboardWanted = false;
  if (state.pressedRows.size) renderWhenSettled();
};

// The panel turning over to the apps on its back, or back on its list side (app/core/PanelWindow.m): meanwhile the
// pointer isn't on the list, and no box here has the keyboard.
window.turned = (on) => {
  state.turned = !!on;
  if (!on) return;
  pointerGone();
  if (document.activeElement?.closest?.(textBoxes())) document.activeElement.blur();
};

// The build of Whozmove running now, as build.sh recorded it (app/core/Builds.m), or null: the header's name for it.
window.setRunningBuild = (running) => {
  state.running = running;
  render();
};

// The panel's switches: Show Next Steps (each row's next steps, and Deploy's button), Show Deploy (Deploy's round
// button), and Show Build in Header; and the panel's look from its Look menu, grey, black or glass, for the colours
// that match the panel's own (tokens.css).
window.setSwitches = (switches) => {
  state.switches = { nextSteps: !!switches.nextSteps, deploy: !!switches.deploy, build: !!switches.build };
  document.documentElement.dataset.look = switches.look || 'grey';
  render();
};

// How a step from a row's menus went (`quiet`: it worked), or why it couldn't go in, or why a deploy couldn't start or
// its command wasn't saved: the row's note for a few seconds, in its work line's place. What it settles for a module goes first
// (core.noted: a Deploy pressed there stops standing in for a run).
window.stepNote = (sid, text, quiet, way) => {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (s) for (const noted of core.noted) noted(s);
  state.stepNotes[sid] = { text, quiet: !!quiet, way: way || null, at: Date.now() };
  renderWhenSettled();
};

// Every script has loaded: the modules start (modules.js), now that the page is whole.
for (const start of core.starts) start();

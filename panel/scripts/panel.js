// The panel: render, and the functions the app calls on the core. Each module defines its own (as window.setDeploys
// in deploy-row.js), beside what it draws.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

if (store.get('collapsed', false)) document.body.classList.add('collapsed');

// ---- Keeping rows in place ----

// The session you're on: last opened from here, or switched to in Claude Desktop or in Ghostty's tabs, where a new
// conversation starts unless you choose another place (starts.js). Its row goes where it belongs, as every row does
// but one you've pressed.
function goTo(sid) { state.current = sid; }
// The app marks the session you're on (`focused`): the conversation Claude Desktop shows, or the session in the
// Ghostty tab you're looking at, whichever of the two apps you were in last. When the mark moves, so does goTo's: as
// the page shows it, so a conversation just opened in Claude counts at once (openedNow).
function followClaude() {
  const sid = state.last.sessions.map(openedNow).find((s) => s.focused)?.sessionId || null;
  if (sid && sid !== state.claudeShowed) goTo(sid);
  state.claudeShowed = sid;
}
// When you last read each session's reply (classify in whose-move.js): you opened it here, or the app saw you looking
// at it in Claude or Ghostty after it came (its seenAt, which it forgets when it restarts, so it's kept here once it
// has read a reply). Kept across launches.
function markRead(sid, at) {
  state.seen[sid] = at;
  store.set('seen', state.seen);
}
function keepSeen(sessions) {
  for (const s of sessions) {
    const reply = s.lastReplyAt || 0;
    if (s.seenAt >= reply && (state.seen[s.sessionId] || 0) < reply) markRead(s.sessionId, s.seenAt);
  }
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

// The header's line, as the list shows it: how many rows are in Your turn (in the requests' colour while a request
// waits there) and how many in Working; with neither, how many in Seen and how many idle.
function summaryHTML(placed) {
  const n = (section) => placed.filter((p) => p.section === section).length, parts = [];
  const asks = placed.some((p) => p.section === 'turn' && p.kind === 'needs');
  if (n('turn')) parts.push(`<b style="color:var(${asks ? '--needs' : '--turn'})">${n('turn')} your turn</b>`);
  if (n('busy')) parts.push(`<b style="color:var(--busy)">${n('busy')} working</b>`);
  if (!parts.length) {
    if (n('seen')) parts.push(`${n('seen')} seen`);
    if (n('idle') || !parts.length) parts.push(`${n('idle')} idle`);
  }
  return parts.join(' · ');
}

// ---- Rendering ----

// A conversation in an app that marks it as shown only once its own record says so (Claude Desktop's, a host with
// marksOpenAtOnce), clicked here, shows as the one open at once, rather than a second or so later when Claude's log
// says so (later still if the list is mid-move), until the data agrees, or for 4s. Meanwhile it's the only one marked:
// until Claude is in front, the session you were on in your terminal still is.
function openedNow(s) {
  if (!state.opening) return s;
  const it = s.sessionId === state.opening.sessionId;
  return it === !!s.focused ? s : { ...s, focused: it };
}

// The list, rebuilt from the newest update, with the header's summary and the count beside the pawn in the menu
// bar.
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
  keepSeen(listed);
  state.kinds = Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, now, view())]));
  const placed = placeRows(sessions.map((s) => ({ s, kind: state.kinds[s.sessionId] })), state.placed, heldNow(), now);
  for (const { s, section, key, tie, latest } of placed) state.placed[s.sessionId] = { section, key, tie, latest };
  for (const before of core.beforeDraw) before(listed);

  const kinds = Object.values(state.kinds);
  document.getElementById('summary').innerHTML = summaryHTML(placed);
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

// When the session you're on changes (the conversation open in Claude, or the Ghostty tab you're looking at), the
// list scrolls just enough to show its row. Only on a change, so it never fights a scroll of the list by hand.
function revealOpenConversation() {
  const list = document.getElementById('list');
  const row = [...list.querySelectorAll('.row.focused')].find((r) => !r.closest('.prows.closed'));
  const id = row?.dataset.id || null;
  if (row && id !== state.lastOpenId) {
    requestAnimationFrame(() => {
      const r = row.getBoundingClientRect(), view = list.getBoundingClientRect();
      if (r.top < view.top) list.scrollTop -= view.top - r.top + 4;
      else if (r.bottom > view.bottom) list.scrollTop += r.bottom - view.bottom + 4;
    });
  }
  state.lastOpenId = id;
}

// The panel grows to fit its content, and for a while to fit a card hanging below it (the modules' too: the card of
// the island's commits stage, say).
function reportHeight() {
  requestAnimationFrame(() => {
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
  // A card, island or button first shown for a session ('compact:<id>', 'island:<id>', …) goes with it, as does a
  // request's card, kept by the request's id.
  const shown = new RegExp(`^(${core.forgotten.prefixes.join('|')}):`);
  const ofKey = (key) => key.replace(shown, '').replace(/:.*$/, '');
  for (const key of Object.keys(state.shownAt)) if (gone(ofKey(key))) delete state.shownAt[key];
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

// The newest rows, about once a second; while something moves, the newest data waits (renderWhenSettled). The strips
// under the list aren't in it, so they keep time on their own, each module's through core.updates (the usage strip's
// time left and wait, Spotify's song line).
window.update = (sessions, now) => {
  state.last = { sessions, now };
  if (!state.readBefore) store.set('readBefore', (state.readBefore = now - IDLE_AFTER_MS));
  forgetGone(sessions);
  for (const updating of core.updating) updating(sessions);
  renderWhenSettled();
  for (const updated of core.updates) updated(now);
};

// How tall the panel can grow where it is: kMaxHeight in app/core/PanelWindow.m, or less where the screen ends below
// it. The list scrolls beyond that.
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

// A click on the header folds the panel to its header, or opens it again (the chevron does the same).
window.toggleCollapsed = () => {
  document.body.classList.toggle('collapsed');
  const collapsed = document.body.classList.contains('collapsed');
  store.set('collapsed', collapsed);
  for (const folded of core.collapses) folded(collapsed);
  reportHeight();
};

// Where the pointer is over the panel, as the app polls it (see hover.js). Once it has left, the rows you pressed go to
// their places (heldNow), so the list is drawn again for them: here, as what watches the pointer runs as the list is
// drawn (syncHover), and drawing it from there would never end. Off the panel `still`, the panel's edge having moved
// past it (a card folding away, a menu of its own closing where you picked from it), it's taken to be still with the
// panel until the app says it has moved.
window.hoverAt = (x, y) => {
  state.pointerStill = false;
  pointerAt(x, y);
};
window.hoverEnd = (still) => {
  pointerGone();
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

// The build of Whozmove running now, as build.sh recorded it (app/core/Builds.m), or null: the header's name for it.
window.setRunningBuild = (running) => {
  state.running = running;
  render();
};

// The pawn menu's switches: Show Next Steps (each row's island, and Deploy's button), Show Deploy (Deploy's round
// button), and Show Build in Header.
window.setSwitches = (switches) => {
  state.switches = { nextSteps: !!switches.nextSteps, deploy: !!switches.deploy, build: !!switches.build };
  render();
};

// How a step from a row's menus went (`quiet`: it worked), or why it couldn't go in, or why a deploy couldn't start or
// its command wasn't saved: under the details for a few seconds. What it settles for a module goes first
// (core.noted: a Deploy pressed there stops standing in for a run).
window.stepNote = (sid, text, quiet) => {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (s) for (const noted of core.noted) noted(s);
  state.stepNotes[sid] = { text, quiet: !!quiet, at: Date.now() };
  renderWhenSettled();
};

// Every script has loaded: the modules start (modules.js), now that the page is whole.
for (const start of core.starts) start();

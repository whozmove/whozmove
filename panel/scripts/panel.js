// The panel: render, and the functions the app calls on the core. Each module defines its own (as window.setDeploys
// in deploy-row.js), beside what it draws.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

if (store.get('collapsed', false)) document.body.classList.add('collapsed');

// ---- Rendering ----

// The session you're on (last opened from here, or switched to in Claude Desktop or in Ghostty's tabs) keeps its place
// under "Your turn" once its reply is read; the reply just dims. It goes to Idle when you move to another one, so the
// list doesn't rearrange itself around the session you're working in. Only a session that was under "Your turn" is
// held there: one opened from Idle stays in Idle.
function goTo(sid) { state.current = state.shownKind[sid] === 'turn' ? sid : null; }
// The app marks the session you're on (`focused`): the conversation Claude Desktop shows, or the session in the
// Ghostty tab you're looking at, whichever of the two apps you were in last. When the mark moves, so does goTo's.
function followClaude() {
  const shown = state.last.sessions.find((s) => s.focused)?.sessionId || null;
  if (shown && shown !== state.claudeShowed) goTo(shown);  // you moved to another session, in Claude or Ghostty
  state.claudeShowed = shown;
}
// How the panel is set up right now, as classify in whose-move.js needs it.
function view() { return { groupBy: state.groupBy, current: state.current, seen: state.seen }; }

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
  state.shownKind = Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, now, view())]));
  for (const before of core.beforeDraw) before(listed);
  const groups = { needs: [], busy: [], turn: [], idle: [] };
  for (const s of sessions) groups[classify(s, now, view())].push(s);
  for (const [kind, g] of Object.entries(groups)) g.sort((a, b) => sortKey(b, kind) - sortKey(a, kind));

  const parts = [];
  if (groups.needs.length) parts.push(`<b style="color:var(--needs)">${groups.needs.length} need you</b>`);
  if (groups.busy.length) parts.push(`<b style="color:var(--busy)">${groups.busy.length} working</b>`);
  if (groups.turn.length) parts.push(`<b style="color:var(--turn)">${groups.turn.length} your turn</b>`);
  if (!parts.length) parts.push(`${sessions.length} idle`);
  document.getElementById('summary').innerHTML = parts.join(' · ');

  const section = (key, label, kind) => {
    const g = groups[key];
    if (!g.length) return '';
    return `<div class="group" data-key="g:${key}">${label}<span class="n">${g.length}</span></div>`
      + g.map((s) => rowHTML(s, kind, now)).join('');
  };
  let html;
  if (state.groupBy === 'project') {
    html = projectsHTML(sessions, now);
  } else {
    html = section('needs', 'Needs you', 'needs') + section('busy', 'Working', 'busy')
      + section('turn', 'Your turn', 'turn');
    if (groups.idle.length) {
      html += `<div class="group toggle${state.showIdle ? '' : ' collapsed'}" data-key="g:idle">Idle`
        + `<span class="n">${groups.idle.length}</span><span class="pchev">${CHEVRON_ICON}</span></div>`;
      html += groupBody(groups.idle.map((s) => ({ s, html: rowHTML(s, 'idle', now) })), !state.showIdle);
    }
  }
  if (!sessions.length) html = '<div class="empty">No Claude Code sessions running</div>';
  morph(document.getElementById('list'), html);
  revealOpenConversation();
  nameRunningBuild();

  native({ type: 'badge', value: groups.needs.length + groups.turn.length });
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
    const held = state.cardHeld && performance.now() < state.cardHeld.until ? state.cardHeld.bottom : 0;
    native({ type: 'height', value: Math.max(content, state.cardKey ? state.cardBottom : 0, held,
                                             ...core.overhangs.map((reach) => reach())) });
  });
}

// What the page keeps for a session or a request goes once it has been gone from the list for a minute: a session
// that ended, a request answered or dismissed. A moment's absence (a file caught mid-write) keeps it. What you've
// read stays for as long as it can still matter: while a reply counts as your turn. The modules name what they keep
// (core.forgotten).
const FORGET_MS = 60 * 1000;
function forgetGone(sessions) {
  const now = Date.now();
  for (const s of sessions) {
    state.listedAt[s.sessionId] = now;
    if (s.ask) state.listedAt[s.ask.id] = now;
  }
  const gone = (id) => now - (state.listedAt[id] ?? state.loadedAt) > FORGET_MS;
  for (const key of ['answering', 'answeredAt', 'stepNotes', ...core.forgotten.keys])
    for (const id of Object.keys(state[key])) if (gone(id)) delete state[key][id];
  // A card, island or button first shown for a session ('compact:<id>', 'island:<id>', …) goes with it, as does a
  // request's card, kept by the request's id.
  const shown = new RegExp(`^(${core.forgotten.prefixes.join('|')}):`);
  const ofKey = (key) => key.replace(shown, '').replace(/:.*$/, '');
  for (const key of Object.keys(state.shownAt)) if (gone(ofKey(key))) delete state.shownAt[key];
  const read = Object.keys(state.seen).filter((id) => gone(id) && now - state.seen[id] > YOUR_TURN_MS);
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

// The grouping chosen from the menu bar item (status, activity or project), set before the first update.
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

// Where the pointer is over the panel, as the app polls it (see hover.js).
window.hoverAt = pointerAt;
window.hoverEnd = pointerGone;

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

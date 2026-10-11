// The panel: render, and every function the app calls, in one place.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

if (store.get('collapsed', false)) document.body.classList.add('collapsed');

// ---- Rendering ----

// The session you're on (last opened from here, or switched to in Claude Desktop) keeps its place under "Your
// turn" once its reply is read; the reply just dims. It goes to Idle when you move to another one, so the list
// doesn't rearrange itself around the session you're working in. Only a session that was under "Your turn" is
// held there: one opened from Idle stays in Idle.
function goTo(sid) { state.current = state.shownKind[sid] === 'turn' ? sid : null; }
function followClaude() {
  const shown = state.last.sessions.find((s) => s.focused)?.sessionId || null;
  if (shown && shown !== state.claudeShowed) goTo(shown);  // another conversation was opened in Claude
  state.claudeShowed = shown;
}
// How the panel is set up right now, as classify in whose-move.js needs it.
function view() { return { groupBy: state.groupBy, current: state.current, seen: state.seen }; }

// A Claude Desktop conversation clicked here shows as the one open in Claude at once, rather than a second or so
// later when Claude's log says so (later still if the list is mid-move), until the data agrees, or for 4s.
function openedNow(s) {
  if (!state.opening || s.entrypoint !== 'claude-desktop') return s;
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
  if (state.keyboardWanted && !document.activeElement?.closest?.('.q-type')) wantKeyboard(false);
  const now = state.last.now, sessions = state.last.sessions.map((s) => openedNow(steady(s, now)));
  state.shownKind = Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, now, view())]));
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

  native({ type: 'badge', value: groups.needs.length + groups.turn.length });
  syncHover();  // the rows under the pointer were just replaced
  reportHeight();
}

// When the conversation open in Claude changes, the list scrolls just enough to show its row. Only on a change,
// so it never fights a scroll of the list by hand.
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

// The panel grows to fit its content, and for a while to fit a card hanging below it.
function reportHeight() {
  requestAnimationFrame(() => {
    const content = Math.ceil(document.getElementById('root').getBoundingClientRect().height);
    native({ type: 'height', value: Math.max(content, state.cardUrl ? state.cardBottom : 0,
                                             state.asking ? state.askBottom : 0) });
  });
}

// What the page keeps for a session or a request goes once it has been gone from the list for a minute: a session
// that ended, a request answered or dismissed. A moment's absence (a file caught mid-write) keeps it. What you've
// read stays for as long as it can still matter: while a reply counts as your turn.
const FORGET_MS = 60 * 1000;
function forgetGone(sessions) {
  const now = Date.now();
  for (const s of sessions) {
    state.listedAt[s.sessionId] = now;
    if (s.ask) state.listedAt[s.ask.id] = now;
  }
  const gone = (id) => now - (state.listedAt[id] ?? state.loadedAt) > FORGET_MS;
  for (const kept of [state.answering, state.answeredAt, state.quiz, state.compactOpen, state.compactNotes,
                      state.compactFocus])
    for (const id of Object.keys(kept)) if (gone(id)) delete kept[id];
  for (const key of Object.keys(state.shownAt)) if (gone(key.replace(/^compact:/, ''))) delete state.shownAt[key];
  const read = Object.keys(state.seen).filter((id) => gone(id) && now - state.seen[id] > YOUR_TURN_MS);
  for (const id of read) delete state.seen[id];
  if (read.length) store.set('seen', state.seen);
  for (const id of Object.keys(state.listedAt)) if (gone(id)) delete state.listedAt[id];
}

// ---- What the app calls ----

// The newest rows, about once a second. A rebuild in the middle of an animation would cut it short, so while one
// runs the newest data waits.
window.update = (sessions, now) => {
  state.last = { sessions, now };
  forgetGone(sessions);
  if (state.asking) placeAsk();
  if (state.sliding || state.composing) return;
  clearTimeout(state.settleTimer);
  const wait = state.settleUntil - performance.now();
  if (wait > 0) state.settleTimer = setTimeout(() => { if (!state.sliding) render(); }, wait);
  else render();
};

// How tall the panel can grow where it is: kMaxHeight in app/PanelWindow.m, or less where the screen ends below
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
  store.set('collapsed', document.body.classList.contains('collapsed'));
  reportHeight();
};

// Where the pointer is over the panel, as the app polls it (see hover.js).
window.hoverAt = pointerAt;
window.hoverEnd = pointerGone;

// Claude's "Switch model?", asked in the panel: the app calls this before sending /model, or when Claude asks
// anyway, and answers Claude's own box with what's picked here.
window.askSwitch = (question) => showSwitchQuestion(question);

// A /compact sent from the Compact card didn't go through: the card opens again, saying why.
window.compactNote = (sid, text) => { state.compactOpen[sid] = true; state.compactNotes[sid] = text; render(); };

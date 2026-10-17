// Starting a new conversation: the box at the bottom of the panel and the card it opens into, shaped like the row it
// becomes; the pending row a start shows as until Claude lists its session; and how the card hands over to that row
// and rises to its place in the list.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A start goes to the app (app/Starts.m) the moment it's pressed. Meanwhile the card turns into the row it starts, in
// place, so your words stay where you wrote them, and that row rises from the box to its place in the list. It waits
// there as a pending row until the session is listed, when the session's own row takes over under the same key, and
// morph carries it on as one row. A terminal start's session id is made here and given to Claude Code, so its row has
// that key from the start; Claude Desktop picks its own, which the app says once the conversation shows up
// (startUpdate).

// The card open in the box at the bottom, { id, folder, name, app, text, problem } or null, and the words of the last
// one closed without starting, which the next card opens with; the starts sent but not yet listed, by start id, { id,
// key, sessionId, folder, name, app, words, at, trust, quiet, drawn, flying, note, why }; what Claude may do in each
// folder, as the app last said, { trusted } or { gone } ({ trusted, here } once you trusted it on the card); and the
// terminal a start can open in (setStartOptions), null when there's none.
moduleState({ dock: null, startDraft: '', starts: {}, folders: {}, startOptions: { terminal: null } });

// A plus, on the box's bar and on a project's header.
const PLUS_ICON = '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M6 1.5v9M1.5 6h9" stroke="currentColor" '
  + 'stroke-width="1.6" stroke-linecap="round"/></svg>';

const dockBox = document.getElementById('dock'), flightLayer = document.getElementById('flight');
const newButton = document.querySelector('header .add-new');
const DOCK_BAR = `<div class="dock-bar" title="New conversation (⌃⌥N)">${PLUS_ICON}`
  + '<span class="db-text">Start a conversation</span><span class="db-key">⌃⌥N</span></div>';
let startsMade = 0;

// ---- Where a start goes ----

// The folders a card can start in: the projects of the sessions listed (a worktree's is its repo's), newest first.
// Claude Desktop's scratch conversations have no folder of their own to start in.
function startProjects(sessions) {
  const out = new Map();
  for (const s of [...sessions].sort((a, b) => lastActive(b) - lastActive(a))) {
    const p = projectOf(s);
    if (!p.scratch && !out.has(p.key)) out.set(p.key, { folder: p.key, name: p.name });
  }
  return [...out.values()];
}

// Where a new conversation starts unless you choose: the project of the session marked as the one you're on (the
// conversation Claude shows, or the session in the tab Ghostty shows), else of the one the list keeps in place for
// you (goTo), else the one most recently active; null with nothing listed.
function defaultStartFolder(sessions, current) {
  const on = sessions.find((s) => s.focused) || sessions.find((s) => s.sessionId === current);
  if (on && !projectOf(on).scratch) return { folder: projectOf(on).key, name: projectOf(on).name };
  return startProjects(sessions)[0] || null;
}

// The checkout a folder is, as a session listed there has it, for the branch on the details line.
function checkoutOf(folder, sessions) {
  return sessions.find((s) => s.git && s.git.root === folder)?.git || null;
}

// What the card says about its folder (`help`, a warning when `warn`), and what its button says (`go`, '' while it
// can't start, as while the app is still asked about the folder). With no words, it only opens a conversation there.
// Claude asks once before working in a folder it hasn't worked in; the card asks instead, and its button trusts the
// folder as it starts (`trust`). Why the last start from the card didn't go through takes the help line's place.
function startState(card, folders) {
  const folder = card.folder && folders[card.folder], verb = card.text.trim() ? 'start' : 'open';
  if (!card.folder) return { help: 'Choose the folder it starts in.', warn: false, go: '' };
  if (folder?.gone) return { help: `${card.name} isn't there any more: choose another folder.`, warn: true, go: '' };
  const untrusted = folder?.trusted === false;
  const go = !folder ? '' : untrusted ? `Trust and ${verb}` : verb[0].toUpperCase() + verb.slice(1);
  const help = card.problem || (untrusted ? `Claude hasn't worked in ${card.name} before. Trusting it lets Claude Code `
    + 'read, edit and run files there.' : '');
  return { help, warn: !!help, go, ...(untrusted ? { trust: true } : {}) };
}

// ---- The card ----

// Shaped like the row it becomes: its dot, its name, your words in a box laid over the "You" line, and the row's own
// details line, where the app (when there's a terminal to choose) and the folder can be changed with a press.
function startCardHTML(card, sessions) {
  const { help, warn, go } = startState(card, state.folders);
  const g = card.folder ? checkoutOf(card.folder, sessions) : null;
  const terminal = state.startOptions.terminal;
  const icon = card.app === 'terminal' ? TERMINAL_ICON : DESKTOP_ICON;
  const app = card.app === 'terminal' ? terminal : 'Claude', other = card.app === 'terminal' ? 'Claude' : terminal;
  const appPart = other ? `<span class="w-app" title="Starts in ${esc(app)}: press for ${esc(other)}">${icon}</span>` : icon;
  const folderTip = card.folder ? `${card.folder}\nPress to start it in another folder` : 'Choose a folder';
  const where = [`<span class="proj w-proj" title="${esc(folderTip)}">${esc(card.name)}<span class="caret">▾</span></span>`];
  if (g) where.push(`<span class="branch">${BRANCH_ICON}${esc(g.branch || 'detached @' + g.detached)}</span>`);
  if (g?.worktree) where.push('<span class="wt">worktree</span>');
  const button = `<button class="c-go"${go ? '' : ' disabled'} title="Return starts it · ⌘Return starts it and opens `
    + `another"><span class="go-label">${esc(go || 'Start')}</span><span class="alt"> + next</span></button>`;
  return `<div class="row compose" data-card="${esc(card.id)}">
      <span class="dot"></span>
      <div class="main">
        <div class="line1"><span class="name">New conversation</span><button class="c-x" title="Close (Esc)">×</button></div>
        <div class="you"><span class="who">You</span><textarea class="c-box" id="${esc(card.id)}-words" rows="1"
          spellcheck="false" aria-label="What should Claude do?" placeholder="What should Claude do?">${esc(card.text)}</textarea></div>
        ${help ? `<div class="c-help${warn ? ' warn' : ''}">${esc(help)}</div>` : ''}
        <div class="where c-where">${appPart}${where.join('<span class="sep">·</span>')}${button}</div>
      </div>
    </div>`;
}

// The starts not listed yet, as sessions for the list: working rows that say they're starting, or what they wait for,
// or why they didn't start. Each is keyed by the session id it will be listed under, once that's known. One still
// handing over in the box isn't drawn yet.
function pendingSessions(starts, sessions, terminal) {
  const listed = new Set(sessions.map((s) => s.sessionId));
  return Object.values(starts).filter((start) => start.drawn && !listed.has(start.key)).map((start) => {
    const g = checkoutOf(start.folder, sessions);
    return {
      sessionId: start.key, pending: true, name: 'New conversation', cwd: start.folder, prs: [], agent: {},
      entrypoint: start.app === 'desktop' ? 'claude-desktop' : 'cli', status: 'busy', statusUpdatedAt: start.at,
      lastPromptAt: start.at, ...(start.words ? { lastPrompt: start.words } : {}), ...(g ? { git: g } : {}),
      activity: start.why || start.note
        || `Starting in ${start.app === 'desktop' ? 'Claude' : terminal || 'the terminal'}`,
      ...(start.why || start.note ? { startProblem: true } : {}),
    };
  });
}

// Whether a row is a start's that hasn't reached it yet: its card is still handing over in the box, or its copy is still
// rising to it (riseToRow). It stays hidden until the copy lands, even once Claude lists the session.
function startLanding(id) {
  return Object.values(state.starts).some((start) => (!start.drawn || start.flying) && start.key === id);
}

// The starts Claude has listed are done with once their rows have landed: the session's own row is theirs now.
function forgetStarted(sessions) {
  const listed = new Set(sessions.map((s) => s.sessionId));
  for (const [id, start] of Object.entries(state.starts))
    if (start.drawn && !start.flying && listed.has(start.key)) delete state.starts[id];
}

// The card in the box, opened in place of its bar (the box eases to its new height), or brought up to date when it's
// open already, keeping your words and where you are in them. The panel takes the keyboard for its box (wantKeyboard).
function openCard(folder, app) {
  if (document.body.classList.contains('collapsed')) toggleCollapsed();
  const sessions = state.last.sessions, was = state.dock;
  wantKeyboard(true);
  if (was && !folder && !app) return focusStart();
  const where = folder ? startProjects(sessions).find((p) => p.folder === folder) || { folder, name: base(folder) }
                       : was ? { folder: was.folder, name: was.name } : defaultStartFolder(sessions, state.current);
  state.dock = {
    id: was?.id || `card${++startsMade}`, folder: where?.folder || null, name: where?.name || 'Choose a folder',
    app: app === 'terminal' && state.startOptions.terminal ? 'terminal' : app === 'desktop' ? 'desktop' : was?.app || 'desktop',
    text: was?.text || takeDraft(), problem: null,
  };
  newButton.classList.add('open');
  if (was && dockCard()) refreshStartCard('.w-proj, .w-app');
  else {
    const card = rowFrom(startCardHTML(state.dock, sessions)), bar = dockBox.querySelector(':scope > .dock-bar');
    resizeDock(() => {
      if (bar) Object.assign(bar.style, { position: 'absolute', left: '6px', right: '6px', top: bar.offsetTop + 'px' });
      dockBox.append(card);
      fitStartBox(card.querySelector('.c-box'));
    }, 420);
    if (bar) animateStart(bar, [{ opacity: 1 }, { opacity: 0 }], 160, { fill: 'forwards' }).then(() => bar.remove());
    animateStart(card, [{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], 380);
  }
  checkStartFolder();
  focusStart();
  syncHover();
}

// The card folds back into the bar, and the keyboard goes back to the app you were in. Words not sent are kept for the
// next card, so an Esc can't lose them.
function closeCard() {
  const card = dockCard();
  if (state.dock?.text.trim()) state.startDraft = state.dock.text;
  state.dock = null;
  newButton.classList.remove('open');
  if (!card) return;
  card.querySelector('.c-box')?.blur();
  let bar = null;
  resizeDock(() => {
    Object.assign(card.style, { position: 'absolute', left: '6px', right: '6px', top: card.offsetTop + 'px', margin: '0' });
    card.classList.add('leaving');
    if (!dockBox.querySelector(':scope > .dock-bar')) {
      dockBox.insertAdjacentHTML('beforeend', DOCK_BAR);
      bar = dockBox.lastElementChild;
    }
  }, 320);
  if (bar) animateStart(bar, [{ opacity: 0 }, { opacity: 1 }], 260);
  animateStart(card, [{ opacity: 1 }, { opacity: 0 }], 180, { fill: 'forwards' }).then(() => card.remove());
  syncHover();
}

function dockCard() { return dockBox.querySelector(':scope > .row.compose:not(.leaving)'); }
function takeDraft() {
  const text = state.startDraft;
  state.startDraft = '';
  return text;
}
// The caret goes in the card's box, after its words, unless it's there already.
function focusStart() {
  const box = dockCard()?.querySelector('.c-box');
  if (!box || document.activeElement === box) return;
  box.focus({ preventScroll: true });
  box.setSelectionRange(box.value.length, box.value.length);
}

// What changed on the card (its folder, its app, what the app said about the folder): its help line grows, folds or
// changes, and its details line comes in afresh, the part that changed with it. The box with your words isn't touched.
function refreshStartCard(changed) {
  const el = dockCard(), card = state.dock;
  if (!el || !card) return;
  const fresh = rowFrom(startCardHTML(card, state.last.sessions)), main = el.querySelector(':scope > .main');
  const oldHelp = main.querySelector(':scope > .c-help'), newHelp = fresh.querySelector('.c-help');
  if (oldHelp && newHelp) {
    if (oldHelp.outerHTML !== newHelp.outerHTML) oldHelp.replaceWith(newHelp);
  } else if (oldHelp) foldPart(oldHelp, 260);
  else if (newHelp) {
    main.querySelector(':scope > .c-where').before(newHelp);
    growPart(newHelp, 300);
  }
  const newWhere = fresh.querySelector('.c-where');
  main.querySelector(':scope > .c-where').replaceWith(newWhere);
  if (changed) for (const part of newWhere.querySelectorAll(changed)) animateStart(part, SWAP_FRAMES, 380);
  syncHover();
}

// Whether Claude may work in the card's folder, asked of the app each time the card opens or its folder changes
// (folderChecked, below, has the answer).
function checkStartFolder() {
  if (state.dock?.folder) native({ type: 'checkFolder', folder: state.dock.folder });
}

// A folder picked from the card's menu (the app's: the projects listed, or Choose Folder…).
function pickFolder(folder) {
  if (!state.dock) return openCard(folder);
  const project = startProjects(state.last.sessions).find((p) => p.folder === folder);
  Object.assign(state.dock, { folder, name: project?.name || base(folder), problem: null });
  refreshStartCard('.w-proj');
  checkStartFolder();
  focusStart();
}

function startMenu(anchor) {
  const r = anchor.getBoundingClientRect();
  native({ type: 'startMenu', x: r.left - 4, y: r.bottom + 4, current: state.dock?.folder || null,
           projects: startProjects(state.last.sessions).map(({ folder, name }) => ({ folder, name })) });
}

function switchStartApp() {
  if (!state.dock || !state.startOptions.terminal) return;
  state.dock.app = state.dock.app === 'terminal' ? 'desktop' : 'terminal';
  state.dock.problem = null;
  refreshStartCard('.w-app');
  focusStart();
}

// The box grows with your words, up to four lines, then scrolls.
function fitStartBox(box) {
  box.style.height = '27px';
  box.style.height = Math.min(box.scrollHeight + 2, 72) + 'px';
  box.style.overflowY = box.scrollHeight + 2 > 72 ? 'auto' : 'hidden';
}

// ---- Starting ----

// Return or Start: the app is asked to start it at once, the card hands over to its row, and the row rises to its place
// in the list. With ⌘, a fresh card is ready below at once, for the next one, and keeps the keyboard. A conversation
// only opened in Claude (no words) has no row until something is sent in it, so its card just folds away.
function sendStart(more) {
  const card = state.dock, el = dockCard();
  if (!card || !el) return;
  const { go, trust } = startState(card, state.folders);
  if (!go) return focusStart();
  const words = el.querySelector('.c-box').value.trim(), id = `start-${Date.now()}-${++startsMade}`;
  const start = { id, key: id, folder: card.folder, name: card.name, app: card.app, words, at: Date.now(), trust: !!trust,
                  quiet: card.app === 'desktop' && !words };
  if (card.app === 'terminal') start.key = start.sessionId = newSessionId();
  native({ type: 'start', startId: id, folder: card.folder, app: card.app, words,
           ...(start.sessionId ? { sessionId: start.sessionId } : {}), ...(trust ? { trust: true } : {}),
           ...(more ? { stay: true } : {}) });
  if (trust) state.folders[card.folder] = { trusted: true, here: true };
  state.starts[id] = start;
  if (start.quiet) {
    setTimeout(() => delete state.starts[id], 30000);  // only to say why, if it didn't open
    hop();
    if (!more) return closeCard();
    card.text = '';
    const box = el.querySelector('.c-box');
    box.value = '';
    fitStartBox(box);
    return refreshStartCard();
  }
  el.classList.add('leaving');
  if (more) {
    state.dock = { id: `card${++startsMade}`, folder: card.folder, name: card.name, app: card.app, text: '', problem: null };
    const next = rowFrom(startCardHTML(state.dock, state.last.sessions));
    resizeDock(() => dockBox.append(next), 420);
    animateStart(next, [{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], 380);
    focusStart();
  } else {
    state.dock = null;
    newButton.classList.remove('open');
  }
  handOverStart(el, start).then(() => {
    hop();
    riseToRow(el, start, !more);
  });
}

// The card turns into the row it starts, in place. Your words stay where you wrote them: the box around them fades and
// settles to their first line, the rest cut off from below, and they dim to the row's "You" line. The card's controls
// fade, its caret folds away (and, grouped by project, the folder, which rows there leave to their group), and Claude's
// line grows in under your words, saying it's starting. Its dot fills and starts to pulse as a working row's does.
function handOverStart(el, start) {
  const main = el.querySelector(':scope > .main'), box = el.querySelector('.c-box');
  const you = main.querySelector(':scope > .you'), where = main.querySelector(':scope > .c-where');
  const look = getComputedStyle(box), motions = [];
  const from = { borderColor: look.borderColor, backgroundColor: look.backgroundColor };
  box.readOnly = true;
  box.blur();
  if (!D_START(1)) return Promise.resolve();
  const gone = { borderColor: 'rgba(255, 255, 255, 0)', backgroundColor: 'rgba(0, 0, 0, 0)',
                 clipPath: 'inset(0px 0px 6px 0px)' };
  motions.push(animateStart(box, [{ ...from, color: 'rgba(255, 255, 255, 0.92)', height: box.offsetHeight + 'px',
                                    clipPath: 'inset(0px 0px 0px 0px)' },
                                  { ...gone, offset: 0.4 }, { ...gone, color: 'rgba(255, 255, 255, 0.55)', height: '27px' }],
                            300, { fill: 'forwards' }));
  motions.push(start.words ? animateStart(you, [{ marginTop: '7px' }, { marginTop: '3px' }], 300, { fill: 'forwards' })
                           : foldPart(you, 300));
  const help = main.querySelector(':scope > .c-help');
  if (help) motions.push(foldPart(help, 320, 0.4));
  motions.push(animateStart(where, [{ marginTop: getComputedStyle(where).marginTop }, { marginTop: '4px' }], 320,
                            { fill: 'forwards' }));
  for (const control of el.querySelectorAll('.c-x, .c-go'))
    motions.push(animateStart(control, [{ opacity: 1 }, { opacity: 0 }], 160, { fill: 'forwards' }));
  const bits = [...el.querySelectorAll('.caret')];
  const folder = where.querySelector('.w-proj');
  if (state.groupBy === 'project' && folder) bits.push(folder, ...(folder.nextElementSibling?.matches('.sep') ? [folder.nextElementSibling] : []));
  for (const bit of bits) motions.push(collapsePart(bit, 280));
  motions.push(animateStart(el.querySelector('.name'), [{ color: 'rgba(255, 255, 255, 0.55)' }, { color: 'rgba(255, 255, 255, 0.92)' }],
                            320, { fill: 'forwards' }));
  motions.push(animateStart(el, [{ backgroundColor: 'rgba(255, 255, 255, 0.05)' }, { backgroundColor: 'rgba(255, 255, 255, 0)' }],
                            420, { fill: 'forwards' }));
  // In step with every working row's dot (phase in util.js).
  const dot = el.querySelector(':scope > .dot');
  Object.assign(dot.style, { animation: 'blink 1.4s ease-in-out infinite',
                             animationDelay: `-${Math.round(performance.now() % 1400)}ms` });
  motions.push(animateStart(dot, [{ backgroundColor: 'rgba(255, 255, 255, 0)', boxShadow: 'inset 0 0 0 1.5px rgba(255, 255, 255, 0.5)' },
                                  { backgroundColor: 'rgba(255, 255, 255, 0.62)', boxShadow: 'inset 0 0 0 0 rgba(255, 255, 255, 0)' }],
                            320, { fill: 'forwards' }));
  const row = rowFrom(rowHTML(pendingSessions({ [start.id]: { ...start, drawn: true } }, [], state.startOptions.terminal)[0],
                              'busy', state.last.now));
  const claude = row.querySelector(':scope > .main > .claude');
  if (claude) {
    (start.words ? you : main.querySelector(':scope > .line1')).after(claude);
    motions.push(growPart(claude, 520));
  }
  return settled(Promise.all(motions), 1500);
}

// The row rises from the box to its place in the list, gliding over the rows as they make room; the box eases back to
// its bar, or to the card waiting for the next one. The row is drawn in the list from the start, hidden until the copy
// rising to it lands.
function riseToRow(el, start, toBar) {
  const root = document.getElementById('root').getBoundingClientRect(), from = el.getBoundingClientRect();
  start.drawn = true;
  start.flying = true;
  render();
  const row = rowAt(start.key), list = document.getElementById('list');
  if (row) {  // the list scrolls to show where it lands, if it's out of view
    const r = row.getBoundingClientRect(), view = list.getBoundingClientRect();
    if (r.top < view.top) list.scrollTop -= view.top - r.top + 4;
    else if (r.bottom > view.bottom) list.scrollTop += r.bottom - view.bottom + 4;
  }
  let bar = null;
  resizeDock(() => {
    el.remove();
    if (toBar && !state.dock && !dockBox.querySelector(':scope > .dock-bar')) {
      dockBox.insertAdjacentHTML('beforeend', DOCK_BAR);
      bar = dockBox.lastElementChild;
    }
  }, 520);
  if (bar) animateStart(bar, [{ opacity: 0 }, { opacity: 1 }], 360, { delay: D_START(160), fill: 'backwards' });
  const landed = () => {
    start.flying = false;
    for (const r of document.querySelectorAll('#list .row.landing')) if (r.dataset.id === start.key) r.classList.remove('landing');
    forgetStarted(state.last.sessions);
    syncHover();
  };
  if (!D_START(1)) return landed();
  const ghost = row ? row.cloneNode(true)
    : rowFrom(rowHTML(pendingSessions({ [start.id]: start }, [], state.startOptions.terminal)[0], 'busy', state.last.now));
  ghost.classList.remove('landing', 'arrive', 'is-hover');
  ghost.classList.add('glide');
  Object.assign(ghost.style, { left: from.left - root.left + 'px', top: from.top - root.top + 'px', width: from.width + 'px' });
  flightLayer.append(ghost);
  // With nowhere in view to land, the row it became fades where it is.
  const to = row?.getBoundingClientRect();
  const flight = to ? [{ transform: 'none' }, { transform: `translate(${to.left - from.left}px, ${to.top - from.top}px)` }]
                    : [{ opacity: 1 }, { opacity: 0 }];
  settled(animateStart(ghost, flight, to ? 800 : 300, { fill: 'forwards' }), 2000).then(() => {
    landed();
    ghost.remove();
  });
}

// A row in the list by its key, the one in view (a row pinned below its folded group is there twice).
function rowAt(key) {
  return [...document.querySelectorAll('#list .row[data-id]')].find((r) => r.dataset.id === key && !r.closest('.closed'))
    || null;
}

// What the app says about a start: the session it became (a Claude Desktop conversation, now known by its id: the row
// already drawn takes that id, so the rebuild carries it on as one row), a note while it waits (your words are in
// Claude's box, say), or why it didn't start, which shows for a while before the row folds away. A folder it was to
// trust is asked about again next time. A conversation only opened has no row: its card comes back to say why.
function startWent(startId, info) {
  const start = state.starts[startId];
  if (!start) return;
  if (info.why && start.trust) delete state.folders[start.folder];
  if (start.quiet) {
    delete state.starts[startId];
    if (!info.why) return;
    if (!state.dock) openCard(start.folder, start.app);
    if (state.dock?.folder === start.folder) {
      state.dock.problem = info.why;
      refreshStartCard();
    }
    return;
  }
  if (info.sessionId && info.sessionId !== start.key) {
    for (const row of document.querySelectorAll('#list .row[data-id]')) if (row.dataset.id === start.key) row.dataset.id = info.sessionId;
    start.key = start.sessionId = info.sessionId;
    start.note = null;
  }
  if (info.note) start.note = info.note;
  if (info.why) {
    Object.assign(start, { why: info.why, note: null });
    setTimeout(() => {
      delete state.starts[startId];
      renderWhenSettled();
    }, 12000);
  }
  renderWhenSettled();
}

// A new session's id, as Claude Code writes them: a random UUID (version 4), in lower case. The page's own
// randomUUID where WebKit offers it, else made the same way from random bytes.
function newSessionId() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

// The pawn hops once: a conversation has started from here.
function hop() {
  const mark = document.querySelector('header .mark');
  if (!mark || !D_START(1)) return;
  mark.classList.remove('hop');
  void mark.getBoundingClientRect();
  mark.classList.add('hop');
}

// ---- Motion helpers (Web Animations, skipped with reduced motion) ----

const D_START = (ms) => (calm.matches ? 0 : ms);
const START_EASE = 'cubic-bezier(.2, .8, .2, 1)', START_OUT = 'cubic-bezier(.4, 0, .2, 1)';
const SWAP_FRAMES = [{ opacity: 0, transform: 'translateY(3px)', filter: 'blur(1.5px)' },
                     { opacity: 1, transform: 'none', filter: 'none' }];
const NO_BOX = { height: '0px', marginTop: '0px', paddingTop: '0px', paddingBottom: '0px' };

// A motion's end, or the end of `ms`, whichever comes first: WebKit holds animations back while the panel can't be seen
// (hidden from the pawn menu, say), and a start shouldn't wait on that to show its row.
function settled(motion, ms) {
  return Promise.race([motion, new Promise((done) => setTimeout(done, ms))]);
}
function animateStart(el, frames, ms, opts = {}) {
  if (!el || !D_START(ms)) return Promise.resolve();
  return el.animate(frames, { duration: ms, easing: opts.easing || START_EASE, ...opts }).finished.catch(() => {});
}
function boxSizes(el) {
  const cs = getComputedStyle(el);
  return { height: el.offsetHeight + 'px', marginTop: cs.marginTop, paddingTop: cs.paddingTop, paddingBottom: cs.paddingBottom };
}
// A line grows in from nothing, fading and lifting into place.
function growPart(el, ms) {
  const to = { ...boxSizes(el), opacity: 1, transform: 'none' };
  el.style.overflow = 'hidden';
  return animateStart(el, [{ ...NO_BOX, opacity: 0, transform: 'translateY(3px)' }, to], ms)
    .then(() => { el.style.overflow = ''; });
}
// A line folds away to nothing; `fadeBy` is how far through the fold its words are gone.
function foldPart(el, ms, fadeBy = 1) {
  const from = { ...boxSizes(el), opacity: 1 };
  const frames = fadeBy < 1 ? [from, { opacity: 0, offset: fadeBy }, { ...NO_BOX, opacity: 0 }] : [from, { ...NO_BOX, opacity: 0 }];
  el.style.overflow = 'hidden';
  return animateStart(el, frames, ms, { easing: START_OUT, fill: 'forwards' }).then(() => el.remove());
}
// A small part of a line goes, giving its room to what follows.
function collapsePart(el, ms) {
  const cs = getComputedStyle(el);
  el.style.overflow = 'hidden';
  return animateStart(el, [{ width: el.offsetWidth + 'px', opacity: 1, paddingLeft: cs.paddingLeft, paddingRight: cs.paddingRight },
                           { width: '0px', opacity: 0, paddingLeft: '0px', paddingRight: '0px' }], ms, { fill: 'forwards' })
    .then(() => el.remove());
}
// The box at the bottom eases from its height before a change to its height after.
let dockMotion = null;
function resizeDock(change, ms) {
  const before = dockBox.getBoundingClientRect().height;
  dockMotion?.cancel();
  change();
  const after = dockBox.getBoundingClientRect().height;
  reportHeight();
  if (Math.abs(after - before) < 0.5 || !D_START(ms)) { dockBox.style.overflow = ''; return; }
  dockBox.style.overflow = 'hidden';
  const motion = dockBox.animate([{ height: before + 'px' }, { height: after + 'px' }], { duration: ms, easing: START_EASE });
  dockMotion = motion;
  const started = performance.now();
  (function follow() {  // the panel follows the box's height as it eases
    reportHeight();
    if (performance.now() - started < ms + 40) requestAnimationFrame(follow);
  })();
  motion.finished.catch(() => {}).then(() => {
    if (dockMotion !== motion) return;
    dockMotion = null;
    dockBox.style.overflow = '';
    reportHeight();
  });
}
function rowFrom(html) {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

// ---- Presses, keys and typing in the box ----

dockBox.innerHTML = DOCK_BAR;
dockBox.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  const t = e.target;
  if (t.closest('.dock-bar')) {
    e.preventDefault();
    return openCard(null, e.altKey ? 'terminal' : null);
  }
  if (!t.closest('.row.compose:not(.leaving)') || t.closest('.c-box')) return;  // a box takes the caret as usual
  e.preventDefault();
  if (t.closest('.c-x')) return closeCard();
  if (t.closest('.c-go')) return sendStart(e.metaKey || e.ctrlKey);
  if (t.closest('.w-app')) return switchStartApp();
  if (t.closest('.w-proj')) return startMenu(t.closest('.w-proj'));
  focusStart();
});
newButton.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  if (state.dock) closeCard();
  else openCard(null, e.altKey ? 'terminal' : null);
});
dockBox.addEventListener('input', (e) => {
  const box = e.target.closest('.c-box'), card = state.dock;
  if (!box || !card || box.closest('.leaving')) return;
  card.text = box.value;
  fitStartBox(box);
  const { go } = startState(card, state.folders), label = box.closest('.row').querySelector('.go-label');
  if (go && label && label.textContent !== go) label.textContent = go;
});
dockBox.addEventListener('keydown', (e) => {
  if (e.key === 'Meta') document.body.classList.add('cmd');
  if (!e.target.closest('.c-box') || e.isComposing || e.keyCode === 229) return;
  if (e.key === 'Escape') {
    e.preventDefault();
    closeCard();
  } else if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendStart(e.metaKey || e.ctrlKey);
  }
});
dockBox.addEventListener('keyup', (e) => { if (e.key === 'Meta') document.body.classList.remove('cmd'); });
// The panel has the keyboard only while one of its boxes is typed in (wantKeyboard in input.js).
dockBox.addEventListener('focusin', (e) => { if (e.target.closest('.c-box')) wantKeyboard(true); });
dockBox.addEventListener('focusout', (e) => {
  if (!e.target.closest('.c-box')) return;
  document.body.classList.remove('cmd');
  wantKeyboard(false);
});

// ---- What the app says ----

// ⌃⌥N or New Conversation in the pawn menu (no folder or app: the card chooses), or a folder picked for the card from
// its menu: the box at the bottom opens its card for a new conversation.
window.openStart = (folder, app) => openCard(folder, app);
window.startProject = (folder) => pickFolder(folder);

// Whether Claude may work in a folder, as the app found it when the card asked (checkFolder): { trusted } or { gone }.
// A folder trusted from the card since it asked stays trusted.
window.folderChecked = (folder, info) => {
  if (state.folders[folder]?.here && !info.gone) return;
  state.folders[folder] = info.gone ? { gone: true } : { trusted: !!info.trusted };
  if (state.dock?.folder === folder) refreshStartCard();
};

// How a start went (app/Starts.m): the session it became, a note while it waits, or why it didn't start.
window.startUpdate = (startId, info) => startWent(startId, info);

// What a start can open in: the terminal (its name), or null when there's none, and the card offers Claude only.
window.setStartOptions = (options) => {
  state.startOptions = { terminal: options?.terminal || null };
  if (state.dock?.app === 'terminal' && !state.startOptions.terminal) state.dock.app = 'desktop';
  refreshStartCard();
};

// ---- What it plugs into ----

// The starts not listed yet are drawn with the rest, as pending rows, which have no work of their own to speak for,
// change or wait for; one listed is done with once its row has landed. Its row stays hidden while its copy rises to it.
core.moreRows.push((listed) => pendingSessions(state.starts, listed, state.startOptions.terminal));
core.updating.push(forgetStarted);
core.slots.rowClass.push((row) => (startLanding(row.s.sessionId) ? ' landing' : ''));
// A project's ＋ opens the card for that project (⌥: in the terminal). Claude Desktop's scratch conversations have no
// folder to start in.
core.slots.project.push((p) => (p.scratch ? '' : `<span class="add" data-folder="${esc(p.key)}"`
  + ` title="New conversation in ${esc(p.name)} (⌥: in the terminal)">${PLUS_ICON}</span>`));
core.presses.push(['.add[data-folder]', (add, e) => {
  e.preventDefault();
  openCard(add.dataset.folder, e.altKey ? 'terminal' : null);
}]);
core.pointerTargets.push('.add', '.add-new', '.dock-bar', '.c-x', '.c-go:not(:disabled)', '.w-app', '.w-proj');
core.textBoxes.push('.c-box');
core.strips.push('dock');

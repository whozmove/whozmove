// Starting a new conversation: the card that opens under the panel's header, shaped like the row it becomes; the
// pending row a start shows as until Claude lists its session; and how the card hands over to that row and moves down
// to its place in the list.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A start goes to the app (app/Starts.m) the moment it's pressed. Meanwhile the card turns into the row it starts, in
// place, so your words stay where you wrote them, and that row moves from the card's place down to its place in the
// list. It waits there as a pending row until the session is listed, when the session's own row takes over under the
// same key, and morph carries it on as one row. A terminal start's session id is made here and given to Claude Code,
// so its row has that key from the start; Claude Desktop picks its own, which the app says once the conversation shows
// up (startUpdate).

// The card open under the header, { id, folder, name, app, text, problem, target, list } or null: `target`, where in
// its project it starts when not its own folder ({ kind: open, branch, path, where }, { kind: branch, name } or { kind:
// new, name, base, named, check }), and `list`, what `@` or `#` offers under the box ({ kind, head, items, sel, token,
// foot }), and `picked` once you chose its project. What a card not sent yet holds (startDraft: its project, where in
// it, the app and your words), kept as it changes, across restarts too, for the next card to open with; the starts sent but not
// yet listed, by start id, { id, key, sessionId, folder, name, app, words, worktree, path, makes, at, trust, terminal,
// drawn, flying, note, why }; what Claude may do in each folder, as the app last said, { trusted } or { gone }
// ({ trusted, here } once you trusted it on the card); what each folder's repo has, for `#` (branchesListed); the
// terminal a start opens in, the one picked on the card's menu (setStartOptions), null when there's none; and the app
// last chosen or started in, which the next card starts with.
moduleState({ dock: null, startDraft: store.get('startDraft', null), starts: {}, folders: {}, repos: {},
              startOptions: { terminal: null }, startApp: store.get('startApp', 'desktop') });

// A plus, on a project's header.
const PLUS_ICON = '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M6 1.5v9M1.5 6h9" stroke="currentColor" '
  + 'stroke-width="1.6" stroke-linecap="round"/></svg>';

const dockBox = document.getElementById('dock'), flightLayer = document.getElementById('flight');
const newButton = document.querySelector('header .add-new'), newTitle = newButton.title;
let startsMade = 0;

// The header's ＋ is the card's ×, turned, while the card is open.
function markNewButton(open) {
  newButton.classList.toggle('open', open);
  newButton.title = open ? 'Close (Esc)' : newTitle;
}

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
// conversation Claude shows, or the session in the tab a terminal shows), else of the one you were last on (goTo), else
// the one most recently active; null with nothing listed.
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
// can't start, as while the app is still asked about the folder, or with no words yet).
// Claude asks once before working in a folder it hasn't worked in; the card asks instead, and its button trusts the
// folder as it starts (`trust`). Why the last start from the card didn't go through takes the help line's place.
function startState(card, folders) {
  const folder = card.folder && folders[card.folder];
  if (!card.folder) return { help: 'Choose the folder it starts in.', warn: false, go: '' };
  if (folder?.gone) return { help: `${card.name} isn't there any more: choose another folder.`, warn: true, go: '' };
  const untrusted = folder?.trusted === false;
  const go = !folder || !card.text.trim() ? '' : untrusted ? 'Trust and start' : 'Start';
  const help = card.problem || (untrusted ? `Claude hasn't worked in ${card.name} before. Trusting it lets Claude Code `
    + 'read, edit and run files there.' : '');
  return { help, warn: !!help, go, ...(untrusted ? { trust: true } : {}) };
}

// ---- Where in its project it starts ----

// The app a card starts in: the terminal for anything in a worktree (Claude Desktop starts only in the folders it
// lists), else the one chosen, which is Claude Desktop when there's no terminal to choose.
function startApp(card) {
  return state.startOptions.terminal && (inWorktree(card.target) || card.app === 'terminal') ? 'terminal' : 'desktop';
}
const appLabel = (app) => (app === 'terminal' ? state.startOptions.terminal || 'the terminal' : 'Claude');

// What the card says, and whether it can start (`go`, '' while it can't): about its folder (startState), else about a
// new worktree, which starts once git has said it can be made there (worktreeNameChecked).
function cardState(card) {
  const said = startState(card, state.folders), t = card.target;
  if (said.help || t?.kind !== 'new') return said;
  if (!t.name) return { help: 'Name the new worktree: #name.', warn: true, go: '' };
  const c = t.check;
  if (!c || c.name !== t.name || (c.base && c.base !== t.base)) return { ...said, go: '' };
  if (c.why) return { help: c.why, warn: true, go: '' };
  return said;
}

// A word under the box while the card's folder is busy and it starts there: another session's agent at work, or changes
// not committed yet. Using a new worktree keeps this conversation's work apart from them: one press.
function busyHint(card, sessions) {
  const repo = state.repos[card.folder];
  if (card.target || !repo || repo.none || !state.startOptions.terminal) return '';
  const here = sessions.filter((s) => !s.pending && s.git?.root === card.folder);
  if (here.some((s) => s.status === 'busy')) return `Claude is at work in ${card.name}.`;
  const changed = Math.max(0, ...here.map((s) => s.checkout?.changes || 0));
  if (!changed) return '';
  return `${changed === 1 ? '1 changed file' : `${changed} changed files`} in ${card.name} `
    + `${changed === 1 ? "isn't" : "aren't"} committed yet.`;
}

// Where it starts, on chips under the box, where the row's details line will be: the project (press it, or type @), then where in it (press it, or type #): its
// own folder on its branch; or a worktree (worktreeChip), one that's there, or a new one, for a branch that's there
// or a new branch, after the branch it starts from on a chip of its own: the project, what it comes from, then it.
function chipsHTML(card) {
  const repo = state.repos[card.folder], t = card.target;
  const chips = [`<span class="st-chip c-proj" data-k="p" title="The project it starts in: press, or type @, for another">`
    + `<i>@</i><span class="c-pname">${esc(card.name)}</span></span>`];
  if (repo && !repo.none) {
    const tip = 'Where in it: press, or type #, for a worktree';
    if (!t) chips.push(`<span class="st-chip c-in" data-k="b" title="${tip}">${BRANCH_ICON}${esc(repo.here?.branch || 'detached')}</span>`);
    else if (t.kind === 'open') chips.push(worktreeChip(t.branch, 'st-chip c-in', ` data-k="b" title="${tip}"`));
    else {
      if (t.kind === 'new') chips.push(`<span class="st-chip c-base" data-k="base" title="The branch it starts from">`
        + `<span class="c-from">from</span>${BRANCH_ICON}${esc(t.base || '')}</span>`);
      chips.push(worktreeChip(t.name || 'name it', 'st-chip c-in', ` data-k="b" title="A new worktree: `
        + `${t.kind === 'new' ? 'a new branch' : 'this branch'}, in a folder of its own"`));
    }
  }
  return `<div class="st-chips">${chips.join('')}</div>`;
}

// What `@` or `#` offers, under the box, the one picked lit; ↑↓ move, Return or Tab take it, Esc closes it.
function listHTML(card) {
  const l = card.list;
  if (!l) return '';
  const option = (it) => {
    if (l.kind === '@') return it.choose ? '<span class="o-l o-soft">Choose another folder…</span>'
      : `<span class="o-l">${esc(it.name)}</span>${it.folder === card.folder ? '<span class="o-s">here now</span>' : ''}`;
    if (it.kind === 'here') return `<span class="o-l">${BRANCH_ICON}${esc(it.branch || 'detached')}</span><span class="o-s">its own folder</span>`;
    if (it.kind === 'open') return `<span class="o-l">${WORKTREE_ICON}${esc(it.branch)}</span><span class="o-s">a worktree</span>`;
    if (it.kind === 'branch') return `<span class="o-l">${BRANCH_ICON}${esc(it.name)}</span><span class="o-s">no folder yet: a new worktree</span>`;
    return `<span class="o-l"><b class="o-new">${WORKTREE_ICON}New worktree</b>${esc(it.name)}<span class="o-from">from</span>${esc(it.base || '')}</span>`;
  };
  return `<div class="c-list" data-k="list">${l.head ? `<div class="c-lhead">${esc(l.head)}</div>` : ''}`
    + l.items.map((it, i) => `<div class="c-opt${i === l.sel ? ' on' : ''}" data-i="${i}">${option(it)}</div>`).join('')
    + `${l.foot ? `<div class="c-lfoot">${l.foot}</div>` : ''}</div>`;
}

// The list for what's being written (or for a chip pressed, with nothing written): the projects for `@`, and for `#`
// what the card's project has, once the app has said, or why there's nothing to choose.
function listFor(card, token) {
  if (token.kind === '@') {
    const items = projectChoices(startProjects(state.last.sessions), token.query);
    return { kind: '@', head: 'Project', items: [...items, { choose: true }], sel: 0, token };
  }
  const repo = state.repos[card.folder], none = (foot) => ({ kind: '#', items: [], sel: 0, token, foot });
  if (!repo) return none(`Looking at ${esc(card.name)}’s branches…`);
  if (repo.none) return none(`${esc(card.name)} isn’t a git repository, so it has no worktrees.`);
  if (!state.startOptions.terminal) return none('Worktrees start in a terminal, and there’s none here.');
  const items = worktreeChoices(repo, token.query, token.from, card.text), last = items.at(-1);
  const other = [...repo.worktrees.map((w) => w.branch), ...repo.branches].find((b) => b !== last?.base) || 'release';
  const foot = token.from === undefined && last?.kind === 'new'
    ? `Add <b>from</b> and a branch to start it from another: <b>#${esc(last.name)} from ${esc(other)}</b>` : '';
  const head = token.from !== undefined ? `A new worktree, ${items[0]?.name || ''}, from which branch?` : 'Where in it';
  return { kind: '#', head, items, sel: 0, token, foot };
}

// The line under the box: where it runs, or, for a new worktree, the folder it goes in, which can be put elsewhere
// (where a repo's new worktrees go, remembered for the repo).
function underHTML(card) {
  const repo = state.repos[card.folder], t = card.target;
  if (card.list || !repo) return '';
  if (repo.none) return `<div class="c-under" data-k="u">Runs in ${esc(repo.where)}</div>`;
  if (!t) return `<div class="c-under" data-k="u">Runs in ${esc(repo.here.where)}`
    + `${repo.here.branch ? `, on ${esc(repo.here.branch)}` : ''}</div>`;
  if (t.kind === 'open') return `<div class="c-under" data-k="u">Runs in ${esc(t.where)}</div>`;
  const where = t.check?.name === t.name && t.check.where ? t.check.where : `${repo.folder}/${(t.name || '').replace(/\//g, '-')}`;
  return `<div class="c-under" data-k="u">New folder: <span class="c-place" title="Where new worktrees of `
    + `${esc(card.name)} go: press to choose">${esc(where)}<span class="caret">${CHEVRON_ICON}</span></span></div>`;
}

// The project and where in it, chosen: from `@`'s list, the project (worktrees are its own again); from `#`'s, the
// target, a new worktree's name your own when you wrote it, else following your words.
function pickChoice(i) {
  const card = state.dock, l = card?.list, it = l?.items[i], el = dockCard();
  if (!it || !el) return;
  const box = el.querySelector('.c-box');
  if (l.token?.start !== undefined) {   // what was written to choose it goes, the rest stays
    box.value = box.value.slice(0, l.token.start) + box.value.slice(l.token.end).replace(/^\s+/, '');
    box.value = box.value.replace(/\s+$/, '') + (box.value.trim() ? ' ' : '');
    card.text = box.value;
    fitStartBox(box);
  }
  card.list = null;
  if (l.kind === '@') {
    if (it.choose) native({ type: 'startMenu', kind: 'choose' });
    else setStartFolder(it.folder, it.name);
  } else {
    card.target = it.kind === 'here' ? null : { ...it, named: it.kind === 'new' && !!l.token?.query };
    askWorktreeName();
  }
  refreshStartCard();
  focusStart();
}

// The list opens for a chip pressed, or follows what's written: it's shut once there's no `@` or `#` before the caret.
function openList(kind) {
  const card = state.dock;
  if (!card) return;
  card.list = card.list?.kind === kind && card.list.token?.start === undefined ? null
    : listFor(card, { kind, query: '', from: undefined });
  refreshStartCard();
  focusStart();
}
function followWords(box) {
  const card = state.dock, token = startToken(box.value, box.selectionStart);
  const was = card.list;
  if (token) card.list = listFor(card, token);
  else if (was?.token?.start !== undefined) card.list = null;
  else return was !== card.list;
  if (was && card.list && was.kind === card.list.kind) card.list.sel = Math.min(was.sel, Math.max(0, card.list.items.length - 1));
  return true;
}

// A new worktree can be made: asked of the app once its name or base stops changing for a moment.
let nameAsk = null;
function askWorktreeName() {
  clearTimeout(nameAsk);
  const card = state.dock, t = card?.target;
  if (t?.kind !== 'new' || !t.name || (t.check?.name === t.name && t.check.base === t.base)) return;
  nameAsk = setTimeout(() => native({ type: 'checkWorktreeName', folder: card.folder, name: t.name,
                                      ...(t.base ? { base: t.base } : {}) }), 250);
}

// What the repo the card's folder is in has, for `#`: asked as the card opens or its folder changes (branchesListed).
function listBranches() {
  if (state.dock?.folder) native({ type: 'listBranches', folder: state.dock.folder });
}

// One press for a busy folder: a new worktree, named from your words, from the repo's base branch.
function useNewWorktree() {
  const card = state.dock, repo = card && state.repos[card.folder];
  if (!repo || repo.none) return;
  card.target = { kind: 'new', name: worktreeName(card.text), base: repo.base, named: false };
  card.list = null;
  askWorktreeName();
  refreshStartCard();
  focusStart();
}

// ---- The card ----

// Start names what it does only as it's about to: the app's icon alone with no words yet, the app's name once there
// are some, and while ⌘ is held (⌘Return starts it), "Start in" before it.
const goVerb = (go) => `${go || 'Start'} in\u00a0`;  // a space that stays at the end of its own box
function setGoButton(button, card) {
  const { go } = cardState(card);
  easeButton(button, () => {
    button.disabled = !go;
    button.classList.toggle('empty', !card.text.trim());
    const verb = button.querySelector('.go-verb');
    if (verb && verb.textContent !== goVerb(go)) verb.textContent = goVerb(go);
  });
}
// The button's words open and close to their own width, measured before and after, so each moves at one pace however
// long it is, and the button grows to the left from its right edge.
function easeButton(button, change) {
  const parts = button ? [...button.querySelectorAll('.go-label, .go-verb')] : [];
  const look = (part) => {
    const cs = getComputedStyle(part);
    return { maxWidth: part.getBoundingClientRect().width + 'px', marginLeft: cs.marginLeft, opacity: cs.opacity };
  };
  const was = parts.map(look);
  change();
  parts.forEach((part, i) => {
    const now = look(part);
    if (now.maxWidth !== was[i].maxWidth) animateStart(part, [was[i], now], 220);
  });
}
// ⌘ held, with the box in use: Start says what ⌘Return does.
function holdCommand(held) {
  if (document.body.classList.contains('cmd') === held) return;
  easeButton(dockCard()?.querySelector('.c-go'), () => document.body.classList.toggle('cmd', held));
}

// Shaped like the row it becomes: its dot and its name, your words in a box, then where it starts on chips, in the
// place the row's details line takes, what `@` and `#` offer as you write them, the line saying where it runs, and
// Start, naming the app, with the app's menu beside it.
function startCardHTML(card, sessions) {
  const { help, warn, go } = cardState(card), busy = help ? '' : busyHint(card, sessions);
  const app = startApp(card), empty = !card.text.trim();
  const button = `<span class="c-split"><button class="c-go${empty ? ' empty' : ''}"${go ? '' : ' disabled'} title="⌘Return starts it">`
    + `${app === 'terminal' ? TERMINAL_ICON : DESKTOP_ICON}<span class="go-label"><span class="go-verb">${esc(goVerb(go))}</span>`
    + `${esc(appLabel(app))}</span></button>`
    + `${state.startOptions.terminal ? `<button class="st-app" title="Start it in another app">${CHEVRON_ICON}</button>` : ''}</span>`;
  return `<div class="row compose" data-card="${esc(card.id)}">
      <span class="dot"></span>
      <div class="main">
        <div class="line1"><span class="name">New conversation</span></div>
        <div class="you"><span class="who">You</span><textarea class="c-box" id="${esc(card.id)}-words" rows="2"
          spellcheck="false" aria-label="What should Claude do?" placeholder="What should Claude do? @ for a project, # for a worktree">${esc(card.text)}</textarea></div>
        ${chipsHTML(card)}${listHTML(card)}${underHTML(card)}
        ${busy ? `<div class="c-busy" data-k="busy"><span>${esc(busy)}</span><button class="c-usewt">Use a new worktree</button></div>` : ''}
        ${help ? `<div class="c-help${warn ? ' warn' : ''}" data-k="help">${esc(help)}</div>` : ''}
        <div class="st-foot">${button}</div>
      </div>
    </div>`;
}

// The starts not listed yet, as sessions for the list: working rows that say they're starting (in the terminal each
// started in, else `terminal`), or what they wait for, or why they didn't start. Each is keyed by the session id it
// will be listed under, once that's known. One still handing over in the box isn't drawn yet.
function pendingSessions(starts, sessions, terminal) {
  const listed = new Set(sessions.map((s) => s.sessionId));
  return Object.values(starts).filter((start) => start.drawn && !listed.has(start.key)).map((start) => {
    // One starting in a worktree shows it as its row will: its branch, in the worktree's folder.
    const repo = checkoutOf(start.folder, sessions);
    const g = start.worktree ? { branch: start.worktree, root: start.path, worktree: start.worktree,
                                 worktreeOf: base(repo?.mainRoot || start.folder), mainRoot: repo?.mainRoot || start.folder }
      : repo;
    const where = start.terminal || terminal || 'the terminal';
    return {
      sessionId: start.key, pending: true, name: 'New conversation', cwd: start.worktree ? start.path : start.folder,
      prs: [], agent: {},
      entrypoint: start.app === 'desktop' ? 'claude-desktop' : 'cli', status: 'busy', statusUpdatedAt: start.at,
      lastPromptAt: start.at, ...(start.words ? { lastPrompt: start.words } : {}), ...(g ? { git: g } : {}),
      activity: start.why || start.note || (start.makes ? `Making the worktree ${start.worktree}, then starting in `
        + where : `Starting in ${start.app === 'desktop' ? 'Claude' : where}`),
      ...(start.why || start.note ? { startProblem: true } : {}),
    };
  });
}

// Whether a row is a start's that hasn't reached it yet: its card is still handing over under the header, or its copy
// is still moving to it (moveToRow). It stays hidden until the copy lands, even once Claude lists the session.
function startLanding(id) {
  return Object.values(state.starts).some((start) => (!start.drawn || start.flying) && start.key === id);
}

// The starts Claude has listed are done with once their rows have landed: the session's own row is theirs now.
function forgetStarted(sessions) {
  const listed = new Set(sessions.map((s) => s.sessionId));
  for (const [id, start] of Object.entries(state.starts))
    if (start.drawn && !start.flying && listed.has(start.key)) delete state.starts[id];
}

// The card, opened under the header: its place eases open and the list moves down to make room (as the panel opens,
// when it was folded into the cat). Or the card brought up to date when it's open already, keeping your words and where
// you are in them. The panel takes the keyboard for its box (wantKeyboard). While a start is still on its way down from
// there, the new card waits unseen until the way is clear, so nothing passes over it.
function openCard(folder, app) {
  const folded = document.body.classList.contains('collapsed');
  if (folded) toggleCollapsed();
  const sessions = state.last.sessions, was = state.dock;
  wantKeyboard(true);
  if (was && !folder && !app) return focusStart();
  // A card not sent yet comes back as it was: your words always, and where it starts unless it opens for another project.
  const draft = was ? null : state.startDraft, same = draft && (!folder || draft.folder === folder);
  const where = folder ? startProjects(sessions).find((p) => p.folder === folder) || { folder, name: base(folder) }
    : was ? { folder: was.folder, name: was.name } : same && draft.folder ? { folder: draft.folder, name: draft.name }
    : defaultStartFolder(sessions, state.current);
  state.dock = {
    id: was?.id || `card${++startsMade}`, folder: where?.folder || null, name: where?.name || 'Choose a folder',
    app: app === 'terminal' && state.startOptions.terminal ? 'terminal' : app === 'desktop' ? 'desktop'
      : was?.app || (same && draft.app) || state.startApp,
    text: was?.text || draft?.text || '', problem: null, target: (same && draft.target) || null, list: null,
    picked: was?.picked || (same && draft.picked) || false,
  };
  markNewButton(true);
  if (was && dockCard()) refreshStartCard();
  else {
    const card = rowFrom(startCardHTML(state.dock, sessions));
    if (dockBox.querySelector(':scope > .row.compose.sent')) waitOver(card);
    else {
      const flying = flightLayer.querySelector(':scope > .row');
      if (flying) card.classList.add('unseen');
      resizeDock(() => {
        dockBox.append(card);
        fitStartBox(card.querySelector('.c-box'));
      }, folded ? 0 : 420);
      if (flying) showWhenClear(card, flying);
      else {
        // What the app says about the folder while it opens fills it in place (refreshStartCard), in this one motion.
        card.classList.add('opening');
        animateStart(card, [{ opacity: 0, transform: 'translateY(-4px)' }, { opacity: 1, transform: 'none' }], 380)
          .then(() => card.classList.remove('opening'));
      }
    }
  }
  checkStartFolder();
  listBranches();
  focusStart();
  syncHover();
}

// The card goes, fading as its place eases shut and the list moves back up, and the keyboard goes back to the app you
// were in. What it holds was kept as it changed (keepDraft), so an Esc can't lose it. A card still waiting unseen just goes.
function closeCard() {
  const card = dockCard();
  keepDraft();
  state.dock = null;
  markNewButton(false);
  if (!card) return;
  card.querySelector('.c-box')?.blur();
  if (card.matches('.waiting, .unseen')) {
    resizeDock(() => card.remove(), 320);
    return syncHover();
  }
  resizeDock(() => {
    Object.assign(card.style, { position: 'absolute', left: '6px', right: '6px', top: card.offsetTop + 'px', margin: '0' });
    card.classList.add('leaving');
  }, 320);
  animateStart(card, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-4px)' }], 300,
               { fill: 'forwards' }).then(() => card.remove());
  syncHover();
}

function dockCard() { return dockBox.querySelector(':scope > .row.compose:not(.leaving)'); }
// What the card holds, kept for the next one, until it's sent: only once there's something of yours in it (words, where
// in its project, or a project you chose), so a card opened and closed again leaves the next one to start where you are.
function keepDraft() {
  const card = state.dock, t = card?.target;
  if (!card) return;
  const draft = card.text.trim() || t || card.picked
    ? { folder: card.folder, name: card.name, app: card.app, text: card.text, picked: !!card.picked,
        target: t ? { ...t, check: null } : null }
    : null;
  state.startDraft = draft;
  store.set('startDraft', draft);
}
// The caret goes in the card's box, after its words, unless it's there already.
function focusStart() {
  const box = dockCard()?.querySelector('.c-box');
  if (!box || document.activeElement === box) return;
  box.focus({ preventScroll: true });
  box.setSelectionRange(box.value.length, box.value.length);
}

// What changed on the card (where it starts, what's offered, what the app said): each part of it that changed comes in
// afresh where it is, a chip or a line within it lit, while the card's place eases to its new height. What's under a
// part that opened or closed slides to its new place with the card's edge, measured where it was and where it lands,
// so nothing jumps; a part that's gone fades where it was. The list follows your typing. The box with your words isn't
// touched.
const CARD_PARTS = ['.c-list', '.c-under', '.c-busy', '.c-help', '.st-foot'];
function refreshStartCard() {
  const el = dockCard(), card = state.dock;
  if (!el || !card) return;
  keepDraft();
  const fresh = rowFrom(startCardHTML(card, state.last.sessions));
  const main = el.querySelector(':scope > .main'), mine = fresh.querySelector(':scope > .main');
  const partOf = (child) => child.className.split(' ')[0], opening = el.classList.contains('opening');
  const parts = [...main.querySelectorAll(':scope > :not(.gone)')];
  const tops = new Map(parts.map((child) => [partOf(child), child.getBoundingClientRect().top]));
  const places = new Map(parts.map((child) => [child, { left: child.offsetLeft, top: child.offsetTop, width: child.offsetWidth }]));
  resizeDock(() => {
    const swap = (old, neu, whole) => {
      if (old.outerHTML === neu.outerHTML) return old;
      const was = new Map([...old.querySelectorAll('[data-k]')].map((e) => [e.dataset.k, e.outerHTML]));
      old.replaceWith(neu);
      if (opening) return neu;
      if (whole) animateStart(neu, SWAP_FRAMES, 300);
      else for (const part of neu.querySelectorAll('[data-k]'))
        if (was.get(part.dataset.k) !== part.outerHTML) animateStart(part, SWAP_FRAMES, 340);
      return neu;
    };
    swap(main.querySelector(':scope > .st-chips'), mine.querySelector(':scope > .st-chips'), false);
    // The parts under the chips, in order: kept, changed, gone or new, each in its place after the one before.
    let after = main.querySelector(':scope > .st-chips');
    for (const sel of CARD_PARTS) {
      const old = main.querySelector(`:scope > ${sel}:not(.gone)`), neu = mine.querySelector(`:scope > ${sel}`);
      if (old && !neu) opening ? old.remove() : fadeWhereItWas(old, places.get(old));
      else if (old) after = sel === '.c-list' ? (old.replaceWith(neu), neu) : swap(old, neu, sel !== '.st-foot');
      else if (neu) {
        after.after(neu);
        after = neu;
        if (opening) continue;
        // It opens downward once what was in its place has gone (fadeWhereItWas), so the two are never drawn together.
        const shut = { opacity: 0, clipPath: 'inset(0px 0px 100% 0px)' };
        animateStart(neu, [shut, { ...shut, offset: 0.4, easing: START_EASE }, { opacity: 1, clipPath: 'inset(0px)' }], 260,
                     { easing: 'linear' });
      }
    }
    if (opening) return;
    for (const child of main.querySelectorAll(':scope > :not(.gone)')) {
      const was = tops.get(partOf(child)), dy = was === undefined ? 0 : was - child.getBoundingClientRect().top;
      if (Math.abs(dy) > 0.5) animateStart(child, [{ transform: `translateY(${dy}px)` }, { transform: 'none' }], 240);
    }
  }, 240);
  syncHover();
}
// A part of the card that's gone stays a moment where it was, out of the way of the rest, fading before what takes
// its place opens there.
function fadeWhereItWas(part, was) {
  Object.assign(part.style, { position: 'absolute', left: was.left + 'px', top: was.top + 'px', width: was.width + 'px',
                              margin: '0', pointerEvents: 'none' });
  part.classList.add('gone');
  animateStart(part, [{ opacity: 1 }, { opacity: 0 }], 100, { fill: 'forwards' }).then(() => part.remove());
}

// Whether Claude may work in the card's folder, asked of the app each time the card opens or its folder changes
// (folderChecked, below, has the answer).
function checkStartFolder() {
  if (state.dock?.folder) native({ type: 'checkFolder', folder: state.dock.folder });
}

// A folder for the card: from `@`'s list, or Choose another folder… (the app's chooser). Where in it starts afresh.
function setStartFolder(folder, name) {
  const card = state.dock;
  if (!card) return openCard(folder);
  const project = startProjects(state.last.sessions).find((p) => p.folder === folder);
  Object.assign(card, { folder, name: name || project?.name || base(folder), problem: null, target: null, list: null,
                        picked: true });
  checkStartFolder();
  listBranches();
}
function pickFolder(folder) {
  if (!state.dock) return openCard(folder);
  setStartFolder(folder);
  refreshStartCard();
  focusStart();
}

// The box grows with your words, up to four lines, then scrolls; it's never shorter than the two lines it opens with,
// so typing never shakes the card.
const BOX_LEAST = 44, BOX_MOST = 72;
function fitStartBox(box) {
  box.style.height = BOX_LEAST + 'px';
  box.style.height = Math.min(Math.max(box.scrollHeight + 2, BOX_LEAST), BOX_MOST) + 'px';
  box.style.overflowY = box.scrollHeight + 2 > BOX_MOST ? 'auto' : 'hidden';
}

// ---- Starting ----

// ⌘Return or Start: the app is asked to start it at once, the card hands over to its row, and the row moves down to its
// place in the list. A card still waiting to show starts nothing yet.
function sendStart() {
  const card = state.dock, el = dockCard();
  if (!card || !el || el.matches('.waiting, .unseen')) return;
  if (card.list) return pickChoice(card.list.sel);
  const { go, trust } = cardState(card);
  if (!go) return focusStart();
  const words = el.querySelector('.c-box').value.trim(), id = `start-${Date.now()}-${++startsMade}`;
  // Where in the project: a worktree's branch and folder go with the start, for its row to show until it's listed.
  const t = card.target, app = startApp(card), repo = state.repos[card.folder];
  const worktree = t ? (t.kind === 'open' ? t.branch : t.name) : null;
  const path = !t ? null : t.kind === 'open' ? t.path : t.check?.path || `${repo?.folderPath}/${t.name.replace(/\//g, '-')}`;
  const start = { id, key: id, folder: card.folder, name: card.name, app, words, worktree, path, makes: !!t && t.kind !== 'open',
                  at: Date.now(), trust: !!trust, terminal: app === 'terminal' ? state.startOptions.terminal : null };
  if (app === 'terminal') start.key = start.sessionId = newSessionId();
  const target = !t ? null : t.kind === 'open' ? { kind: 'open', path: t.path } : t.kind === 'branch'
    ? { kind: 'branch', name: t.name } : { kind: 'new', name: t.name, ...(t.base ? { base: t.base } : {}) };
  native({ type: 'start', startId: id, folder: card.folder, app, words,
           ...(start.sessionId ? { sessionId: start.sessionId } : {}), ...(trust ? { trust: true } : {}),
           ...(target ? { target } : {}) });
  // Sent, so there's nothing to keep for the next card.
  Object.assign(card, { text: '', target: null, picked: false });
  keepDraft();
  state.startApp = card.app;
  store.set('startApp', card.app);
  if (trust) state.folders[card.folder] = { trusted: true, here: true };
  state.starts[id] = start;
  el.classList.add('leaving', 'sent');
  state.dock = null;
  markNewButton(false);
  handOverStart(el, start).then(() => {
    hop();
    moveToRow(el, start);
  });
}

// A card made while a start is still handing over in the card's place waits there unseen, laid over it, with the
// keyboard, so what's typed goes in. Once that start's copy moves off, it takes the place, and it shows when the way
// down is clear (moveToRow).
function waitOver(card) {
  card.classList.add('waiting');
  dockBox.append(card);
  fitStartBox(card.querySelector('.c-box'));
}

// The card turns into the row it starts, in place. Your words stay where you wrote them: the box around them fades and
// settles to their first line, the rest cut off from below, they dim to the row's "You" line, and its "You" opens in
// front of them. The card's own parts fold away (its chips, the line under the box, Start), and the row's lines grow
// in: Claude's under your words, saying it's starting, and the details line, saying where. Its dot fills and starts to
// pulse as a working row's does.
function handOverStart(el, start) {
  const main = el.querySelector(':scope > .main'), box = el.querySelector('.c-box');
  const you = main.querySelector(':scope > .you');
  const look = getComputedStyle(box), motions = [];
  const from = { borderColor: look.borderColor, backgroundColor: look.backgroundColor };
  box.readOnly = true;
  box.blur();
  if (!D_START(1)) return Promise.resolve();
  // The box's edge and padding go as it settles, so the words end where the row's own words are. Its words, the row's
  // name and its dot change to the row's own colours, as the panel's look has them now.
  const text = tokenColour('--text'), muted = tokenColour('--muted');
  const gone = { borderColor: 'rgba(255, 255, 255, 0)', backgroundColor: 'rgba(0, 0, 0, 0)',
                 clipPath: 'inset(0px 0px 0px 0px)' };
  const flat = { padding: '0px', borderWidth: '0px' };
  motions.push(animateStart(box, [{ ...from, color: text, height: box.offsetHeight + 'px',
                                    padding: look.padding, borderWidth: look.borderWidth, clipPath: 'inset(0px 0px 0px 0px)' },
                                  { ...gone, offset: 0.4 }, { ...gone, ...flat, color: muted, height: '15px' }],
                            300, { fill: 'forwards' }));
  motions.push(animateStart(you, [{ marginTop: '6px' }, { marginTop: '3px' }], 300, { fill: 'forwards' }));
  if (start.words) {
    const who = you.querySelector('.who');
    who.classList.add('said');
    motions.push(animateStart(who, [{ maxWidth: '0px', opacity: 0 }, { maxWidth: '42px', opacity: 1 }], 300, { fill: 'forwards' }));
  } else motions.push(foldPart(you, 300));
  for (const part of main.querySelectorAll(':scope > .c-list, :scope > .c-under, :scope > .c-busy, :scope > .c-help, '
                                         + ':scope > .st-foot'))
    motions.push(foldPart(part, 320, 0.4));
  motions.push(animateStart(el.querySelector('.name'), [{ color: muted }, { color: text }],
                            320, { fill: 'forwards' }));
  motions.push(animateStart(el, [{ backgroundColor: tokenColour('--surface') }, { backgroundColor: 'rgba(255, 255, 255, 0)' }],
                            420, { fill: 'forwards' }));
  // In step with every working row's dot (phase in util.js).
  const dot = el.querySelector(':scope > .dot');
  Object.assign(dot.style, { animation: 'blink 1.4s ease-in-out infinite',
                             animationDelay: `-${Math.round(performance.now() % 1400)}ms` });
  motions.push(animateStart(dot, [{ backgroundColor: 'rgba(255, 255, 255, 0)',
                                    boxShadow: `inset 0 0 0 1.5px ${tokenColour('--compose-dot')}` },
                                  { backgroundColor: tokenColour('--working-dot'),
                                    boxShadow: 'inset 0 0 0 0 rgba(255, 255, 255, 0)' }],
                            320, { fill: 'forwards' }));
  const row = rowFrom(rowHTML(pendingSessions({ [start.id]: { ...start, drawn: true } }, state.last.sessions,
                                              state.startOptions.terminal)[0], 'busy', state.last.now));
  const claude = row.querySelector(':scope > .main > .claude'), where = row.querySelector(':scope > .main > .where');
  if (claude) {
    (start.words ? you : main.querySelector(':scope > .line1')).after(claude);
    motions.push(growPart(claude, 520));
  }
  const chips = main.querySelector(':scope > .st-chips');
  if (where && chips) motions.push(chipsBecome(chips, where));
  else {
    if (chips) motions.push(foldPart(chips, 320, 0.4));
    if (where) {
      main.append(where);
      motions.push(growPart(where, 520));
    }
  }
  return settled(Promise.all(motions), 1500);
}

// The chips turn into the row's details line where they are, as Claude's line opens above them: what's on both moves
// along the line from where the card had it to where the row has it, the project's name and the branch, or the
// worktree's chip, settling to the row's size; and the rest fades, the @ and the chips' backgrounds, the branch a new
// worktree starts from, going, and the app's icon and the dots between coming in. Nothing leaves the line, and nothing
// moves until what's in its way has gone (`clear`, the part of the way through the chips have faded by).
function chipsBecome(chips, where) {
  const ms = 440, clear = 0.3, motions = [];
  const start = { height: chips.offsetHeight + 'px', marginTop: getComputedStyle(chips).marginTop };
  chips.before(where);
  const to = boxSizes(where);
  Object.assign(where.style, { position: 'relative', ...start });
  Object.assign(chips.style, { position: 'absolute', left: '0', right: '0', top: '0', margin: '0' });
  where.append(chips);
  const box = (el) => el.getBoundingClientRect();
  const centre = (r) => r.top + r.height / 2;
  const kept = new Set();
  const carry = (from, onto, keyframes) => {
    if (!from || !onto) return;
    const a = box(from), b = box(onto), lead = (el) => el.querySelector('svg') || el;
    const at = keyframes ? a : box(lead(from)), into = keyframes ? b : box(lead(onto));
    const move = `translate(${at.left - into.left}px, ${centre(a) - centre(b)}px)`;
    kept.add(onto);
    if (keyframes) {
      from.style.visibility = 'hidden';
      const was = { transform: move, ...keyframes(from) };
      motions.push(animateStart(onto, [was, { ...was, offset: clear, easing: START_EASE }, { transform: 'none', ...keyframes(onto) }],
                                ms, { easing: 'linear' }));
    } else {
      motions.push(animateStart(onto, [{ transform: move, opacity: 0 }, { transform: move, opacity: 0.5, offset: clear,
                                                                          easing: START_EASE },
                                       { transform: 'none', opacity: 1 }], ms, { easing: 'linear' }));
    }
  };
  carry(chips.querySelector('.c-pname'), where.querySelector('.proj'));
  const card = chips.querySelector('.c-in'), row = where.querySelector('.branch');
  if (card?.matches('.wt') && row?.matches('.wt')) {
    // The worktree's chip is the same chip throughout, settling from the card's size to the row's.
    carry(card, row, (el) => {
      const cs = getComputedStyle(el);
      return { height: el.offsetHeight + 'px', paddingLeft: cs.paddingLeft, paddingRight: cs.paddingRight,
               borderRadius: cs.borderRadius };
    });
  } else carry(card, row);
  for (const part of where.children)
    if (part !== chips && !kept.has(part))
      motions.push(animateStart(part, [{ opacity: 0 }, { opacity: 0, offset: 0.35, easing: START_EASE }, { opacity: 1 }], ms,
                                { easing: 'linear' }));
  motions.push(animateStart(chips, [{ opacity: 1 }, { opacity: 0 }], ms * clear, { fill: 'forwards' }));
  motions.push(animateStart(where, [start, { height: to.height, marginTop: to.marginTop }], ms));
  Object.assign(where.style, { height: '', marginTop: '' });  // the line's own size once its motion is done
  return Promise.all(motions).then(() => {
    chips.remove();
    where.style.position = '';
  });
}

// The row moves from the card's place down to its place in the list, gliding over the rows as they make room, while
// the card's place eases shut behind it (or takes the card waiting for the next one) and the list moves up to meet it.
// The row is drawn in the list from the start, hidden until the copy moving to it lands. Where it lands is measured as
// the page will be once all that has eased (asItEnds), with the list scrolled first to show it there, clear of the row
// you're on if that holds on at the list's edge (showInList), so the copy lands exactly on it; and it catches up with
// whatever moves the row while it's on its way (catchUp).
function moveToRow(el, start) {
  const root = document.getElementById('root').getBoundingClientRect(), from = el.getBoundingClientRect();
  start.drawn = true;
  start.flying = true;
  render();
  let next = null, to = null;
  resizeDock(() => {
    el.remove();
    next = dockBox.querySelector(':scope > .row.compose.waiting');
    next?.classList.replace('waiting', 'unseen');
  }, 520, () => {
    to = asItEnds(() => {
      const row = rowAt(start.key);
      if (!row) return null;
      showInList(row);
      return row.getBoundingClientRect();
    });
  });
  const landed = () => {
    start.flying = false;
    for (const r of document.querySelectorAll('#list .row.landing')) if (r.dataset.id === start.key) r.classList.remove('landing');
    forgetStarted(state.last.sessions);
    showWaiting(next);
    syncHover();
  };
  if (!D_START(1)) return landed();
  const row = rowAt(start.key);
  const ghost = row ? row.cloneNode(true)
    : rowFrom(rowHTML(pendingSessions({ [start.id]: start }, [], state.startOptions.terminal)[0], 'busy', state.last.now));
  ghost.classList.remove('landing', 'arrive', 'is-hover');
  ghost.classList.add('glide');
  Object.assign(ghost.style, { left: from.left - root.left + 'px', top: from.top - root.top + 'px', width: from.width + 'px' });
  flightLayer.append(ghost);
  showWhenClear(next, ghost);
  // With nowhere in view to land, the row it became fades where it is.
  const flight = to ? [{ transform: 'none' }, { transform: `translate(${to.left - from.left}px, ${to.top - from.top}px)` }]
                    : [{ opacity: 1 }, { opacity: 0 }];
  settled(animateStart(ghost, flight, to ? 800 : 300, { fill: 'forwards' }), 2000)
    .then(() => (to ? catchUp(ghost, start, from) : null))
    .then(() => {
      landed();
      ghost.remove();
    });
}

// Measures as the page will be once the card's place and the list have finished easing, and puts both back where they
// were before anything is drawn.
function asItEnds(measure) {
  const ease = dockMotion?.playState === 'running' ? dockMotion : null, at = ease?.currentTime ?? 0;
  if (ease) ease.currentTime = ease.effect.getTiming().duration;
  try { return atListEnd(measure); } finally { if (ease) ease.currentTime = at; }
}

// Something can move the row while its copy is on the way (another card opening above the list, the list scrolled):
// the copy then goes the rest of the way, arriving as whatever moved it finishes, so it still lands exactly on the row.
function catchUp(ghost, start, from) {
  const end = asItEnds(() => rowAt(start.key)?.getBoundingClientRect()), at = ghost.getBoundingClientRect();
  if (!end || (Math.abs(end.top - at.top) < 1 && Math.abs(end.left - at.left) < 1)) return null;
  const easing = dockMotion?.playState === 'running' ? dockMotion : null;
  const ms = Math.max(240, easing ? easing.effect.getTiming().duration - easing.currentTime : 0);
  return settled(animateStart(ghost, [{ transform: `translate(${at.left - from.left}px, ${at.top - from.top}px)` },
                                      { transform: `translate(${end.left - from.left}px, ${end.top - from.top}px)` }],
                              ms, { fill: 'forwards' }), ms + 500);
}

// A card waiting to show does once the copy moving down from its place has passed below it, so nothing passes over it;
// or once the copy has landed (landed, above), or at once with no copy.
function showWhenClear(card, ghost) {
  if (!card) return;
  (function watch() {
    if (!card.isConnected || !card.classList.contains('unseen')) return;
    const clear = !ghost.isConnected || ghost.getBoundingClientRect().top >= card.getBoundingClientRect().bottom;
    if (clear) return showWaiting(card);
    requestAnimationFrame(watch);
  })();
}
function showWaiting(card) {
  if (!card?.isConnected || !card.classList.contains('unseen')) return;
  card.classList.remove('unseen');
  animateStart(card, [{ opacity: 0, transform: 'translateY(-4px)' }, { opacity: 1, transform: 'none' }], 360);
}

// A row in the list by its key, the one in view (a row pinned below its folded group is there twice).
function rowAt(key) {
  return [...document.querySelectorAll('#list .row[data-id]')]
    .find((r) => r.dataset.id === key && !r.closest('.prows.closed')) || null;
}

// What the app says about a start: the session it became (a Claude Desktop conversation, now known by its id: the row
// already drawn takes that id, so the rebuild carries it on as one row), a note while it waits (your words are in
// Claude's box, say), or why it didn't start, which shows for a while before the row folds away. A folder it was to
// trust is asked about again next time.
function startWent(startId, info) {
  const start = state.starts[startId];
  if (!start) return;
  if (info.why && start.trust) delete state.folders[start.folder];
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

// The cat in the name hops once: a conversation has started from here.
function hop() {
  const mark = document.querySelector('header .name-cat');
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
// The card's place under the header eases from its height before a change to its height after. `atEnd` runs between
// the two, while the page is laid out as it will end up, for what has to be measured there.
let dockMotion = null;
let dockEnds = 0;
function resizeDock(change, ms, atEnd) {
  const before = dockBox.getBoundingClientRect().height;
  if (dockMotion) ms = Math.max(ms, dockEnds - performance.now());  // a motion under way carries on, to the new height
  dockMotion?.cancel();
  change();
  const after = dockBox.getBoundingClientRect().height;
  atEnd?.();
  reportHeight();
  if (Math.abs(after - before) < 0.5 || !D_START(ms)) { dockBox.style.overflow = ''; return; }
  dockBox.style.overflow = 'hidden';
  const motion = dockBox.animate([{ height: before + 'px' }, { height: after + 'px' }], { duration: ms, easing: START_EASE });
  dockMotion = motion;
  dockEnds = performance.now() + ms;
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

dockBox.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  const t = e.target;
  if (!t.closest('.row.compose:not(.leaving)') || t.closest('.c-box')) return;  // the box takes the caret as usual
  e.preventDefault();
  const card = state.dock;
  if (t.closest('.st-app')) return appMenu(t.closest('.st-app'));
  if (t.closest('.c-go')) return sendStart();
  const option = t.closest('.c-opt');
  if (option) return pickChoice(+option.dataset.i);
  if (t.closest('.c-proj')) return openList('@');
  if (t.closest('.c-in, .c-base')) return openList('#');
  if (t.closest('.c-usewt')) return useNewWorktree();
  if (t.closest('.c-place') && card) return placesMenu(t.closest('.c-place'));
  focusStart();
});
// The app it starts in, and where a repo's new worktrees go: the app's own menus, opened from what was pressed.
function appMenu(anchor) {
  const r = anchor.getBoundingClientRect(), card = state.dock;
  if (card) native({ type: 'startMenu', kind: 'app', x: r.right - 160, y: r.bottom + 4, app: startApp(card),
                     worktree: inWorktree(card.target) });
}
function placesMenu(anchor) {
  const r = anchor.getBoundingClientRect(), g = checkoutOf(state.dock.folder, state.last.sessions);
  native({ type: 'startMenu', kind: 'places', x: r.left - 4, y: r.bottom + 4, repo: g?.mainRoot || g?.root || state.dock.folder });
}
// The header's ＋ opens the card, and closes it while it's open; with the panel folded into the cat, where the card
// can't be seen (⌃⌥N), it opens it.
newButton.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  if (state.dock && !document.body.classList.contains('collapsed')) closeCard();
  else openCard(null, e.altKey ? 'terminal' : null);
});
dockBox.addEventListener('input', (e) => {
  const box = e.target.closest('.c-box'), card = state.dock;
  if (!box || !card || box.closest('.leaving')) return;
  card.text = box.value;
  keepDraft();
  fitStartBox(box);
  let changed = followWords(box);
  // A new worktree's name follows your words until you name it yourself.
  const t = card.target;
  if (t?.kind === 'new' && !t.named && !card.list && worktreeName(card.text) !== t.name) {
    Object.assign(t, { name: worktreeName(card.text), check: null });
    askWorktreeName();
    changed = true;
  }
  if (changed) return refreshStartCard();
  const button = box.closest('.row').querySelector('.c-go');
  if (button) setGoButton(button, card);
});
dockBox.addEventListener('keydown', (e) => {
  if (e.key === 'Meta') holdCommand(true);
  if (e.isComposing || e.keyCode === 229 || !e.target.closest('.c-box')) return;
  const card = state.dock, list = card?.list;
  if (list && list.items.length && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
    e.preventDefault();
    list.sel = (list.sel + (e.key === 'ArrowDown' ? 1 : list.items.length - 1)) % list.items.length;
    return refreshStartCard();
  }
  if (list && (e.key === 'Enter' || e.key === 'Tab') && list.items.length) {
    e.preventDefault();
    return pickChoice(list.sel);
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    if (!list) return closeCard();
    card.list = null;
    return refreshStartCard();
  }
  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    sendStart();
  }
});
dockBox.addEventListener('keyup', (e) => { if (e.key === 'Meta') holdCommand(false); });
// The panel has the keyboard only while one of its boxes is typed in (wantKeyboard in input.js).
dockBox.addEventListener('focusin', (e) => { if (e.target.closest('.c-box')) wantKeyboard(true); });
dockBox.addEventListener('focusout', (e) => {
  if (!e.target.closest('.c-box')) return;
  holdCommand(false);
  wantKeyboard(false);
});

// ---- What the app says ----

// ⌃⌥N or New Conversation in the pawn menu (no folder or app: the card chooses), or a folder picked for the card from
// its menu: the card for a new conversation opens under the header.
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

// What the card's folder's repo has, for `#` (listBranches): its own folder, its worktrees, its branches with no
// folder, its base branch and where new worktrees go; or { none } outside git. A list open for `#` takes it in.
window.branchesListed = (folder, info) => {
  state.repos[folder] = info;
  const card = state.dock;
  if (card?.folder !== folder) return;
  const t = card.target;
  if (info.none || (t?.kind === 'open' && !info.worktrees.some((w) => w.path === t.path))
      || (t?.kind === 'branch' && !info.branches.includes(t.name))) card.target = null;
  if (card.list?.kind === '#') card.list = listFor(card, card.list.token || { kind: '#', query: '', from: undefined });
  if (card.target?.kind === 'new' && !card.target.base) card.target.base = info.base || null;
  askWorktreeName();
  refreshStartCard();
};

// Whether a new worktree can be made, as the app found it (checkWorktreeName): { path, where, name, base }, where it
// would go and the branch it starts from, or { why }. An answer for a name or base since changed is let go.
window.worktreeNameChecked = (folder, name, info) => {
  const t = state.dock?.target;
  if (t?.kind !== 'new' || state.dock.folder !== folder || t.name !== name || (info.base && info.base !== t.base)) return;
  t.check = { name, ...info };
  refreshStartCard();
};

// A repo's new worktrees go somewhere else now (chosen from the card's menu): what it has is asked again, and the new
// worktree's place with it.
window.worktreesMoved = () => {
  const t = state.dock?.target;
  if (t?.kind === 'new') t.check = null;
  listBranches();
  refreshStartCard();
};

// The app chosen from Start's menu: this card starts there, and the next ones too until another is chosen.
window.startAppChosen = (app) => {
  const card = state.dock;
  if (!card) return;
  card.app = app === 'terminal' ? 'terminal' : 'desktop';
  state.startApp = card.app;
  store.set('startApp', card.app);
  refreshStartCard();
  focusStart();
};

// What a start can open in: the terminal picked on the card's menu (its name), told again as you pick another, or null
// when there's none, and the card offers Claude only.
window.setStartOptions = (options) => {
  state.startOptions = { terminal: options?.terminal || null };
  if (!state.startOptions.terminal && state.dock?.target) state.dock.target = null;
  if (state.dock?.app === 'terminal' && !state.startOptions.terminal) state.dock.app = 'desktop';
  refreshStartCard();
};

// ---- What it plugs into ----

// The starts not listed yet are drawn with the rest, as pending rows, which have no work of their own to speak for,
// change or wait for; one listed is done with once its row has landed. Its row stays hidden while its copy moves to it.
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
core.pointerTargets.push('.add', '.add-new', '.c-go:not(:disabled)', '.st-app', '.c-proj', '.c-in', '.c-base',
                         '.c-opt', '.c-place', '.c-usewt');
core.textBoxes.push('.c-box');
core.strips.push('dock');

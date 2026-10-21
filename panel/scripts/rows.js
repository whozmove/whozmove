// The list's HTML: a session's row, and its group and project headers. The row's template is the core's; what the
// modules show on it goes in its places (core.slots), each giving its HTML or nothing.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each section's name on its header, in the order they're shown (SECTIONS in whose-move.js).
const SECTION_NAMES = { turn: 'Your turn', busy: 'Working', seen: 'Seen', idle: 'Idle' };

// The app a session runs in, as a row names it (core.hosts): the module's that holds it (Claude Desktop), else a terminal.
// A terminal session that has ended opens again in the terminal the app names (opensIn).
const TERMINAL_HOST = {
  name: 'Terminal', openNow: 'Open in your terminal now', inName: '',
  closedTip: (s) => (s.opensIn ? `Not running: click to open it in ${s.opensIn}` : 'Not running'),
};
function hostOf(s) {
  return core.hosts.find((host) => host.holds(s)) || TERMINAL_HOST;
}

// A worktree, wherever it shows (a row's details line, the new conversation card): its icon and its branch's name on a
// chip in the worktree colours. Where it sits adds its own classes and attributes (`cls`, `attrs`), and its size.
function worktreeChip(name, cls = '', attrs = '') {
  return `<span class="wt${cls ? ` ${cls}` : ''}"${attrs}>${WORKTREE_ICON}<span class="wt-name">${esc(name)}</span></span>`;
}

// What a place on a row (or a project's header) shows: each module's part there, in the order they were added.
function slot(name, of) {
  return core.slots[name].map((part) => part(of)).join('');
}

// The last exchange under the title, as a chat: your message, and below it Claude's line, each with its label.
// While Claude works, the line shows the step it's on and the turn's time so far, with its label fading in and
// out; when it needs you, what for; then its reply. Both lines stay from one turn to the next, so every change is
// text replaced in place (morph) and nothing moves. A step's name stays up after the step finishes, as in Claude's
// own progress row, and a step shows once it starts running (a hook can't see it sooner). The chat shows while
// Claude works or needs you, and for a reply until its session goes Idle (dimmer once read). Claude's line is its
// reply only when that answers your message: after a turn you stopped, there's only yours. A conversation started
// from the panel and not listed yet (starts.js) says it's starting, or what it waits for, or why it didn't start.
function chatHTML(s, kind, now) {
  if (kind === 'idle' && !s.compacting) return '';
  const you = s.lastPrompt
    ? `<div class="you"><span class="who">You</span><span class="what">${esc(s.lastPrompt)}</span></div>` : '';
  let claude = '';
  if (s.startProblem) {
    claude = `<div class="claude wait" data-mode="wait"><span class="who">Claude</span>`
      + `<span class="what">${esc(s.activity)}</span></div>`;
  } else if (kind === 'busy' || s.compacting) {  // working, or compacting at a word from the panel
    const since = s.compacting || s.lastPromptAt || s.statusUpdatedAt;
    const doing = s.compacting ? 'Compacting the conversation' : s.activity || 'Thinking';
    // The shimmer sits on an inner span: WebKit doesn't paint a cut-off "…" in clipped-to-text colour, so
    // the outer span draws it, in plain grey.
    claude = `<div class="claude work" data-mode="work"><span class="who" style="${phase(2800)}">Claude</span>`
      + `<span class="what"><span class="shine" style="${phase(3000)}">${esc(doing)}</span></span>`
      + (since ? `<span class="elapsed">${elapsed(now - since)}</span>` : '') + '</div>';
  } else {
    const wants = kind === 'needs'
      && (s.ask ? (s.ask.tool === 'AskUserQuestion' ? 'Has a question for you' : 'Needs your OK to go on') : s.notice);
    const text = wants || ((s.lastReplyAt || 0) >= (s.lastPromptAt || 0) ? s.lastReply : '');
    const look = wants ? 'wait' : isRead(s, view()) ? 'reply read' : 'reply';
    if (text) claude = `<div class="claude ${look}" data-mode="${wants ? 'wait' : 'reply'}">`
      + `<span class="who">Claude</span><span class="what">${esc(text)}</span></div>`;
  }
  return you + claude;
}

// The work line, while there's something on it: at its start the session's pull requests (or Create PR, once its
// branch is pushed with none, or where it stands while commits wait), and at its end what isn't committed in the
// checkout and the steps its work has to take. The row's note (stepLine), when it has one, is said in the line's place,
// over what it holds, which stays laid out unseen, so the row keeps its height and nothing under it moves; cut short to
// one line, with all of it over it.
function workHTML(row, note = null) {
  const start = slot('workStart', row), end = slot('numbers', row) + slot('steps', row);
  if (!start && !end) return '';
  const said = note ? `<div class="work-note${note.quiet ? ' quiet' : ''}" title="${esc(note.text)}">`
    + `${esc(note.text)}</div>` : '';
  return `<div class="work${note ? ' noted' : ''}">${start}${end ? `<span class="work-end">${end}</span>` : ''}`
    + `${said}</div>`;
}

// The bottom line, as an editor's status bar has it: how the session's agent is set up at its start (its model, effort
// and mode, and its context ring: the modules' setup), and where it runs at its end: the worktree, or the branch (or,
// outside git, the folder), which pointed at says the project and more (placeCardHTML), and what a module puts after
// it (Deploy's button). Short of room, a long name where it runs (past a dozen letters) shortens first, to about
// that, then the agent's effort and model give way, then the name further; the mode never does.
function whereHTML(row) {
  const { s } = row, g = s.git;
  const branch = g && (g.branch || 'detached @' + g.detached), name = g ? branch : base(s.cwd);
  const place = !g ? `<span class="branch folder">${esc(name)}</span>`
    : g.worktree ? worktreeChip(branch, 'branch') : `<span class="branch">${BRANCH_ICON}${esc(branch)}</span>`;
  const long = [...name].length > 12 ? ' long' : '';
  return `<div class="where">${slot('setup', row)}<span class="gap"></span>`
    + `<span class="place${long}" data-place="${esc(s.sessionId)}">${place}</span>${slot('placeEnd', row)}</div>`;
}

// What where a session runs says when pointed at: its project, then that it's a worktree of it and on which branch (or
// which branch it's on, or that it's a folder outside git), its folder, and the app it runs in.
function placeCardHTML(s) {
  const g = s.git, project = projectOf(s).name;
  const what = !g ? 'A folder outside git'
    : g.worktree ? `A worktree of ${esc(g.worktreeOf || project)}, on branch <b>${esc(g.branch || '')}</b>`
    : g.branch ? `On branch <b>${esc(g.branch)}</b>` : `Detached at <b>${esc(g.detached || '')}</b>`;
  return `<div class="pl-head">${esc(project)}</div><div class="pl-what">${what}</div>`
    + `<div class="pl-path">${esc(g?.root || s.cwd || '')}</div><div class="pl-app">In ${esc(hostOf(s).name)}</div>`;
}

// A conversation open in more than one process at once (s.alsoOpen: resumed in a second tab while it still ran, or open
// in Claude Desktop and a terminal): an icon at the title line's end, in the colour of something to put right, with
// how many times when it's more than twice. Pointed at, its card says where else (twiceCardHTML).
function twiceHTML(s) {
  if (!s.alsoOpen?.length) return '';
  const times = s.alsoOpen.length + 1;
  return `<span class="twice" data-sid="${esc(s.sessionId)}">${TWICE_ICON}`
    + `${times > 2 ? `<span class="twice-n">${times}</span>` : ''}</span>`;
}

// How many times it's open, as its card says it.
function openTimes(s) {
  const times = s.alsoOpen.length + 1;
  return times === 2 ? 'open twice' : `open ${times} times`;
}

// What "open twice" says when pointed at: where else the conversation is open, and what that means. Each copy knows
// only what was said in it since the second opened. Nothing goes into a terminal's copy from the panel while another
// runs in a terminal, where a key could land in the other's tab; with the other in an app of its own (Claude Desktop),
// only its mode can't be changed, as the copies share one record of it. One paused in its terminal (Ctrl+Z), maybe in
// the very tab the row's copy runs in, takes nothing, but brought back it would carry on from where it stopped. The
// other copies in terminals can be closed from the card, the one the row follows staying, but not while one works (the
// app checks again, and that none asks anything); one paused, or in Claude Desktop, is closed where it is.
function twiceCardHTML(s) {
  const own = hostOf(s), running = s.alsoOpen.filter((copy) => !copy.paused);
  const apps = [...new Set(running.map(hostOf).filter((host) => host !== TERMINAL_HOST).map((host) => host.name))];
  const tabs = running.filter((copy) => hostOf(copy) === TERMINAL_HOST).length;
  const other = own === TERMINAL_HOST;
  if (tabs > 1) apps.push(`${tabs} ${other ? 'other ' : ''}terminal tabs`);
  else if (tabs) apps.push(`${other ? 'another' : 'a'} terminal tab`);
  const paused = s.alsoOpen.length - running.length;
  const where = [apps.length && `open in ${apps.join(' and ')}`,
                 paused && `paused in ${paused > 1 ? `${paused} terminals` : 'a terminal'}`].filter(Boolean);
  const knows = 'Each copy knows only what was said in it since the second one opened';
  const help = !running.length
    ? "Brought back with fg, it would carry on without what's been said here since: close it when you can."
    : other && tabs ? `${knows}. The panel types nothing into it while another copy runs in a terminal.`
    : other ? `${knows}, so its mode can't be told here: change it in the terminal.`
    : `${knows}.`;
  const working = running.some((copy) => hostOf(copy) === TERMINAL_HOST && copy.busy);
  const close = tabs
    ? `<div class="st-steps"><button class="st-step" data-act="close"${working ? ' disabled' : ''}>Close the other `
      + `${tabs > 1 ? 'copies' : 'copy'}</button></div>`
      + (working ? `<div class="st-wait">Claude is working there: close it when it's done</div>` : '')
    : '';
  const times = openTimes(s);
  return `<div class="tw-head">${times[0].toUpperCase() + times.slice(1)}</div>
    <div class="tw-where">Also ${esc(where.join(', and '))}</div>
    <div class="tw-help">${esc(help)}</div>${close}`;
}

core.cards.push({
  selector: '.place[data-place]',
  key: (place) => 'place:' + place.dataset.place,
  html(place) {
    const s = state.last.sessions.find((x) => x.sessionId === place.dataset.place);
    return s ? placeCardHTML(s) : '';
  },
});
core.cards.push({
  selector: '.twice[data-sid]',
  key: (twice) => 'twice:' + twice.dataset.sid,
  html(twice) {
    const s = state.last.sessions.find((x) => x.sessionId === twice.dataset.sid);
    return s?.alsoOpen?.length ? twiceCardHTML(s) : '';
  },
  press(key, act) {
    if (act === 'close') native({ type: 'closeCopy', sessionId: key.slice('twice:'.length) });
  },
});
// The icon cross-fades as it comes, and as how many times changes.
core.swaps.push(':scope > .main > .line1 .twice');

// The row's note, { text, quiet } or null: how a step went, or why it couldn't (or why a deploy couldn't start, or its
// command wasn't saved), for 8s; else what a module has to say (the folder's deploy). It's said in the work line's
// place (workHTML), or, on a row without one, on a line of its own over the bottom line (noteHTML).
function noteHTML(note) {
  return note ? `<div class="step-note${note.quiet ? ' quiet' : ''}">${esc(note.text)}</div>` : '';
}
function stepLine(row) {
  const note = state.stepNotes[row.s.sessionId];
  if (note && Date.now() - note.at < 8000) return { text: note.text, quiet: note.quiet };
  for (const say of core.rowNotes) {
    const said = say(row);
    if (said) return said;
  }
  return null;
}

// The card under a row's chat: of the modules' cards that want to show there (a request, Compact, Deploy's set-up),
// the most pressing. The others are told they're away, so one that's back waits again before
// it takes a press.
// Sorted once the modules start, when every card is there (they add them as their scripts load).
const sortCards = () => [...core.rowCards].sort((a, b) => a.order - b.order);
let sortedCards = null;
core.starts.push(() => { sortedCards = sortCards(); });
const rowCards = () => sortedCards ?? sortCards();
function rowCard(row) {
  let html = '', taken = false;
  for (const card of rowCards()) {
    if (!taken && card.wants(row)) {
      taken = true;
      html = card.html(row);
    } else card.away?.(row);
  }
  return html;
}

// A card opening on a row closes the cards that would hide it, the more pressing ones that can be closed (Compact, for
// Deploy's set-up), so it shows.
function openingCard(sid, name) {
  for (const card of rowCards()) {
    if (card.name === name) return;
    card.close?.(sid);
  }
}

// A session's row. `row` is what each module's part is given: the session, what it is now (kind: classify), the section
// it's shown in (a row you've pressed stays where you saw it, and a reply you've read stays in Your turn until you've
// moved on, so the two can differ: sectionOf), the time the rows were sent (now), whether it speaks for its checkout
// while Show Next Steps is on (owner), the page's own clock, which Deploy's press and animations are timed by, and what
// each module found when it first looked at the row (core.rowLooks: its next steps, Deploy's button).
function rowHTML(s, kind, now, section = SECTION_OF[kind]) {
  const row = { s, kind, section, now, owner: state.switches.nextSteps && state.owners.has(s.sessionId),
                clock: Date.now() };
  for (const look of core.rowLooks) look(row);
  // How long ago, on the title line; not while it works (or compacts), when Claude's line has the time.
  const since = kind === 'needs' ? s.statusUpdatedAt || 0 : lastActive(s);
  const time = ago(now - since);
  const closed = s.status === 'closed' ? ' closed' : '';
  const focused = s.focused ? ' focused' : '';
  const tip = s.focused ? hostOf(s).openNow : closed ? hostOf(s).closedTip?.(s) || '' : '';
  const title = tip ? `title="${esc(tip)}"` : '';
  const marks = slot('rowClass', row);  // a module's own classes (a new conversation's row, still landing)
  const note = stepLine(row), work = workHTML(row, note);
  return `<div class="row ${kind}${closed}${focused}${marks}" data-id="${esc(s.sessionId)}" ${title}>
      <span class="dot" style="${kind === 'needs' ? phase(1600) : kind === 'busy' ? phase(1400) : ''}"></span>
      <div class="main">
        <div class="line1">
          <span class="name">${esc(s.name || base(s.cwd))}</span>${slot('name', row)}
          ${kind === 'busy' || s.compacting ? '' : `<span class="time">${time}</span>`}${twiceHTML(s)}
        </div>
        ${chatHTML(s, kind, now)}
        ${rowCard(row)}
        ${work || noteHTML(note)}${whereHTML(row)}
      </div>
    </div>`;
}

// A group's rows in a body that folds to nothing. The conversation open in Claude, any session waiting on you (a
// request, a question or a reply you haven't read), a row you've pressed, and one just started from the panel stay in
// view: while the group is folded, a copy of their row is pinned below it. The original stays in the body, in place, so
// opening the group slides to its true height.
function groupBody(rows, closed) {
  const pinned = closed ? rows.filter((r) => r.s.focused || SECTION_OF[r.kind] === 'turn' || r.held || r.s.pending)
    : [];
  return `<div class="prows${closed ? ' closed' : ''}">${rows.map((r) => r.html).join('')}</div>`
    + (pinned.length ? `<div class="pinned">${pinned.map((r) => r.html).join('')}</div>` : '');
}

// The rows as they're placed (placeRows), each section under its header with its count: Your turn, Working and Seen,
// then Idle, folded until you open it.
function sectionsHTML(placed, now) {
  let html = '';
  for (const section of SECTIONS) {
    const rows = placed.filter((p) => p.section === section)
      .map(({ s, kind, held }) => ({ s, kind, held, html: rowHTML(s, kind, now, section) }));
    if (!rows.length) continue;
    const name = `${SECTION_NAMES[section]}<span class="n">${rows.length}</span>`;
    if (section !== 'idle') {
      html += `<div class="group" data-key="g:${section}">${name}</div>${rows.map((r) => r.html).join('')}`;
      continue;
    }
    html += `<div class="group toggle${state.showIdle ? '' : ' collapsed'}" data-key="g:idle">${name}`
      + `<span class="pchev">${CHEVRON_ICON}</span></div>` + groupBody(rows, !state.showIdle);
  }
  return html;
}

// Projects ordered by most recent activity (each row's latest, from placeRows, so one you've pressed doesn't move its
// project); inside each, its rows as they're placed: Your turn, Working, Seen, Idle. A project's header has its name,
// its chevron, and what the modules put there (＋ for a new conversation in it).
function projectsHTML(placed, now) {
  const projects = new Map();
  for (const p of placed) {
    const of = projectOf(p.s);
    if (!projects.has(of.key)) projects.set(of.key, { ...of, rows: [], latest: 0 });
    const entry = projects.get(of.key);
    entry.rows.push(p);
    entry.latest = Math.max(entry.latest, p.latest);
  }
  return [...projects.values()]
    .sort((a, b) => b.latest - a.latest)
    .map((p) => {
      const closed = !!state.closedProjects[p.key];
      const head = `<div class="project${closed ? ' collapsed' : ''}" data-key="${esc(p.key)}" title="${esc(p.key)}">
            <span class="pname">${esc(p.name)}</span><span class="pchev">${CHEVRON_ICON}</span>
            ${slot('project', p)}
          </div>`;
      const rows = p.rows.map(({ s, kind, section, held }) =>
        ({ s, kind, held, html: rowHTML(s, kind, now, section) }));
      return head + groupBody(rows, closed);
    })
    .join('');
}

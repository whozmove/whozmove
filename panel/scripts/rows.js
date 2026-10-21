// The list's HTML: a session's row, and its group and project headers. The row's template is the core's; what the
// modules show on it goes in its places (core.slots), each giving its HTML or nothing.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each section's name on its header, in the order they're shown (SECTIONS in whose-move.js).
const SECTION_NAMES = { turn: 'Your turn', busy: 'Working', seen: 'Seen', idle: 'Idle' };

// The app a session runs in, as a row names it (core.hosts): the module's that holds it (Claude Desktop), else a terminal.
const TERMINAL_HOST = { name: 'Terminal', icon: TERMINAL_ICON, openNow: 'Open in your terminal now', inName: '' };
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

// The details, on two lines: where the session runs (its app, hostOf; its project, unless grouped by project;
// branch, a worktree's in its colour; and that it's open twice, when it is), ending in what a module puts there (the
// session's own numbers); and how its agent is set up (the modules' setup line: its model, effort and mode, and its
// context ring). Between them, what the modules put under the first line (the island), and a short line when there's
// something to say (stepLine). A session outside git, grouped by project, has nothing else to say on the first line, so
// its Desktop/Terminal icon heads the second.
function metaHTML(row) {
  const { s } = row;
  const end = slot('end', row);
  const under = slot('underWhere', row);
  const note = stepLine(row);
  const noteHTML = note ? `<div class="step-note${note.quiet ? ' quiet' : ''}">${esc(note.text)}</div>` : '';
  const g = s.git;
  const branch = g && (g.branch || 'detached @' + g.detached);
  const where = [];
  if (state.groupBy !== 'project') where.push(`<span class="proj">${esc(projectOf(s).name)}</span>`);
  if (g) where.push(g.worktree ? worktreeChip(branch, 'branch') : `<span class="branch">${BRANCH_ICON}${esc(branch)}</span>`);
  if (s.alsoOpen?.length) where.push(`<span class="twice" data-sid="${esc(s.sessionId)}">${openTimes(s)}</span>`);
  const host = hostOf(s);
  const tip = [s.cwd, g && `branch ${branch}`, g?.worktree && `worktree ${g.worktree} of ${g.worktreeOf}`,
               host.name].filter(Boolean).join('\n');
  const icon = host.icon;
  const setup = slot('setup', row);
  if (!where.length && !end) return under + noteHTML + `<div class="setup" title="${esc(tip)}">${icon}${setup}</div>`;
  return `<div class="where" title="${esc(tip)}">${icon}${where.join('<span class="sep">·</span>')}${end}</div>`
    + under + noteHTML + (setup ? `<div class="setup">${setup}</div>` : '');
}

// A conversation open in more than one process at once (s.alsoOpen: resumed in a second tab while it still ran, or open
// in Claude Desktop and a terminal), as its details line says it.
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

// The line under the details, { text, quiet } or null: how a step from a row's menus went, or why it couldn't (or why
// a deploy couldn't start, or its command wasn't saved), for 8s; else what a module has to say there (the folder's
// deploy).
function stepLine(row) {
  const note = state.stepNotes[row.s.sessionId];
  if (note && Date.now() - note.at < 8000) return { text: note.text, quiet: note.quiet };
  for (const say of core.rowNotes) {
    const said = say(row);
    if (said) return said;
  }
  return null;
}

// The card under a row's chat: of the modules' cards that want to show there (a request, Compact, Deploy's set-up, the
// extra stage's question), the most pressing. The others are told they're away, so one that's back waits again before
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
// each module found when it first looked at the row (core.rowLooks: the island's stages, Deploy's button).
function rowHTML(s, kind, now, section = SECTION_OF[kind]) {
  const row = { s, kind, section, now, owner: state.switches.nextSteps && state.owners.has(s.sessionId),
                clock: Date.now() };
  for (const look of core.rowLooks) look(row);
  // How long ago, on the title line; not while it works (or compacts), when Claude's line has the time.
  const since = kind === 'needs' ? s.statusUpdatedAt || 0 : lastActive(s);
  const time = ago(now - since);
  const closed = s.status === 'closed' ? ' closed' : '';
  const focused = s.focused ? ' focused' : '';
  const tip = s.focused ? hostOf(s).openNow : closed ? 'Not running: click to open in Claude' : '';
  const marks = slot('rowClass', row);  // a module's own classes (a new conversation's row, still landing)
  return `<div class="row ${kind}${closed}${focused}${marks}" data-id="${esc(s.sessionId)}" ${tip ? `title="${tip}"` : ''}>
      <span class="dot" style="${kind === 'needs' ? phase(1600) : kind === 'busy' ? phase(1400) : ''}"></span>
      <div class="main">
        <div class="line1">
          <span class="name">${esc(s.name || base(s.cwd))}</span>${slot('name', row)}
          ${kind === 'busy' || s.compacting ? '' : `<span class="time">${time}</span>`}${slot('time', row)}
        </div>
        ${chatHTML(s, kind, now)}
        ${rowCard(row)}
        ${metaHTML(row)}
        ${slot('after', row)}
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

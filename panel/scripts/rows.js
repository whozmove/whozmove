// The list's HTML: a session's row, and its group and project headers. The row's template is the core's; what the
// modules show on it goes in its places (core.slots), each giving its HTML or nothing.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const STATUS_ORDER = { needs: 0, busy: 1, turn: 2, idle: 3 };

// The app a session runs in, as a row names it (core.hosts): the module's that holds it (Claude Desktop), else a terminal.
const TERMINAL_HOST = { name: 'Terminal', icon: TERMINAL_ICON, openNow: 'Open in your terminal now', inName: '' };
function hostOf(s) {
  return core.hosts.find((host) => host.holds(s)) || TERMINAL_HOST;
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
// Claude works or needs you, and for a reply while "Your turn" lasts (dimmer once read). A conversation started from
// the panel and not listed yet (starts.js) says it's starting, or what it waits for, or why it didn't start.
function chatHTML(s, kind, now) {
  const replied = s.lastReplyAt || 0;
  const recentReply = s.lastReply && replied > (s.lastPromptAt || 0) && now - replied < YOUR_TURN_MS;
  if (kind === 'idle' && !recentReply && !s.compacting) return '';
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
    const text = wants || s.lastReply;
    const look = wants ? 'wait' : kind === 'idle' || isRead(s, state.seen) ? 'reply read' : 'reply';
    if (text) claude = `<div class="claude ${look}" data-mode="${wants ? 'wait' : 'reply'}">`
      + `<span class="who">Claude</span><span class="what">${esc(text)}</span></div>`;
  }
  return you + claude;
}

// The details, on two lines: where the session runs (its app, hostOf; its project, unless grouped by project;
// branch; worktree), ending in what a module puts there (the session's own numbers) or else in what the work has been
// through (proofHTML); and how its agent is set up (the modules' setup line: its model, effort and mode, and its
// context ring). Between them, what the modules put under the first line (the island), and a short line when there's
// something to say (stepLine). A session outside git, grouped by project, has nothing else to say on the first line, so
// its Desktop/Terminal icon heads the second.
function metaHTML(row) {
  const { s, kind } = row;
  const end = slot('end', row) || proofHTML(s, kind);
  const under = slot('underWhere', row);
  const note = stepLine(row);
  const noteHTML = note ? `<div class="step-note${note.quiet ? ' quiet' : ''}">${esc(note.text)}</div>` : '';
  const g = s.git;
  const branch = g && (g.branch || 'detached @' + g.detached);
  const where = [];
  if (state.groupBy !== 'project') where.push(`<span class="proj">${esc(projectOf(s).name)}</span>`);
  if (g) where.push(`<span class="branch">${BRANCH_ICON}${esc(branch)}</span>`);
  if (g?.worktree) where.push(`<span class="wt">worktree</span>`);
  const host = hostOf(s);
  const tip = [s.cwd, g && `branch ${branch}`, g?.worktree && `worktree ${g.worktree} of ${g.worktreeOf}`,
               host.name].filter(Boolean).join('\n');
  const icon = host.icon;
  const setup = slot('setup', row);
  if (!where.length && !end) return under + noteHTML + `<div class="setup" title="${esc(tip)}">${icon}${setup}</div>`;
  return `<div class="where" title="${esc(tip)}">${icon}${where.join('<span class="sep">·</span>')}${end}</div>`
    + under + noteHTML + (setup ? `<div class="setup">${setup}</div>` : '');
}

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

// What the work has been through, beside its state (workProof in whose-move.js).
function proofHTML(s, kind) {
  const proof = workProof(s, kind);
  return proof ? `<span class="proof" title="${esc(proof.tip)}">${esc(proof.text)}</span>` : '';
}

// An idle row's current action (currentAction), as a coloured tag. A working row shows what it's doing on Claude's
// line instead (chatHTML), and a row that needs you shows what for. A row whose work a module shows in more detail
// (`shown`: its island) leaves it to that.
function stageHTML(s, kind, shown) {
  if (kind === 'busy' || kind === 'needs' || shown) return '';
  const action = currentAction(s);
  return action ? `<span class="stage o-${action[1]}">${esc(action[0])}</span>` : '';
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

// A session's row. `row` is what each module's part is given: the session, its section (kind), the time the rows were
// sent (now), whether it speaks for its checkout while Show Next Steps is on (owner), the page's own clock, which
// Deploy's press and animations are timed by, and what each module found when it first looked at the row
// (core.rowLooks: the island's stages, Deploy's button).
function rowHTML(s, kind, now) {
  const row = { s, kind, now, owner: state.switches.nextSteps && state.owners.has(s.sessionId), clock: Date.now() };
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
          ${stageHTML(s, kind, row.workShown)}
          ${kind === 'busy' || s.compacting ? '' : `<span class="time">${time}</span>`}${slot('time', row)}
        </div>
        ${chatHTML(s, kind, now)}
        ${rowCard(row)}
        ${metaHTML(row)}
        ${slot('after', row)}
      </div>
    </div>`;
}

// A group's rows in a body that folds to nothing. The conversation open in Claude, any session that needs you (a
// request or question waiting), and one just started from the panel stay in view: while the group is folded, a copy of
// their row is pinned below it. The original stays in the body, in place, so opening the group slides to its true
// height.
function groupBody(rows, closed) {
  const pinned = closed ? rows.filter((r) => r.s.focused || r.kind === 'needs' || r.s.pending) : [];
  return `<div class="prows${closed ? ' closed' : ''}">${rows.map((r) => r.html).join('')}</div>`
    + (pinned.length ? `<div class="pinned">${pinned.map((r) => r.html).join('')}</div>` : '');
}

// Projects ordered by most recent activity; inside each, sessions by status, then recency (sortKey). A project's header
// has its name, its chevron, and what the modules put there (＋ for a new conversation in it).
function projectsHTML(sessions, now) {
  const projects = new Map();
  for (const s of sessions) {
    const p = projectOf(s);
    if (!projects.has(p.key)) projects.set(p.key, { ...p, sessions: [], latest: 0 });
    const entry = projects.get(p.key);
    entry.sessions.push(s);
    entry.latest = Math.max(entry.latest, sortKey(s, classify(s, now, view())));
  }
  return [...projects.values()]
    .sort((a, b) => b.latest - a.latest)
    .map((p) => {
      const closed = !!state.closedProjects[p.key];
      const rows = p.sessions
        .map((s) => ({ s, kind: classify(s, now, view()) }))
        .sort((a, b) => STATUS_ORDER[a.kind] - STATUS_ORDER[b.kind]
                        || sortKey(b.s, b.kind) - sortKey(a.s, a.kind));
      const head = `<div class="project${closed ? ' collapsed' : ''}" data-key="${esc(p.key)}" title="${esc(p.key)}">
            <span class="pname">${esc(p.name)}</span><span class="pchev">${CHEVRON_ICON}</span>
            ${slot('project', p)}
          </div>`;
      return head + groupBody(rows.map(({ s, kind }) => ({ s, kind, html: rowHTML(s, kind, now) })), closed);
    })
    .join('');
}

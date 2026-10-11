// The list's HTML: a session's row, and its group and project headers.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const MAX_PRS = 3;

const MODE_NAMES = {
  default: 'Ask', acceptEdits: 'Edits', plan: 'Plan', auto: 'Auto', bypassPermissions: 'Bypass', dontAsk: "Don't ask",
};

const STATUS_ORDER = { needs: 0, busy: 1, turn: 2, idle: 3 };

// The last exchange under the title, as a chat: your message, and below it Claude's line, each with its label.
// While Claude works, the line shows the step it's on and the turn's time so far, with its label fading in and
// out; when it needs you, what for; then its reply. Both lines stay from one turn to the next, so every change is
// text replaced in place (morph) and nothing moves. A step's name stays up after the step finishes, as in Claude's
// own progress row, and a step shows once it starts running (a hook can't see it sooner). The chat shows while
// Claude works or needs you, and for a reply while "Your turn" lasts (dimmer once read).
function chatHTML(s, kind, now) {
  const replied = s.lastReplyAt || 0;
  const recentReply = s.lastReply && replied > (s.lastPromptAt || 0) && now - replied < YOUR_TURN_MS;
  if (kind === 'idle' && !recentReply && !s.compacting) return '';
  const you = s.lastPrompt
    ? `<div class="you"><span class="who">You</span><span class="what">${esc(s.lastPrompt)}</span></div>` : '';
  let claude = '';
  if (kind === 'busy' || s.compacting) {  // working, or compacting at a word from the panel
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

// A ring filling up with the context in use. Neutral below 60%, amber from 60% (filling up), red-orange from 85%
// (near auto-compact: start fresh or compact). Pointed at, it widens into a Compact button that is the same gauge
// (its fill is the context in use); a click opens the Compact card (compactHTML). It's drawn open while pointed at
// or while its card is up, so the rebuild every second doesn't replay the widening.
function contextRing(s) {
  const a = s.agent || {}, tokens = a.tokens, model = a.model;
  if (!tokens) return '';
  const window = contextWindow(model, tokens), pct = Math.min(100, Math.round(tokens / window * 100));
  const color = pct >= 85 ? '#ff6b4a' : pct >= 60 ? '#ffc53d' : 'rgba(255, 255, 255, 0.55)';
  const r = 5, length = 2 * Math.PI * r, left = Math.max(0, compactLimit(a) - tokens);
  const open = state.hoverCtx === s.sessionId || state.compactOpen[s.sessionId] ? ' open' : '';
  const title = `${pct}% · ${kTokens(tokens)} of ${kTokens(window)} tokens in context`
    + ` · ${kTokens(left)} left before auto-compact`;
  return `<span class="ctx${open}" data-ctx="${esc(s.sessionId)}" title="${title}"`
    + ` style="color:${color};--fill:${pct}%">
      <svg width="12" height="12" viewBox="0 0 12 12">`
    + `<circle cx="6" cy="6" r="${r}" fill="none" stroke="rgba(255,255,255,.14)" stroke-width="1.6"/>
      <circle cx="6" cy="6" r="${r}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round"
              stroke-dasharray="${(length * pct / 100).toFixed(2)} ${length.toFixed(2)}"/></svg>`
    + '<span class="ctx-label">Compact</span></span>';
}

// The details, on two lines: where the session runs (Desktop or Terminal; its project, unless grouped by
// project; branch; worktree) and how its agent is set up, with its context ring. A session outside git,
// grouped by project, has nothing to say on the first line, so its Desktop/Terminal icon heads the second.
function metaHTML(s, kind) {
  const proof = proofHTML(s, kind);
  const g = s.git, a = s.agent || {};
  const branch = g && (g.branch || 'detached @' + g.detached);
  const where = [];
  if (state.groupBy !== 'project') where.push(`<span class="proj">${esc(projectOf(s).name)}</span>`);
  if (g) where.push(`<span class="branch">${BRANCH_ICON}${esc(branch)}</span>`);
  if (g?.worktree) where.push(`<span class="wt">worktree</span>`);
  const tip = [s.cwd, g && `branch ${branch}`, g?.worktree && `worktree ${g.worktree} of ${g.worktreeOf}`,
               s.entrypoint === 'claude-desktop' ? 'Claude Desktop' : 'Terminal'].filter(Boolean).join('\n');
  const icon = s.entrypoint === 'claude-desktop' ? DESKTOP_ICON : TERMINAL_ICON;
  const mode = MODE_NAMES[a.mode] || a.mode;
  const inClaude = s.entrypoint === 'claude-desktop' ? ' in Claude' : '';
  const pick = (field, label, cls = '') =>
    `<span class="pick${cls}" data-pick="${field}" title="Change ${field}${inClaude}">${label}</span>`;
  const agent = [modelName(a.model) && pick('model', esc(modelName(a.model))),
                 a.effort && pick('effort', esc(a.effort)),
                 mode && pick('mode', esc(mode), a.mode === 'bypassPermissions' ? ' bypass' : '')]
    .filter(Boolean).join(' · ');
  const setup = (agent ? `<span class="agent">${agent}</span>` : '') + contextRing(s);
  if (!where.length && !proof) return `<div class="setup" title="${esc(tip)}">${icon}${setup}</div>`;
  return `<div class="where" title="${esc(tip)}">${icon}${where.join('<span class="sep">·</span>')}${proof}</div>`
    + (setup ? `<div class="setup">${setup}</div>` : '');
}

// Open PRs this session created or worked on. Hidden while GitHub is still being asked, dimmed when
// their state couldn't be checked (UNKNOWN); merged and closed ones are left out.
function prsHTML(s) {
  const open = (s.prs || []).filter((p) => p.state === 'OPEN' || p.state === 'UNKNOWN');
  if (!open.length) return '';
  const rows = open.slice(0, MAX_PRS).map((p) => {
    const cls = ['pr', p.isDraft ? 'draft' : '', p.state === 'UNKNOWN' ? 'pending' : ''].join(' ');
    return `<div class="${cls}" data-url="${esc(p.url)}">${PR_ICON}<span class="num">#${esc(p.number)}</span>`
      + `<span class="pt">${esc(p.title || p.repo)}</span></div>`;
  });
  if (open.length > MAX_PRS) rows.push(`<div class="pr more">+${open.length - MAX_PRS} more open</div>`);
  return `<div class="prs">${rows.join('')}</div>`;
}

// What the work has been through, beside its state (workProof in whose-move.js).
function proofHTML(s, kind) {
  const proof = workProof(s, kind);
  return proof ? `<span class="proof" title="${esc(proof.tip)}">${esc(proof.text)}</span>` : '';
}

// An idle row's current action (currentAction), as a coloured tag. A working row shows what it's doing on Claude's
// line instead (chatHTML), and a row that needs you shows what for.
function stageHTML(s, kind) {
  if (kind === 'busy' || kind === 'needs') return '';
  const action = currentAction(s);
  return action ? `<span class="stage o-${action[1]}">${esc(action[0])}</span>` : '';
}

function rowHTML(s, kind, now) {
  // How long ago, on the title line; not while it works (or compacts), when Claude's line has the time.
  const since = kind === 'needs' ? s.statusUpdatedAt || 0 : lastActive(s);
  const time = ago(now - since);
  const closed = s.status === 'closed' ? ' closed' : '';
  const focused = s.focused ? ' focused' : '';
  const tip = s.focused ? 'Open in Claude now' : closed ? 'Not running: click to open in Claude' : '';
  return `<div class="row ${kind}${closed}${focused}" data-id="${esc(s.sessionId)}" ${tip ? `title="${tip}"` : ''}>
      <span class="dot" style="${kind === 'needs' ? phase(1600) : kind === 'busy' ? phase(1400) : ''}"></span>
      <div class="main">
        <div class="line1">
          <span class="name">${esc(s.name || base(s.cwd))}</span>
          ${stageHTML(s, kind)}
          ${kind === 'busy' || s.compacting ? '' : `<span class="time">${time}</span>`}
        </div>
        ${chatHTML(s, kind, now)}
        ${s.ask && !folded(s.ask.id) ? askHTML(s.ask) : !s.ask && state.compactOpen[s.sessionId] ? compactHTML(s) : ''}
        ${metaHTML(s, kind)}
        ${prsHTML(s)}
      </div>
    </div>`;
}

// A group's rows in a body that folds to nothing. The conversation open in Claude, and any session that needs you
// (a request or question waiting), stay in view: while the group is folded, a copy of their row is pinned below
// it. The original stays in the body, in place, so opening the group slides to its true height.
function groupBody(rows, closed) {
  const pinned = closed ? rows.filter((r) => r.s.focused || r.kind === 'needs') : [];
  return `<div class="prows${closed ? ' closed' : ''}">${rows.map((r) => r.html).join('')}</div>`
    + (pinned.length ? `<div class="pinned">${pinned.map((r) => r.html).join('')}</div>` : '');
}

// Projects ordered by most recent activity; inside each, sessions by status, then recency (sortKey).
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
            ${p.scratch ? '' : `<span class="add" data-folder="${esc(p.key)}"`
                + ` title="New session in ${esc(p.name)} (⌥: in terminal)">${PLUS_ICON}</span>`}
          </div>`;
      return head + groupBody(rows.map(({ s, kind }) => ({ s, kind, html: rowHTML(s, kind, now) })), closed);
    })
    .join('');
}

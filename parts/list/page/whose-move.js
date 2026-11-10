// Whose move it is: what each session is, how the list sorts, and which session speaks for each checkout.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// A reply you've read waits this long for something more, from you or from Claude: a day with nothing, and its
// session is idle. One you haven't read waits for you however long it takes.
const IDLE_AFTER_MS = 24 * 60 * 60 * 1000;
// How long you're away from a session before you've moved on from it: until then, being on it again reads what it
// sends (stillOnIt).
const MOVED_ON_MS = 10 * 60 * 1000;
// Statuses that mean Claude is waiting on you. The app's twin is AgentAsksYou (parts/work/app/Work.m): a status counted
// here is counted there.
const NEEDS_STATUSES = new Set(['waiting', 'needs_input', 'requires_action', 'blocked']);

// What a session is now: needs (a request or question waits for you), busy (working), background (its turn has ended
// and it takes your messages, but agents it started still work in the background: not your move until they're done,
// when Claude replies again), turn (a reply you haven't read), seen (a reply you've read) or idle (no reply, or one
// you've read with nothing since for a day: no message, and you not on it while it was yours). `view` holds when you
// were last on each session while it was yours, as the page keeps it (`seen`: stillOnIt), the time before which every
// reply counts as read (`readBefore`), and each reply to you not read yet (`toRead`: stillToRead). Claude's registry
// time isn't used: it also moves when a process merely starts.
function classify(s, now, view) {
  if (s.ask || NEEDS_STATUSES.has(s.status)) return 'needs';
  if (s.status === 'busy') return 'busy';
  if (backgroundAtWork(s)) return 'background';
  if (!s.lastReplyAt) return 'idle';
  if (!isRead(s, view)) return 'turn';
  return now - Math.max(lastActive(s), view.seen[s.sessionId] || 0) < IDLE_AFTER_MS ? 'seen' : 'idle';
}

// How many jobs a session runs in the background that hold its work (`holds`: its agents, say, which can change its
// files), which make it 'background' (classify). A shell command it left running (a dev server) isn't counted here:
// one may run all day, so it never keeps a reply from being your move.
function backgroundAtWork(s) {
  return (s.background || []).filter((job) => job.holds).length;
}

// How many jobs a session runs in the background, whatever their kind, shell commands left running among them, and
// whatever the session is now.
function backgroundRunning(s) {
  return (s.background || []).length;
}

// Whether you've read Claude's last reply: you've been on its session since, as the page keeps it (`seen`, which
// opening it here counts for) or as the app and Claude say (onItAt). A reply from before `readBefore` counts as read
// too: that's set once, a day (IDLE_AFTER_MS) before the page first kept which replies you'd read, since until then
// which you'd read wasn't always kept. A reply that went to another session, not to you, as a module says
// (repliedElsewhere), was never yours to read; but one to you that you hadn't read when it came stays to read
// (`toRead`) until you've read it. A conversation a module says is wholly not yours (core.notYoursToRead: one that has
// ended in a team member's folder, say) has nothing to read, kept or not: only a module says so, never by default.
function isRead(s, view) {
  const read = readUpTo(s, view);
  if (core.notYoursToRead.some((notYours) => notYours(s))) return true;
  if ((view.toRead?.[s.sessionId] || 0) > read) return false;
  return (s.lastReplyAt || 0) <= read || repliedElsewhere(s);
}
function readUpTo(s, view) {
  return Math.max(view.seen[s.sessionId] || 0, onItAt(s), view.readBefore || 0);
}

// Whether the session's last reply went to another session rather than to you, as a module says
// (core.repliesElsewhere): it then never waits on you.
function repliedElsewhere(s) {
  return core.repliesElsewhere.some((elsewhere) => elsewhere(s));
}

// What the page keeps of a session's replies to you not read yet (`kept`, the time of the last one, or 0), now: its
// reply's time while that's to you and not read, and it's kept, whatever goes elsewhere since, until you've read it.
// But the reply kept that's known now to have gone elsewhere itself, as its session's last reply, was never yours: it
// was kept before that was known (a module's part of the row not in yet). While a module says a conversation is
// wholly not yours, what's kept stays as it is, nothing added and nothing dropped: isRead reads it meanwhile, and should
// the conversation come back as yours (resumed), a reply to you kept unread still waits on you.
function stillToRead(s, kept, view) {
  if (core.notYoursToRead.some((notYours) => notYours(s))) return kept;
  const read = readUpTo(s, view);
  if ((s.lastReplyAt || 0) > read && !repliedElsewhere(s)) return Math.max(kept, s.lastReplyAt);
  if (kept === s.lastReplyAt && repliedElsewhere(s)) return 0;
  return kept > read ? kept : 0;
}

// When the app and Claude last saw you on a session: on it in Claude, Ghostty or iTerm2, or writing to it (not another
// session writing to it), as the app works it out for the row (`onItAt`, Row.m), which Compact at Breaks goes by too.
function onItAt(s) {
  return s.onItAt || 0;
}

// When you were last on a session, as the page keeps it (`kept`), now that you're on it at `at` (opened here, or as
// onItAt says): it follows you while the session is yours, with something new since you were last on it (a reply, or
// your message, after `readBefore`), or you on it in the last ten minutes. Once you've moved on, it stays as it was,
// so looking at that session again doesn't read a reply it sends later: only being on it once that reply has come does.
function stillOnIt(s, kept, at, now, readBefore) {
  const newest = Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0);
  const yours = Math.max(kept, readBefore || 0) < newest || now - kept < MOVED_ON_MS;
  return yours ? Math.max(kept, at) : kept;
}

// Whether a session waits on you: a request or question, or a reply you haven't read. Its dot says so, the menu bar
// counts it, and the folded panel names it.
function waitsOnYou(kind) {
  return kind === 'needs' || kind === 'turn';
}

// When a session became your turn: when its request came (the hook's time, else when Claude's status changed), or
// when Claude replied.
function turnSince(s, kind) {
  return kind === 'needs' ? s.ask?.at || s.statusUpdatedAt || 0 : s.lastReplyAt || 0;
}

// The list's one view, for everyone: the groups the modules put on top (core.topGroups: a team's chief, its groups and
// its team), each module given what the one before left, then every project, A to Z, with the rows left for them.
// Inside each group the rows keep the order they were placed in (placeRows), newest message first: nothing is lifted,
// as what waits on you says so on its row. A row a module leaves in neither of its lists isn't shown.
function listGroups(placed) {
  const groups = [];
  let rest = placed;
  for (const top of core.topGroups) {
    const given = top(rest);
    if (!given) continue;
    groups.push(...given.groups);
    rest = given.rest;
  }
  return [...groups, ...projectGroups(rest)];
}

// Projects in the order of their names, A to Z, so a project never moves as its conversations do; inside each, its rows
// as they're placed, newest message first.
function projectGroups(placed) {
  const projects = new Map();
  for (const p of placed) {
    const of = projectOf(p.s);
    if (!projects.has(of.key)) projects.set(of.key, { ...of, project: true, rows: [] });
    projects.get(of.key).rows.push(p);
  }
  const byName = (a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true })
    || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
  return [...projects.values()].sort(byName);
}

// The rows in the order the list places them, each { s, kind, latest, quiet, held }, as a chat app lists its
// conversations, which every group in the list keeps (listGroups): newest message first (movedAt). A message coming in,
// Claude's reply or a request, takes its row to the top, and so does yours; while Claude works it stays where your
// message put it. Only the idle ones (`quiet`: a reply you've read with nothing since for a day, or none at all) go
// below the rest, newest first there too, so a reply you haven't read never sits under one you were done with a day
// ago. A row you've pressed (`held(id)`) keeps all it was last shown with (`before`), whatever it has become, so it
// stays where you saw it, until you've moved on from the panel.
function placeRows(rows, before, held) {
  const byId = (a, b) => (a.s.sessionId < b.s.sessionId ? -1 : a.s.sessionId > b.s.sessionId ? 1 : 0);
  return rows.map(({ s, kind }) => {
    const was = before[s.sessionId];
    if (was && held(s.sessionId)) return { ...was, s, kind, held: true };
    return { s, kind, latest: movedAt(s, kind), quiet: kind === 'idle' };
  }).sort((a, b) => a.quiet - b.quiet || b.latest - a.latest || byId(a, b));
}

// When the conversation last moved: your message, Claude's reply, or the newest message in its transcript.
// A change of status or settings doesn't count, so changing a session's model doesn't send it to the top.
function lastActive(s) {
  const moved = Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0, s.messageAt || 0);
  return moved || s.activityAt || s.statusUpdatedAt || 0;
}

// When a session's last message came, which is where its row sorts: a working one's when its turn began, your message,
// not its latest step, so its steps never move it; one waiting on you when its request came, or its reply; the rest
// when their conversation last moved. At work with no message of yours since its reply (compacting, say), nothing has
// been said, so it stays where its last message put it; only a session with no messages recorded goes by when it
// started working.
function movedAt(s, kind) {
  if (kind === 'busy') {
    return s.lastPromptAt > (s.lastReplyAt || 0) ? s.lastPromptAt : s.lastReplyAt || s.statusUpdatedAt || 0;
  }
  return Math.max(lastActive(s), kind === 'needs' ? turnSince(s, kind) : 0);
}

// Claude's status and your message (or its reply) arrive separately, usually a tenth of a second apart. For up
// to 3 seconds a new turn is shown as it was until both agree, so your message appears first and the working
// line follows it; and a message of yours that has just come in is the start of a turn, though the status still says
// idle, so its row shows it at work at once. A status change in the middle of a turn shows as it is.
function steady(s, now) {
  if (!s.lastPromptAt) return s;
  const replied = (s.lastReplyAt || 0) >= s.lastPromptAt;
  if (s.status === 'idle' && !replied && now - s.lastPromptAt < 3000) return { ...s, status: 'busy' };
  if (now - (s.statusUpdatedAt || 0) > 3000) return s;
  if (s.status === 'busy' && s.lastPromptAt < s.statusUpdatedAt - 2000 && replied) return { ...s, status: 'idle' };
  if (s.status === 'idle' && !replied) return { ...s, status: 'busy' };
  return s;
}

// Who speaks for a checkout: the row that shows its numbers and next steps.

// When a session last edited files in a checkout (`root`), or null if its edits haven't landed there: the hook notes
// the checkout its edits last landed in (workRoot), and the agent's module when (`workEditedAt`: when the hook noted,
// or, from an older hook that doesn't note when, the end of its last turn that changed something, or else the start of
// time), which the commands module's CompactTime goes by too.
function editedAt(s, root) {
  if (!s.workRoot || s.workRoot !== root) return null;
  return s.workEditedAt || 0;
}

// The session that speaks for each checkout (or folder, outside git): of the sessions that run there, the one that
// edited files there last, running or not, whatever it has done since. A session speaks only for the checkout it runs
// in (the app sends workGit only for one that runs outside any), so what it edits elsewhere never brings that
// checkout's steps to its row. Only its row shows the numbers, the steps (and Deploy) for the work there, so several
// chats in one checkout don't all offer the same Commit. When no session there has edited it, the session last active there speaks
// for it, one still running before a closed one, so work left in a checkout always shows somewhere. Returns their ids.
function checkoutOwners(sessions) {
  const editor = {}, fallback = {};
  const running = (s) => s.status !== 'closed';
  for (const s of sessions) {
    const root = (s.workGit || s.git)?.root || s.cwd;
    if (!root) continue;
    const at = editedAt(s, root), best = editor[root];
    if (at !== null && (!best || at > best.at || (at === best.at && lastActive(s) > lastActive(best.s)))) {
      editor[root] = { s, at };
    }
    const f = fallback[root];
    if (!f || running(s) > running(f) || (running(s) === running(f) && lastActive(s) > lastActive(f))) {
      fallback[root] = s;
    }
  }
  return new Set(Object.keys(fallback).map((root) => (editor[root]?.s || fallback[root]).sessionId));
}

// The commits a checkout has that GitHub doesn't: past the upstream when there is one, else past the base branch
// (GitHub's copy of it, where there is one), as the app lists them (FetchChangeCounts in app/shared/Git.m: keep the two in
// step). None without a remote, where a commit is finished.
function unpushedCommits(c) {
  if (!c || !(c.remotes > 0)) return 0;
  return (c.upstream ? c.ahead : c.aheadOfBase) || 0;
}

// A session's project: its repo (a worktree counts toward the repo it came from), or outside git, its folder.
// `key` is that folder, where ＋ starts a new session. An app may group some of its sessions in a project of its own
// (core.hosts' project: Claude Desktop's scratch conversations share one group).
function projectOf(s) {
  const g = s.git;
  if (g?.worktree && g.mainRoot) return { key: g.mainRoot, name: g.worktreeOf };
  const own = core.hosts.map((host) => host.project?.(s)).find(Boolean);
  if (own) return own;
  const root = g?.root || s.cwd;
  return { key: root, name: base(root) };
}

// Times.

// How long is left, in whole minutes: "4m", or "<1m" under one.
const minutesLeft = (ms) => (ms < 60000 ? '<1m' : `${Math.floor(ms / 60000)}m`);

// How long ago: "now", "45s", "5m", "3h", "2d".
function ago(ms) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 10) return 'now';
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s / 60) + 'm';
  if (s < 86400) return Math.floor(s / 3600) + 'h';
  return Math.floor(s / 86400) + 'd';
}

// How long the current step has been running: "12s", "1m 16s", "1h 3m".
function elapsed(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return s + 's';
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

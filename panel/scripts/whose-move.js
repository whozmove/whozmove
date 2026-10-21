// Whose move it is: which section each session goes in, how sessions sort, and which session speaks for each
// checkout.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// A reply you've read waits this long for something more, from you or from Claude: an hour with nothing, and its
// session goes to Idle. One you haven't read waits for you however long it takes.
const IDLE_AFTER_MS = 60 * 60 * 1000;
// How long you're away from a session before you've moved on from it: a reply you've read stays in Your turn while
// you're on its session, and until you've been away from it this long.
const MOVED_ON_MS = 10 * 60 * 1000;
// Statuses that mean Claude is waiting on you.
const NEEDS_STATUSES = new Set(['waiting', 'needs_input', 'requires_action', 'blocked']);

// What a session is now: needs (a request or question waits for you), busy (working), turn (a reply you haven't
// read), seen (a reply you've read) or idle (no reply, or one you've read with nothing since for an hour: no message,
// and you not on it while it was yours). `view` holds when you were last on each session while it was yours, as the
// page keeps it (`seen`: stillOnIt), and the time before which every reply counts as read (`readBefore`). Claude's
// registry time isn't used: it also moves when a process merely starts.
function classify(s, now, view) {
  if (s.ask || NEEDS_STATUSES.has(s.status)) return 'needs';
  if (s.status === 'busy') return 'busy';
  if (!s.lastReplyAt) return 'idle';
  if (!isRead(s, view)) return 'turn';
  return now - Math.max(lastActive(s), view.seen[s.sessionId] || 0) < IDLE_AFTER_MS ? 'seen' : 'idle';
}

// Whether you've read Claude's last reply: you've been on its session since, as the page keeps it (`seen`, which
// opening it here counts for) or as the app and Claude say (onItAt). A reply from before `readBefore` counts as read
// too: that's set once, an hour before the page first kept the replies you hadn't read in Your turn, since until then
// a reply went to Idle after an hour, read or not, and which you'd read wasn't always kept.
function isRead(s, view) {
  const read = Math.max(view.seen[s.sessionId] || 0, onItAt(s), view.readBefore || 0);
  return (s.lastReplyAt || 0) <= read;
}

// When the app and Claude last saw you on a session: on it in Claude, Ghostty or iTerm2 (the app's `seenAt`, and Claude
// Desktop's own `lastFocusedAt`), or writing to it.
function onItAt(s) {
  return Math.max(s.seenAt || 0, s.lastFocusedAt || 0, s.lastPromptAt || 0);
}

// When you were last on a session, as the page keeps it (`kept`), now that you're on it at `at` (opened here, or as
// onItAt says): it follows you while the session is yours, with something new since you were last on it (a reply, or
// your message, after `readBefore`), or you on it in the last ten minutes. Once you've moved on, it stays as it was,
// so looking at that session again doesn't bring its row back into Your turn: only something new does.
function stillOnIt(s, kept, at, now, readBefore) {
  const newest = Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0);
  const yours = Math.max(kept, readBefore || 0) < newest || now - kept < MOVED_ON_MS;
  return yours ? Math.max(kept, at) : kept;
}

// Where each kind of session is shown, top to bottom: a request and a reply you haven't read share Your turn, then
// Working, Seen (the replies you've read, once you've moved on from them: sectionOf) and Idle.
const SECTIONS = ['turn', 'busy', 'seen', 'idle'];
const SECTION_OF = { needs: 'turn', turn: 'turn', busy: 'busy', seen: 'seen', idle: 'idle' };

// Where a session is shown: as its kind says, but a reply you've read stays in Your turn until you've moved on from it,
// so it doesn't leave as you read it: while you're on its session, and for ten minutes after you were last on it, as
// the page keeps it (`view.seen`: stillOnIt). Then it goes to Seen.
function sectionOf(s, kind, now, view) {
  return kind === 'seen' && now - (view.seen[s.sessionId] || 0) < MOVED_ON_MS ? 'turn' : SECTION_OF[kind];
}

// When a session became your turn: when its request came (the hook's time, else when Claude's status changed), or
// when Claude replied.
function turnSince(s, kind) {
  return kind === 'needs' ? s.ask?.at || s.statusUpdatedAt || 0 : s.lastReplyAt || 0;
}

// Where a session sorts within Working, Seen or Idle, smallest first: Working by when each turn began, newest first, so
// two at work don't trade places with every step; Seen by the reply, newest first; Idle by when the conversation last
// moved.
function placeKey(s, kind, section) {
  if (section === 'busy') return -sortKey(s, 'busy');
  if (section === 'seen') return -(s.lastReplyAt || 0);
  return -lastActive(s);
}

// The rows in the order they're shown, each { s, kind, section, key, tie, latest, held }: by section (sectionOf, with
// `view` as classify has it), then by key, then by tie. Your turn is first come, first served: a row that comes into it
// joins its end (its key is `now`, those that come at once in the order they became your turn, their tie), and keeps
// that place while it's there, so nothing above it moves. Working's, Seen's and Idle's keys don't move while a row
// stays in its section either, so rows keep their order. A row you've pressed (`held(id)`) keeps all it was last shown
// with (`before`), whatever it has become, so it stays where you saw it, and so does its project (`latest`, how recent
// it is: sortKey).
function placeRows(rows, before, held, now, view) {
  const byId = (a, b) => (a.s.sessionId < b.s.sessionId ? -1 : a.s.sessionId > b.s.sessionId ? 1 : 0);
  return rows.map(({ s, kind }) => {
    const was = before[s.sessionId];
    if (was && held(s.sessionId)) return { ...was, s, kind, held: true };
    const section = sectionOf(s, kind, now, view), latest = sortKey(s, kind);
    if (section !== 'turn') return { s, kind, section, key: placeKey(s, kind, section), tie: 0, latest };
    const stays = was?.section === 'turn';
    return { s, kind, section, key: stays ? was.key : now, tie: stays ? was.tie : turnSince(s, kind), latest };
  }).sort((a, b) => SECTIONS.indexOf(a.section) - SECTIONS.indexOf(b.section) || a.key - b.key || a.tie - b.tie
    || byId(a, b));
}

// When the conversation last moved: your message, Claude's reply, or the newest message in its transcript.
// A change of status or settings doesn't count, so changing a session's model doesn't send it to the top.
function lastActive(s) {
  const moved = Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0, s.messageAt || 0);
  return moved || s.activityAt || s.statusUpdatedAt || 0;
}

// How recent a session is: a working one by when its turn began, not by its latest step, so two working at once
// don't swap places with every step; the rest by when their conversation last moved. Working sorts by it, and so do
// the projects.
function sortKey(s, kind) {
  if (kind !== 'busy') return lastActive(s);
  return s.lastPromptAt > (s.lastReplyAt || 0) ? s.lastPromptAt : s.statusUpdatedAt || 0;
}

// Claude's status and your message (or its reply) arrive separately, usually a tenth of a second apart. For up
// to 3 seconds a new turn is shown as it was until both agree, so your message appears first and the working
// line follows it; and a message of yours that has just come in is the start of a turn, though the status still says
// idle, so its row goes straight to Working. A status change in the middle of a turn shows as it is.
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

// Outcomes of a turn that changed or shipped something.
const CHANGED = ['Implemented', 'Documented', 'Built', 'Validated', 'Tested', 'Committed', 'Pushed', 'PR raised',
                 'Merged', 'On staging', 'Deployed'];

// When a session last edited files in a checkout (`root`), or null if its edits haven't landed there: the hook notes
// the checkout its edits last landed in (workRoot) and when (editedAt). An older hook doesn't note when; then the end
// of its last turn that changed something stands in, or else the start of time.
function editedAt(s, root) {
  if (!s.workRoot || s.workRoot !== root) return null;
  return s.editedAt || (CHANGED.includes(s.outcome) ? s.outcomeAt || 0 : 0);
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

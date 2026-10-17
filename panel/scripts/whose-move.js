// Whose move it is: which section each session goes in, how sessions sort, what an idle session's work is waiting
// on, with the label and colour the panel gives it, and which session speaks for each checkout.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// A reply stays under "Your turn" this long, unless you've read it.
const YOUR_TURN_MS = 30 * 60 * 1000;
// Grouped by activity, a session stays under "Your turn" until it has been quiet this long.
const ACTIVE_MS = 60 * 60 * 1000;
// Statuses that mean Claude is waiting on you.
const NEEDS_STATUSES = new Set(['waiting', 'needs_input', 'requires_action', 'blocked']);

// The section a session goes in: needs (a request or question waits for you), busy (working), turn (a reply
// for you) or idle. `view` is how the panel is set up: its grouping, the session you're on, and when you last
// opened each session here.
// - By status, a reply counts for half an hour, until you've read it. The session you're on keeps its place
//   after you read it, so the list doesn't move under you.
// - By activity, a session counts while its conversation moved in the last hour, read or not.
// Claude's registry time isn't used: it also moves when a process merely starts.
function classify(s, now, view) {
  if (s.ask || NEEDS_STATUSES.has(s.status)) return 'needs';
  if (s.status === 'busy') return 'busy';
  const replied = s.lastReplyAt || 0;
  if (view.groupBy === 'activity') return replied && now - lastActive(s) < ACTIVE_MS ? 'turn' : 'idle';
  if (replied && now - replied < YOUR_TURN_MS && (!isRead(s, view.seen) || s.sessionId === view.current)) return 'turn';
  return 'idle';
}

// Whether you've read Claude's last reply: you opened the session here since (`seen`), or had it open in
// Claude Desktop.
function isRead(s, seen) {
  return (s.lastReplyAt || 0) <= Math.max(seen[s.sessionId] || 0, s.lastFocusedAt || 0);
}

// When the conversation last moved: your message, Claude's reply, or the newest message in its transcript.
// A change of status or settings doesn't count, so changing a session's model doesn't send it to the top.
function lastActive(s) {
  const moved = Math.max(s.lastReplyAt || 0, s.lastPromptAt || 0, s.messageAt || 0);
  return moved || s.activityAt || s.statusUpdatedAt || 0;
}

// Where a row sorts. A working session goes by when its turn began, not by its latest step, so two working at
// once don't swap places with every step. The rest go by when their conversation last moved.
function sortKey(s, kind) {
  if (kind !== 'busy') return lastActive(s);
  return s.lastPromptAt > (s.lastReplyAt || 0) ? s.lastPromptAt : s.statusUpdatedAt || 0;
}

// Claude's status and your message (or its reply) arrive separately, usually a tenth of a second apart. For up
// to 3 seconds a new turn is shown as it was until both agree, so your message appears first and the working
// line follows it. A status change in the middle of a turn shows as it is.
function steady(s, now) {
  if (!s.lastPromptAt || now - (s.statusUpdatedAt || 0) > 3000) return s;
  const replied = (s.lastReplyAt || 0) >= s.lastPromptAt;
  if (s.status === 'busy' && s.lastPromptAt < s.statusUpdatedAt - 2000 && replied) return { ...s, status: 'idle' };
  if (s.status === 'idle' && !replied) return { ...s, status: 'busy' };
  return s;
}

// What an idle session's work is waiting on.

// Outcomes of a turn that changed or shipped something.
const CHANGED = ['Implemented', 'Documented', 'Built', 'Validated', 'Tested', 'Committed', 'Pushed', 'PR raised',
                 'Merged', 'On staging', 'Deployed'];

// A checkout's state belongs to a session only when the work there is its own: it changed or shipped
// something, has PRs, or runs in its own worktree. Otherwise a chat that just sits in a busy checkout, or one
// that changed something long ago and has only looked things up since, would take on that checkout's state.
function ownsCheckout(s) {
  return !!(s.git?.worktree || (s.prs || []).length || CHANGED.includes(s.outcome));
}

// Labels too vague to keep when Claude says it's waiting on you.
const VAGUE = ['Done', 'Exploring', 'Planning'];

// The current action as [label, kind]. When Claude ended its turn blocked on you, a definite state such as
// "Ready to commit" stays, in your colour; only a vague one turns into "Waiting on you".
function currentAction(s) {
  const action = workState(s);
  if (s.summaryStatus !== 'blocked') return action;
  if (!action || VAGUE.includes(action[0])) return ['Waiting on you', 'yours'];
  return [action[0], action[1] === 'urgent' ? 'urgent' : 'yours'];
}

// Where the work stands, as [label, kind], most pressing first: the checkout's live state (changes, unpushed
// commits, the branch's PR), then how far the last turn took the work, then Claude Desktop's own verdict.
// The kind picks the colour: urgent, yours, dev, wait, done or plain.
function workState(s) {
  const c = ownsCheckout(s) ? s.checkout : null, pr = c?.pr, outcome = s.outcome;
  const checked = ['Built', 'Validated', 'Tested'].includes(outcome);
  if (c?.changes > 0) return checked ? ['Ready to commit', 'yours'] : ['In development', 'dev'];
  if (c?.ahead > 0) return ['Committed', 'yours'];  // committed, not pushed yet
  if (outcome === 'Deployed') return ['Live in prod', 'done'];
  if (outcome === 'On staging') return ['On staging', 'wait'];
  if (outcome === 'Merged') return ['Merged', 'done'];  // GitHub's status can lag behind by minutes
  // Open PRs, the session's own and its branch's: the most pressing one decides.
  const open = (s.prs || []).filter((p) => p.state === 'OPEN');
  if (pr?.state === 'OPEN' && !open.some((p) => p.url === pr.url)) open.push(pr);
  const has = (test) => open.some(test);
  if (open.length) {
    if (has((p) => p.checks === 'failing')) return ['CI failing', 'urgent'];
    if (has((p) => p.review === 'CHANGES_REQUESTED')) return ['Changes requested', 'urgent'];
    if (has((p) => p.checks === 'running')) return ['CI running', 'wait'];
    if (open.every((p) => p.isDraft)) return ['Draft PR', 'yours'];
    if (open.every((p) => p.isDraft || p.review === 'APPROVED')) return ['Approved', 'yours'];
    return ['In review', 'wait'];
  }
  if (outcome === 'PR raised') return ['In review', 'wait'];  // its status isn't in yet
  // A turn that only looked things up, planned or reviewed is newer than any merge it sits on top of.
  if (outcome === 'Reviewed') return ['Review posted', 'done'];
  if (outcome === 'Researched') return ['Exploring', 'plain'];
  if (outcome === 'Planned') return ['Planning', 'plain'];
  if (pr?.state === 'MERGED' || (s.prs || []).some((p) => p.state === 'MERGED')) return ['Merged', 'done'];
  // A push needn't set up tracking (`git push origin feat`), so the turn saying it pushed is enough.
  if (outcome === 'Pushed') return ['Pushed, no PR', 'yours'];
  if (outcome === 'Committed' && c) {
    if (c.upstream) return ['Pushed, no PR', 'yours'];
    return c.remotes > 0 ? ['Committed', 'yours'] : ['Committed', 'done'];  // with no remote, nothing is left to do
  }
  if (outcome || s.summaryStatus === 'completed') return ['Done', 'plain'];
  return null;
}

// What the work has been through, shown beside a definite state: built, tested, validated, and a local code
// review's audit ("audit: 15 found", then "audit: 1 left" or "audit clean"; a skipped finding counts as left).
// It says "audit" so it never reads as a GitHub review. Returns { text, tip }, or null when there's none.
const PROOF_WORDS = { Built: 'built', Tested: 'tested', Validated: 'validated' };
function workProof(s, kind) {
  if (kind === 'busy' || kind === 'needs') return null;
  const action = currentAction(s);
  if (!action || VAGUE.includes(action[0]) || action[0] === 'Waiting on you') return null;
  const steps = Object.keys(PROOF_WORDS).filter((k) => (s.workSteps || []).includes(k)).map((k) => PROOF_WORDS[k]);
  const a = s.audit, tips = steps.map((w) => w[0].toUpperCase() + w.slice(1));
  if (a) {
    const clean = !a.found || (a.settled && !a.left);
    steps.push(clean ? 'audit clean' : a.settled ? `audit: ${a.left} left` : `audit: ${a.found} found`);
    const findings = `Code review: ${a.found} finding${a.found === 1 ? '' : 's'}`;
    tips.push(findings + (a.settled ? `, ${a.found - a.left} settled, ${a.left} left` : ''));
  }
  return steps.length ? { text: steps.join(' · '), tip: tips.join(' · ') } : null;
}

// Who speaks for a checkout: the row that shows its island.

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
// checkout's island to its row. Only its row shows the island (and Deploy) for the work there, so several chats in one
// checkout don't all offer the same Commit. When no session there has edited it, the session last active there speaks
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

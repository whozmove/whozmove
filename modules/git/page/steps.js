// The steps a row's checkout has to take, as git sees it (stepsOf): commit what isn't committed, push what's ahead of
// GitHub (or publish a branch never pushed), and open a pull request once it's all pushed; and, on the way, how the
// checkout's last code review went (reviewOf).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// The open pull request for the row's branch: the branch's own, else (off the base branch) one the session raised from
// this branch. A PR whose branch GitHub hasn't said yet counts as this branch's.
function openPR(s) {
  const c = s.checkout;
  if (c?.pr?.state === 'OPEN') return c.pr;
  const branch = (s.workGit || s.git)?.branch;
  if (branch === c?.base) return null;
  return (s.prs || []).find((p) => p.state === 'OPEN' && (!p.headRefName || p.headRefName === branch)) || null;
}

// The steps the row's checkout has to take, or null: only for the session that speaks for the checkout (`owner`), in
// git, and only while there's one to take. Shown while the agent works too: what they say doesn't wait on the agent,
// only taking them does. { commit, push, publish, pr }, each there only when it's to take:
//   commit   {staged}: files changed here, new ones included, how many of them with staged changes (a commit then
//            takes only those)
//   push     how many commits the branch is ahead of its upstream on GitHub
//   publish  how many commits a branch never pushed has: with a remote, as a commit is finished without one
//   pr       {into}: a branch pushed with nothing waiting and no pull request, as GitHub says it, into the repo's
//            default branch (`into`, the base)
// A pushed branch needs a pull request only once GitHub has said it has none (c.pr is null then; it's missing until gh
// answers, and always without gh), and only if the agent hasn't raised one since GitHub last looked.
function stepsOf(s, owner) {
  const c = s.checkout;
  if (!owner || !c || !s.git) return null;
  const files = (c.changes || 0) + (c.newFiles || 0);
  const remote = c.remotes > 0, branch = (s.workGit || s.git)?.branch;
  const unpushed = unpushedCommits(c);
  const raised = s.outcome === 'PR raised' && (s.outcomeAt || 0) > (c.prCheckedAt || 0) * 1000;
  const needsPR = remote && c.upstream && !!branch && branch !== c.base && !openPR(s)
    && (c.pr === null || c.pr?.state === 'CLOSED') && !raised && c.aheadOfBase > 0 && !unpushed;
  const steps = {};
  if (files) steps.commit = { staged: (c.filesStaged || 0) + (c.filesPartly || 0) };
  if (unpushed && c.upstream) steps.push = unpushed;
  else if (unpushed) steps.publish = unpushed;
  if (needsPR) steps.pr = { into: c.base || null };
  return Object.keys(steps).length ? steps : null;
}

// The words a step says, beside its icon as it's pointed at, and over it (its tooltip): what a press asks the agent
// to do.
function stepWords(step, steps) {
  if (step === 'commit') {
    const staged = steps.commit.staged;
    return ['Commit', staged ? `Commit what's staged (${staged} ${staged === 1 ? 'file' : 'files'})`
                             : 'Commit the changes'];
  }
  if (step === 'push') return ['Push', `Push ${steps.push} ${steps.push === 1 ? 'commit' : 'commits'} to GitHub`];
  if (step === 'publish') return ['Publish', 'Publish this branch on GitHub'];
  return ['', ''];
}

// Where a branch stands while it has commits to push or publish, as the work line's start says it when no pull request
// or code review (reviewOf) shows there, in git's words: how far it's ahead of its upstream's remote ("Ahead of
// origin"), or, never pushed, that it isn't published; and how many commits. Null when nothing waits to go, and while
// anything isn't committed, staged or not: the line has the checkout's numbers and the commit then, so its step isn't
// alone there.
function outgoingWords(c, steps) {
  const n = steps?.push || steps?.publish;
  if (!n || steps.commit) return null;
  const remote = typeof c?.upstream === 'string' && c.upstream.split('/')[0];
  return [steps.push ? `Ahead of ${remote || 'GitHub'}` : 'Not published',
          `${thousands(n)} ${n === 1 ? 'commit' : 'commits'}`];
}

// The last code review of the row's checkout, as the sessions' hooks recorded it (`audit`): a review reports its
// findings through Claude Code's ReportFindings tool, and reports them again, each with what became of it, once they've
// been seen to. It's the newest among the row's session and the others in its checkout, run on the branch the checkout
// is on now (one recorded before the hook noted the branch counts on any). Null with none, and once it no longer speaks
// for the work there: one with nothing left to fix, once anything there has been edited since (what it passed has
// changed); any other, once a commit came since it last reported and an edit since that commit (new work). An edit
// counts from any session whose edits landed there, wherever it runs. Otherwise {found, left, settled, changed, by}:
// `changed` when the checkout was edited after the review last reported (its fixes come before its second report), `by`
// the name of the session it ran in, when that isn't the row's own.
function reviewOf(s, sessions) {
  const g = s.workGit || s.git, root = g?.root;
  if (!root) return null;
  const all = [s, ...(sessions || []).filter((x) => x.sessionId !== s.sessionId)];
  const branch = g.branch || g.detached;
  const ran = all.filter((x) => (x.workGit || x.git)?.root === root && x.audit?.at
                                && (!x.audit.branch || x.audit.branch === branch))
    .sort((a, b) => b.audit.at - a.audit.at)[0];
  if (!ran) return null;
  const audit = ran.audit;
  const edited = Math.max(0, ...all.map((x) => editedAt(x, root) || 0));
  const committed = (s.checkout?.headAt || 0) * 1000;
  const clean = !audit.found || (audit.settled && !audit.left);
  if (edited > audit.at && (clean || (committed > audit.at && edited > committed))) return null;
  return { found: audit.found || 0, left: audit.left || 0, settled: !!audit.settled, changed: edited > audit.at,
           by: ran === s ? null : ran.name || base(ran.cwd) };
}

// How the review went (reviewOf), as the work line's start says it, and in full words over it (its tooltip), which
// names the session it ran in when that isn't the row's own: [word, what's left, tip, done], `done` when nothing it
// found is left to fix, which the line marks with a tick. Until the review reports again, everything it found is still
// to fix; after, only what it didn't settle (a finding fixed, or found to need no change, is settled; one skipped is
// left).
function reviewWords(review) {
  const { found, left } = review;
  const problems = `${thousands(found)} ${found === 1 ? 'problem' : 'problems'}`;
  const a = review.by ? `A code review in ${review.by}` : 'A code review';
  if (review.changed) {
    return ['Changed since the review', '',
            `Files were edited after ${review.by ? `the code review in ${review.by}` : 'the last code review'}`, false];
  }
  if (!found) return ['Reviewed', 'nothing to fix', `${a} found nothing to fix`, true];
  if (!review.settled) return ['Reviewed', `${thousands(found)} to fix`, `${a} found ${problems}`, false];
  if (left) return ['Reviewed', `${thousands(left)} left`,
                    `${a} found ${problems}, and ${thousands(left)} ${left === 1 ? 'is' : 'are'} still to fix`, false];
  return ['Reviewed', 'all fixed', `${a} found ${problems}, and none is left to fix`, true];
}

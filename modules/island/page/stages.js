// The island's stages: where the work in a row's checkout stands, from left to right (stagesOf), and how their counts
// are written.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// "1 file", "3 files".
function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}

// A count as the island writes it, short enough for a 16px capsule: whole below 1,000, then "1.2k", "12k", "1.2M".
function compact(n) {
  const short = (x, unit) => (x < 10 ? x.toFixed(1).replace(/\.0$/, '') : String(Math.round(x))) + unit;
  if (n < 1000) return String(n);
  return n < 999500 ? short(n / 1000, 'k') : short(n / 1e6, 'M');
}

// "3 files", "1.2k files".
function counted(n, one, many) {
  return n < 1000 ? plural(n, one, many) : `${compact(n)} ${many}`;
}

// The open pull request for the row's branch: the branch's own, else (off the base branch) one the session raised from
// this branch. A PR whose branch GitHub hasn't said yet counts as this branch's.
function openPR(s) {
  const c = s.checkout;
  if (c?.pr?.state === 'OPEN') return c.pr;
  const branch = (s.workGit || s.git)?.branch;
  if (branch === c?.base) return null;
  return (s.prs || []).find((p) => p.state === 'OPEN' && (!p.headRefName || p.headRefName === branch)) || null;
}

// The row's island, the stages its checkout's work is at from left to right, or null: only for the session that
// speaks for the checkout (`owner`), in git, and only while something is in flight (files changed, something in the
// extra stage, commits not on GitHub, or a pushed branch with no pull request). Shown while the agent works too:
// what it says doesn't wait on the agent, only what its menus ask does. Each stage is { stage, text, tip, count,
// step, pr, move, parts }:
//   files    files changed here, new ones included, or, while the extra stage holds something, as many as it says are
//            outside it (its `edits`);
//            from git, also how they split (`parts`): staged (all their changes), partly (staged, then changed again)
//            and unstaged (none staged, new files included), each file counted once; of those outside the extra
//            stage only, when it names them
//   extra    the checkout's extra stage, when it has one you've allowed (docs/reference/stages.md)
//   commits  commits not on GitHub yet: only with a remote, as a commit is finished without one
//   github   the branch's open pull request ("#14"), or "no PR" for a branch GitHub says was pushed without one
// `step` is the step its menu offers first (StepRequest's in app/NextSteps.m); `move` marks where your next move is,
// the stage holding work that's nearest GitHub.
function stagesOf(s, owner) {
  const c = s.checkout;
  if (!owner || !c) return null;
  const extra = c.stage && !c.stage.ask ? c.stage : null;
  // The extra stage's count of the files outside it stands for git's only while it holds something: when it's empty,
  // every change is outside it, and git's count says the same, with how the files split.
  const edits = extra?.count ? extra.edits : undefined;
  const files = edits ?? (c.changes || 0) + (c.newFiles || 0);
  const remote = c.remotes > 0, branch = (s.workGit || s.git)?.branch;
  const onBase = branch === c.base, pr = openPR(s), unpushed = unpushedCommits(c);
  // A pushed branch needs a pull request only once GitHub has said it has none (c.pr is null then; it's missing until
  // gh answers, and always without gh), and only if the agent hasn't raised one since GitHub last looked.
  const raised = s.outcome === 'PR raised' && (s.outcomeAt || 0) > (c.prCheckedAt || 0) * 1000;
  const needsPR = remote && !!branch && !onBase && !pr && (c.pr === null || c.pr?.state === 'CLOSED') && !raised
    && c.aheadOfBase > 0 && !unpushed;
  if (!files && !extra?.count && !unpushed && !needsPR) return null;
  const stages = [{ stage: 'files', count: files, text: counted(files, 'file', 'files'), step: 'commit',
                    tip: files ? `${plural(files, 'file', 'files')} changed` : 'No changed files' }];
  // The split comes from git's view of every change; an extra stage counting the files itself (some of them are in
  // it) makes that the wrong picture, so its count stands alone, unless it names the files it counts: then they're
  // split the same way (`parts`, from the app), and the gauge is of those.
  if (files && edits == null && c.filesStaged != null)
    stages[0].parts = { staged: c.filesStaged || 0, partly: c.filesPartly || 0,
                        unstaged: (c.filesUnstaged || 0) + (c.newFiles || 0) };
  else if (files && edits != null && extra.parts) stages[0].parts = { ...extra.parts };
  if (extra) stages.push({ stage: 'extra', count: extra.count,
                           text: `${compact(extra.count)} ${extra.label || 'pending'}`,
                           tip: `${extra.count} ${extra.label || 'pending'}` });
  if (remote) {
    stages.push({ stage: 'commits', count: unpushed, text: counted(unpushed, 'commit', 'commits'),
                  step: onBase || pr ? 'push' : 'pr',
                  tip: unpushed ? `${plural(unpushed, 'commit', 'commits')} not on GitHub yet` : 'No commits waiting' });
    stages.push(pr ? { stage: 'github', count: 1, text: `#${pr.number}`, pr: pr.number, tip: `Pull request #${pr.number}` }
      : needsPR ? { stage: 'github', count: 1, text: 'no PR', step: 'pr', tip: 'Pushed, with no pull request yet' }
      : { stage: 'github', count: 0, text: 'GitHub', tip: 'Nothing on GitHub yet' });
  }
  // A pull request already open is where the work is going, not a move of yours; one still to open is.
  const holding = stages.filter((st) => st.count > 0 && !(st.stage === 'github' && st.pr));
  holding[holding.length - 1].move = true;
  return stages;
}

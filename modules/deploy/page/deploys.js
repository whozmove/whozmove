// Deploy, for any project (app/Deploys.m): what a session's project would run, how its folder's last run went,
// whether its row has Deploy's round button and how it looks, and the card where you set what Deploy runs.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// Deploy's round button (deployHTML): play to deploy, a stop square while it runs (a press then offers Stop Deploy),
// and a check for a moment once it's done.
const PLAY_ICON = '<svg class="play-icon" width="8" height="8" viewBox="0 0 10 10"><path fill="currentColor" '
  + 'd="M2.6 1.4C2.6 .9 3.1 .6 3.5 .9L8.6 4.3C9 4.6 9 5.2 8.6 5.5L3.5 8.9C3.1 9.2 2.6 8.9 2.6 8.4Z"/></svg>';
const STOP_ICON = '<svg class="play-icon" width="8" height="8" viewBox="0 0 10 10"><rect x="2.4" y="2.4" width="5.2" '
  + 'height="5.2" rx="1.2" fill="currentColor"/></svg>';
const CHECK_ICON = '<svg class="play-icon" width="9" height="9" viewBox="0 0 10 10"><path d="M2 5.3 4.1 7.3 8 2.9" '
  + 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

// A session's project, as Deploy keys it: the repo's main checkout (its worktrees share one command), or its folder
// outside git. And the folder it deploys from: its own checkout, or that folder.
function projectKey(s) {
  const g = s.workGit || s.git;
  return g?.mainRoot || g?.root || s.cwd;
}
function folderOf(s) {
  const g = s.workGit || s.git;
  return g?.root || s.cwd;
}
// The folder a session's edits count for: the checkout they last landed in (workRoot), which can be another than its
// own, or its own folder when it hasn't edited anything.
function workFolder(s) {
  return s.workRoot || folderOf(s);
}

// Whether a session's last edits (workRoot) came during the turn it's on now: they landed after that turn began
// (lastPromptAt). An older hook doesn't note when it edited; then it's taken that they did.
const editingThisTurn = (s) => !s.editedAt || !s.lastPromptAt || s.editedAt >= s.lastPromptAt;

// What's known about a session's Deploy, from what the app sent (setDeploys): the command saved for its project, the
// one Whozmove suggests, and its folder's last deploy, skip and run.
function deployFor(s, deploys) {
  const key = projectKey(s), folder = folderOf(s), f = deploys.folders?.[folder] || {};
  return { key, folder, command: deploys.projects?.[key]?.command, suggested: f.suggested, at: f.at,
           skippedAt: f.skippedAt, run: f.run };
}

// Turns that changed or built something, so there could be a new version to put in place: what an older hook's
// session goes by.
const DEPLOYABLE = ['Implemented', 'Built', 'Tested', 'Validated'];

// When a session last changed or built something in `folder`, or 0. Its edits count in the checkout they landed in
// (the hook notes when, editedAt, and where, workRoot: workFolder), and its builds (builtAt) in the folder it runs in,
// where its commands run. So a turn that only commits or pushes, or only runs the tests, isn't new work, and doesn't
// hide the work before it either. An older hook notes where it edited but not when, nor builds; then the end of its
// last turn that changed or built something stands in, where it edited.
function deployWork(s, folder) {
  const edited = workFolder(s) === folder;
  const older = edited && s.workRoot && !s.editedAt && DEPLOYABLE.includes(s.outcome) ? s.outcomeAt || 0 : 0;
  return Math.max(edited ? s.editedAt || 0 : 0, folderOf(s) === folder ? s.builtAt || 0 : 0, older);
}

// When anything was last changed or built in each folder, by whichever session did it (deployWork says which folder
// each counts in): the row that offers Deploy is the folder's owner (checkoutOwners), which may not be the session
// that built, nor even one that runs there.
function folderWork(sessions) {
  const work = {};
  for (const s of sessions) {
    for (const folder of new Set([workFolder(s), folderOf(s)])) {
      const at = deployWork(s, folder);
      if (folder && at > (work[folder] || 0)) work[folder] = at;
    }
  }
  return work;
}

// The sessions whose agent is working (or compacting), by each folder they work in: their own checkout (or folder,
// outside git), and the one their edits land in while the turn they're on has edited files there (an edit from an
// earlier turn doesn't keep them at work there). `kinds` is what each session is now (classify). Deploy waits while any
// agent works in its folder, not just the row's own, so what's put in place isn't half-way through a change; so do the
// island's steps (OthersAtWork in app/core/Work.m), while the island stays up, to show where the work stands. One
// waiting on you doesn't count: it changes nothing until you answer it, which may be days away.
function agentsAtWork(sessions, kinds) {
  const at = {};
  for (const s of sessions) {
    if (kinds[s.sessionId] !== 'busy' && !s.compacting) continue;
    const there = editingThisTurn(s) ? s.workRoot : null;
    for (const folder of new Set([s.git?.root || s.cwd, there])) if (folder) (at[folder] ??= []).push(s);
  }
  return at;
}

// How a wait for the agents in other sessions is said, naming them as their rows are titled (`titles`, in order), as
// the app says it in the island's menus (WhyStepsWait in app/core/Work.m): "until the agent in “a” is done", "until the
// agents in “a” and “b” are done", "until the agents in “a” and 2 others are done".
function untilDone(titles) {
  const named = titles.map((t) => `“${t}”`);
  if (named.length === 1) return `until the agent in ${named[0]} is done`;
  const rest = named.length === 2 ? named[1] : `${named.length - 1} others`;
  return `until the agents in ${named[0]} and ${rest} are done`;
}

// Whether a row's Deploy is due: its project has a command (saved, or one Whozmove suggests; with neither, the
// project never shows Deploy), and something was changed or built in its folder (by this session, or another there:
// `d.work`) since the folder's last deploy, or since Deploy was last skipped there. This session's own work counts
// where it happened (deployWork): what it edited in another checkout is nothing new to put in place here.
function deployDue(s, d) {
  if (!d || !(d.command || d.suggested)) return false;
  return Math.max(deployWork(s, d.folder || folderOf(s)), d.work || 0) > Math.max(d.at || 0, d.skippedAt || 0);
}

// How long the check shows once a deploy has gone through, and how long the line under the row says why one didn't.
const DONE_MS = 1500, FAILED_MS = 10 * 60000;

// Deploy's round button on a row, or null. Only the row that speaks for its folder (`owner`) has one, and only while
// Show Deploy is on (`d`, deployFor's with `pressed`, `work`, `seenDone` and `waitsFor`, is null when it's off). Once
// you've confirmed a command for the project it's always there; with only a suggestion it's offered after new work in
// the folder (deployDue), until you set it up or pass on it; with neither, never. A deploy under way shows whatever the
// agents do meanwhile. Returns { look, due, running, waitsFor }:
// - `look`: 'going' (pressed, or `running`), 'done' (it went through: the check shows from when the page first saw it
//   had, `seenDone`, as the app looks only every couple of seconds), 'off' (the row's agent, or another working in its
//   folder, is working or asking, and a deploy waits for it) or 'ready';
// - `due`: whether something changed or was built in the folder since the last deploy (the dot);
// - `waitsFor`: the titles of the other sessions it waits for, when it's not the row's own agent.
function deployOffer(s, kind, owner, d, now) {
  if (!owner || !d) return null;
  const run = d.run || {}, due = deployDue(s, d), going = !!(run.running || d.pressed);
  if (!going && !d.command && !(d.suggested && due)) return null;
  const own = kind === 'busy' || kind === 'needs' || s.compacting;
  const look = going ? 'going'
    : run.ok && now - (d.seenDone || 0) < DONE_MS ? 'done'
    : own || d.waitsFor ? 'off' : 'ready';
  return { look, due, running: !!run.running, waitsFor: look === 'off' && !own ? d.waitsFor : undefined };
}

// The round button, at the end of a row's title line: play, with a dot when there's new work to deploy; a stop square
// in a slowly turning arc while it runs; a check for a moment once it's done; dimmed while the agent works. Its icon
// comes in, and its arc turns, on CSS animations started `--since` ago (the press, the run's start, the check, its
// end), so the rebuild every second carries them on rather than restarting them. `offer` is deployOffer's; `now` the
// page's clock.
function deployHTML(s, d, offer, now) {
  const run = d.run || {};
  const since = offer.look === 'going' ? now - (run.running ? run.startedAt : d.pressed)
    : offer.look === 'done' ? now - d.seenDone
    : run.ok ? now - (d.seenDone || 0) - DONE_MS
    : run.finishedAt ? now - run.finishedAt : Infinity;
  const icon = offer.look === 'going' ? STOP_ICON : offer.look === 'done' ? CHECK_ICON : PLAY_ICON;
  const failed = run.ok === false && !run.stopped ? `\nThe last deploy didn't go through: ${run.lastLine || ''}` : '';
  const more = '\nRight-click for more';
  const tip = offer.look === 'going' ? `Deploying: runs ${d.command || 'the saved command'}`
      + (offer.running ? '\nPress to stop it or see its log' : '')
    : offer.look === 'done' ? 'Deployed'
    : offer.look === 'off' ? `Deploy waits ${offer.waitsFor ? untilDone(offer.waitsFor) : 'until the agent is done'}`
      + more
    : d.command ? `Deploy: runs ${d.command}` + (offer.due ? '\nChanged since the last deploy' : '') + failed + more
    : `Set up Deploy: Whozmove suggests ${d.suggested}` + more;
  const cls = offer.look + (offer.running ? ' running' : '')
    + (offer.due && (offer.look === 'ready' || offer.look === 'off') ? ' new' : '');
  // Long past, an animation has nothing left to show, so the time stops counting (and the HTML stops changing); but the
  // arc turns for as long as a deploy runs, and keeps its place only with the true time.
  const shown = Math.max(0, offer.look === 'going' ? since : Math.min(since, 60000));
  return `<span class="play ${cls}" data-deploy="${esc(s.sessionId)}" title="${esc(tip)}"`
    + ` style="--since:-${Math.round(shown)}ms">`
    + '<svg class="play-ring" width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8"/></svg>'
    + `${icon}</span>`;
}

// The line under the row's details, when there's something to say about its folder's deploy: what's running (and,
// after 2 minutes, that it's still going: Deploy is for commands that finish), or for a while after a run that didn't
// go through, why (the end of its log), or that you stopped it. { text, quiet }, or null.
function deployNote(d, now) {
  const run = d.run || {};
  if (run.running && now - (run.startedAt || now) > 120000) {
    return { text: 'Still running: press its button to stop it or see its log', quiet: true };
  }
  if (run.running || d.pressed) return { text: `Deploying: ${d.command || ''}`, quiet: true };
  if (run.ok !== false || now - (run.finishedAt || 0) > FAILED_MS) return null;
  if (run.stopped) return { text: 'You stopped the deploy', quiet: true };
  return { text: `Couldn't deploy: ${run.lastLine || ''}` };
}

// The card where you set what Deploy runs for a project, in two steps, as a command will run as written whenever Deploy
// is pressed: the command (suggested, or the one saved, in a box to change), then the same again to confirm it, with
// what it really runs where it names package scripts or Makefile targets, and a warning if that looks as if it could
// reach production. Both come from the app, which reads the project's files (`setup.checked`, CheckDeploy in
// app/Deploys.m). `setup` is { step, text, then, checked }; `d` is deployFor's. Deploy runs in the checkout's top
// folder (`d.folder`), whichever folder the session is in.
function setupHTML(s, setup, d) {
  const card = `<div class="perm deploy-setup" data-setup="${esc(s.sessionId)}" data-step="${setup.step}">`;
  if (setup.step === 2) {
    const checked = setup.checked || {};
    const more = checked.more ? `\n… and ${checked.more} more` : '';
    return card + '<div class="q-top"><span class="q-head">Run this every time you press Deploy?</span></div>'
      + `<pre class="perm-detail">${esc(setup.text)}</pre>`
      + (checked.runs ? `<div class="q-help">That runs:</div><pre class="perm-detail">${esc(checked.runs + more)}</pre>`
        : '')
      + `<div class="q-help" title="${esc(d.folder)}">In ${esc(base(d.folder))}, on this Mac. Nothing else is sent`
      + ' anywhere.</div>'
      + (checked.production ? '<div class="c-note">This looks as if it could deploy to production.</div>' : '')
      + '<div class="perm-actions"><button class="d-back">Back</button>'
      + '<button class="perm-allow d-yes">Yes, use it</button></div></div>';
  }
  return card + `<div class="q-top"><span class="q-head">Set up Deploy for ${esc(base(d.key))}</span>`
    + '<button class="q-close" title="Close">×</button></div>'
    + `<div class="q-help" title="${esc(d.folder)}">What should Deploy run on this Mac? It runs in`
    + ` ${esc(base(d.folder))}, through your login shell, and should finish once it has done its job.</div>`
    + `<input class="q-type d-cmd" placeholder="A command that finishes" maxlength="1000"`
    + ` value="${esc(setup.text)}">`
    + '<div class="perm-actions"><button class="d-cancel">Cancel</button>'
    + `<button class="perm-allow d-next"${setup.text.trim() ? '' : ' disabled'}>Use this</button></div></div>`;
}

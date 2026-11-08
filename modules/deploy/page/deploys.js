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
// one Whozmove suggests, its folder's last deploy, skip and run, the port a deploy there gets in $PORT, the deploy a
// session asked for there (Let It Deploy), waiting: {by, waits}, and Deploy's card for the folder (deployCardHTML).
function deployFor(s, deploys) {
  const key = projectKey(s), folder = folderOf(s), f = deploys.folders?.[folder] || {};
  return { key, folder, command: deploys.projects?.[key]?.command, suggested: f.suggested, at: f.at,
           skippedAt: f.skippedAt, run: f.run, port: f.port, asked: f.asked, card: f.card, kept: f.kept };
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
// next steps (OthersAtWork in parts/work), which stay on the row meanwhile, dimmed. One
// waiting on you doesn't count: it changes nothing until you answer it, which may be days away. A conversation open
// more than once works wherever one of its copies does (s.alsoOpen), though its row shows another.
function agentsAtWork(sessions, kinds) {
  const at = {};
  for (const s of sessions) {
    // A session whose agents still work in the background (`background`) is at work there too.
    if (!['busy', 'background'].includes(kinds[s.sessionId]) && !s.compacting && !s.alsoOpen?.some((copy) => copy.busy))
      continue;
    const there = editingThisTurn(s) ? s.workRoot : null;
    for (const folder of new Set([s.git?.root || s.cwd, there])) if (folder) (at[folder] ??= []).push(s);
  }
  return at;
}

// How a wait for the agents in other sessions is said, naming them as their rows are titled (`titles`, in order), as
// the app says it when a step waits (WhyStepsWait in parts/work): "until the agent in “a” is done", "until the
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

// How long the check shows once a deploy has gone through, and how long the row's note says why one didn't.
const DONE_MS = 1500, FAILED_MS = 10 * 60000;

// Deploy's round button on a row, or null. Only the row that speaks for its folder (`owner`) has one, and only while
// Show Deploy is on (`d`, deployFor's with `pressed`, `work`, `seenDone` and `waitsFor`, is null when it's off). Once
// you've confirmed a command for the project it's always there; with only a suggestion it's offered after new work in
// the folder (deployDue), until you set it up or pass on it; with neither, never. A deploy under way shows whatever the
// agents do meanwhile. Returns { look, due, running, waitsFor }:
// - `look`: 'going' (pressed, or `running`), 'up' (running and listening on a port: a server, up), 'done' (it went
//   through: the check shows from when the page first saw it
//   had, `seenDone`, as the app looks only every couple of seconds), 'off' (the row's agent, or another working in its
//   folder, is working or asking, and a deploy waits for it) or 'ready';
// - `due`: whether something changed or was built in the folder since the last deploy (the dot);
// - `waitsFor`: the titles of the other sessions it waits for, when it's not the row's own agent;
// - `background`: why it waits for what the row's own agent runs in the background (classify's 'background'), in the
//   words the app put on the row (`backgroundWait`, from the work part), when that's what it waits for;
// - `kept`: while it waits, whether your press is kept, to deploy once that's done (`d.kept`, DeployKept in the app);
//   while it isn't, a press keeps one, for a project with a command (`keeps`).
function deployOffer(s, kind, owner, d, now) {
  if (!owner || !d) return null;
  const run = d.run || {}, due = deployDue(s, d), going = !!(run.running || d.pressed);
  if (!going && !d.command && !(d.suggested && due)) return null;
  const own = kind === 'busy' || kind === 'needs' || kind === 'background' || s.compacting;
  const look = going ? (run.running && run.up ? 'up' : 'going')
    : run.ok && now - (d.seenDone || 0) < DONE_MS ? 'done'
    : own || d.waitsFor ? 'off' : 'ready';
  const off = look === 'off';
  return { look, due, running: !!run.running, waitsFor: off && !own ? d.waitsFor : undefined,
           background: off && kind === 'background' ? s.backgroundWait || undefined : undefined,
           kept: off && d.kept ? true : undefined, keeps: off && !d.kept && d.command ? true : undefined };
}

// Who a press waits for, after "the", as its tip and note say it, naming the other sessions as their rows are titled,
// as untilDone does: "agent in “a” is", "agents in “a” and “b” are"; or the row's own, "agent is".
function waitedFor(titles) {
  if (!titles?.length) return 'agent is';
  return untilDone(titles).replace(/^until the /, '').replace(/ (is|are) done$/, ' $1');
}

// The row's note while your press is kept: "Deploys once the agent in “cart total” is done editing fix-cart", or once
// the row's own agent is done.
function keptNote(offer, name) {
  return offer.waitsFor ? `Deploys once the ${waitedFor(offer.waitsFor)} done editing ${name}`
    : 'Deploys once the agent is done';
}

// How long a build has been up, as its tip says it: " for 4 min", " for 2 h", or ", started just now".
function upFor(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return ', started just now';
  return m < 60 ? ` for ${m} min` : ` for ${Math.floor(m / 60)} h`;
}

// Where a build that's up can be opened: "localhost:3001".
const upAddress = (up) => `localhost:${up.port}`;

// An up build's tip, which is also what VoiceOver says of its button: where it runs and for how long, then what else
// holds (other devices can reach it, it listens on other ports too, files changed since it started).
function upTip(d, offer, now) {
  const up = d.run.up, lines = [`Running at ${upAddress(up)}${upFor(now - up.at)}. Press for its menu`];
  if (up.every) lines.push('Also open to other devices on your network');
  if (up.also?.length) lines.push(`Also listening on ${up.also.map((p) => ':' + p).join(', ')}`);
  if (offer.due) {
    lines.push('Files changed here since it started: restart to bring the changes in, unless the server reloads by '
               + 'itself');
  }
  return lines.join('\n');
}

// Where the arc had got to as the page first saw the build up (`seen`, or when it came up, for one already up when the
// page loaded), worked out from the same clock its turn runs on (the run's start: playTurn, a turn every 1.2s), so it
// closes into the ring from there.
const TURN_MS = 1200;
const upTurn = (run, seen) => ((((seen || run.up.at) - run.startedAt) % TURN_MS) / TURN_MS) * 360;

// The round button, at the end of a row's title line: play, with a dot when there's new work to deploy; a stop square
// in a slowly turning arc while it runs; once it's a server that's up, the stop square in a steady ring, the arc
// closing into it; a check for a moment once it's done; dimmed while the agent works. Its icon
// comes in, and its arc turns, on CSS animations started `--since` ago (the press, the run's start, the check, its
// end), so a rebuild of the list carries them on rather than restarting them. `offer` is deployOffer's; `now` the
// page's clock; `upSeen` when the page first saw the build up (0 for one up before it loaded).
function deployHTML(s, d, offer, now, upSeen = 0) {
  const run = d.run || {};
  if (offer.look === 'up') {
    const tip = upTip(d, offer, now), sinceUp = upSeen ? Math.min(now - upSeen, 60000) : 60000;
    return `<span class="play up running${offer.due ? ' new' : ''}" data-deploy="${esc(s.sessionId)}"`
      + ` title="${esc(tip)}" aria-label="${esc(tip)}" style="--since:-60000ms; --up-since:-${Math.round(sinceUp)}ms;`
      + ` --turn:${upTurn(run, upSeen).toFixed(1)}deg">`
      + '<svg class="play-ring" width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8"/></svg>'
      + `${STOP_ICON}</span>`;
  }
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
    : offer.kept ? `${keptNote(offer, base(d.folder))}, so the build never catches a file half-written\nPress for its menu`
    : offer.keeps && offer.waitsFor ? `Deploy: runs ${d.command}\nThe ${waitedFor(offer.waitsFor)} editing`
      + ` ${base(d.folder)}: a press deploys once that's done` + more
    : offer.keeps && offer.background ? `Deploy: runs ${d.command}\nDeploy waits ${offer.background}\nA press deploys`
      + ' once that\'s done' + more
    : offer.keeps ? `Deploy: runs ${d.command}\nThe agent is at work in ${base(d.folder)}: a press deploys once it's done`
      + more
    : offer.look === 'off' ? `Deploy waits ${offer.waitsFor ? untilDone(offer.waitsFor)
      : offer.background || 'until the agent is done'}`
      + more
    : d.command ? `Deploy: runs ${d.command}` + (offer.due ? '\nChanged since the last deploy' : '') + failed + more
    : `Set up Deploy: Whozmove suggests ${d.suggested}` + more;
  const cls = offer.look + (offer.running ? ' running' : '') + (offer.kept ? ' kept' : offer.keeps ? ' keeps' : '')
    + (offer.due && (offer.look === 'ready' || offer.look === 'off') ? ' new' : '');
  // Long past, an animation has nothing left to show, so the time stops counting (and the HTML stops changing); but the
  // arc turns for as long as a deploy runs, and keeps its place only with the true time.
  const shown = Math.max(0, offer.look === 'going' ? since : Math.min(since, 60000));
  return `<span class="play ${cls}" data-deploy="${esc(s.sessionId)}" title="${esc(tip)}"`
    + ` style="--since:-${Math.round(shown)}ms">`
    + '<svg class="play-ring" width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8"/></svg>'
    + `${icon}</span>`;
}

// Whether a command looks as if it starts a server (a dev, start, serve or preview script, or a server it names), so
// a run that hasn't listened yet is said to have no address yet, rather than only to be running long. A watch alone
// (`tsc --watch`) runs for good without being one.
const SERVER_WORDS = /\b(dev|start|serve|server|preview)\b|http\.server/;

// The address of a build that's up, after the folder on the bottom line (":3001"), pressed to open it. Once the ring
// has closed, its room opens, then it fades in, lifting 3px (deploy.css), from when the page first saw it up.
function deployAddressHTML(s, d, now, upSeen = 0) {
  const up = d.run.up, words = `Open ${upAddress(up)}`;
  const sinceUp = upSeen ? Math.min(now - upSeen, 60000) : 60000;
  return `<span class="d-addr" data-addr="${esc(s.sessionId)}" role="button" title="${esc(words)}"`
    + ` aria-label="${esc(words)}" style="--up-since:-${Math.round(sinceUp)}ms"><span class="d-addr-in">`
    + `:${esc(up.port)}</span></span>`;
}

// The row's note (in its work line's place), when there's something to say about its folder's deploy: what's running
// (and, after 2 minutes, that it's still going with no address yet), nothing once a server's up, a deploy a session
// asked for and what it waits for, or for a while after a run, why one didn't go through (the end of its log), that
// you stopped it, or which session asked for one that went through. Why one didn't go through is its card's to say
// (deployRunCard), and once that's put away (`shut`, its key), it isn't said again. { text, quiet }, or null.
function deployNote(d, now, shut) {
  const run = d.run || {};
  // A session's ask to restart the build that's up, while it waits: said, as the ring alone wouldn't say it.
  if (d.asked?.restart) return { text: `Restart asked by “${d.asked.by}” · ${d.asked.waits}`, quiet: true };
  if (run.running && run.up) return null;  // the ring and the address say it
  if (run.installing) return { text: `Installing packages first: ${run.installing}`, quiet: true };
  if (run.running && now - (run.installedAt || run.startedAt || now) > 120000) {
    const server = SERVER_WORDS.test(d.command || '');
    return { text: server ? 'Still running, with no address yet: press its button to stop it or see its log'
      : 'Still running after 2 minutes: press its button to stop it or see its log', quiet: true };
  }
  if (run.running || d.pressed) return { text: `Deploying: ${d.command || ''}`, quiet: true };
  if (d.asked) return { text: `Deploy asked by “${d.asked.by}” · ${d.asked.waits}`, quiet: true };
  if (!run.finishedAt || now - run.finishedAt > FAILED_MS) return null;
  if (run.ok) return run.by ? { text: `Deployed by “${run.by}”`, quiet: true } : null;
  if (run.stopped) return { text: 'You stopped the deploy', quiet: true };
  if (shut === `end:${run.finishedAt}`) return null;
  return { text: `Couldn't deploy: ${run.lastLine || ''}` };
}

// Names as a list in words: "a", "a and b", "a, b and c".
function namesAnd(names) {
  return names.length < 2 ? names.join('') : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

// The card where you set what Deploy runs for a project, in two steps, as a command will run as written whenever Deploy
// is pressed: the command (suggested, or the one saved, in a box to change), then the same again to confirm it, with
// what it really runs where it names package scripts or Makefile targets, and a warning if that looks as if it could
// reach production. Both come from the app, which reads the project's files (`setup.checked`, CheckDeploy in
// app/Deploys.m), all of it, to scroll through, with the files checked before every run, the programs that aren't, and
// what Whozmove can't follow. Confirming also says the port it gets in $PORT here, as a command confirmed on this card
// runs with one. `setup` is { step, text, then, checked }; `d` is deployFor's. Deploy runs in the checkout's top folder
// (`d.folder`), whichever folder the session is in.
function setupHTML(s, setup, d) {
  const card = `<div class="perm deploy-setup" data-setup="${esc(s.sessionId)}" data-step="${setup.step}">`;
  if (setup.step === 2) {
    const checked = setup.checked || {};
    const more = checked.cut ? '\n… and more than the card can show' : '';
    return card + '<div class="q-top"><span class="card-title">Run this every time you press Deploy?</span></div>'
      + `<pre class="perm-detail">${esc(setup.text)}</pre>`
      + (checked.runs ? `<div class="q-help">That runs:</div><pre class="perm-detail">${esc(checked.runs + more)}</pre>`
        : '')
      + checkedHTML(checked, { before: 'Before each run', as: 'as you confirmed, and asks you again if not' })
      + `<div class="q-help" title="${esc(d.folder)}">In ${esc(base(d.folder))}, on this Mac. Nothing else is sent`
      + ' anywhere.</div>'
      + (d.port ? `<div class="q-help">If it starts a server, it gets port ${esc(d.port)} in $PORT here, and each`
        + ` checkout of ${esc(base(d.key))} its own, so their builds can run side by side.</div>` : '')
      + (checked.production ? '<div class="c-note notice inline warn">This looks as if it could deploy to production.</div>'
        : '')
      + '<div class="perm-actions"><button class="d-back">Back</button>'
      + '<button class="perm-allow d-yes">Yes, use it</button></div></div>';
  }
  return card + `<div class="q-top"><span class="card-title">Set up Deploy for ${esc(base(d.key))}</span>`
    + '<button class="icon-button small q-close" title="Close">×</button></div>'
    + `<div class="q-help" title="${esc(d.folder)}">What should Deploy run on this Mac? It runs in`
    + ` ${esc(base(d.folder))}, through your login shell: a command that does its job and finishes, or a server that`
    + ' keeps running.</div>'
    + `<input class="field q-type d-cmd" placeholder="A command, or a server" maxlength="1000"`
    + ` value="${esc(setup.text)}">`
    + '<div class="perm-actions"><button class="d-cancel">Cancel</button>'
    + `<button class="perm-allow d-next"${setup.text.trim() ? '' : ' disabled'}>Use this</button></div></div>`;
}

// Deploy's card on a row, when a press didn't run as it was: what happened, in plain words, and what you can do. `c`
// is what the app sent for the folder (Deploys.m's port check): its port held by another of Deploy's builds
// (`clash`: replace it, run on the next free port, or, for a command confirmed before ports, give each checkout one),
// or by something Deploy didn't start (`held`: run on the next free port, or go to the session that started it).
// `name` is the checkout's, `project` the project's. Each action is [what it does, its label, whether it leads]. A
// card a session's ask met (`asked`, its title) says so first, as nothing you pressed put it there.
function deployCard(c, name, project) {
  const asked = c.asked ? `“${c.asked}” asked to deploy ${name}. ` : '';
  if (c.kind === 'clash') {
    const why = c.fixed ? `${project}'s dev server listens on ${c.port} whatever port Deploy gives it, so two of its`
        + ' builds can\'t run side by side. To run them together, have its dev script use $PORT.'
      : c.old ? 'This command was set up before Deploy gave each checkout its own port, so every build takes'
        + ` ${c.port}. Give each its own, and ${name}'s runs beside ${c.other}'s.`
      : c.next ? `Or run ${name}'s beside it on the next free port, ${c.next}, from now on.` : '';
    // Side by side is what's wanted, so a port of its own leads where it can; replacing leads only where it can't.
    return { title: `${c.other}'s build is on port ${c.port}. Replace it?`, help: asked + why,
             acts: [['cancel', 'Cancel'], ...(c.old ? [['ports', 'Give Each a Port…', true]] : []),
                    ...(c.next && !c.fixed && !c.old ? [['next', `Use Port ${c.next}`]] : []),
                    ['replace', 'Stop It and Deploy', !c.old]] };
  }
  if (c.kind === 'held') {
    const holder = c.sessionName ? `a server the agent in “${c.sessionName}” started` : c.name || 'another program';
    const ran = c.minutes >= 1 ? `, running for ${c.minutes < 60 ? `${c.minutes} min` : `${Math.floor(c.minutes / 60)} h`}`
      : '';
    return { title: `Port ${c.port} is in use by ${holder}`,
             help: `${asked}It's ${c.name || 'a program'}${ran}. Deploy stops only the builds it started:`
               + (c.next ? ` run ${name}'s on port ${c.next} from now on, or` : '') + ' stop that one where it was'
               + ' started.',
             acts: [['cancel', 'Cancel'], ...(c.session ? [['session', 'Take Me There']] : []),
                    ...(c.next ? [['next', `Use Port ${c.next}`, true]] : [])] };
  }
  return null;
}

// How long the Deployed card shows after the page saw a server come up, unless you open it or close it first.
const DEPLOYED_CARD_MS = 10 * 60000;

// The card a folder's own run has to say, when the app sent none (deployFor's `card`), or null. Each has a `key`, which
// putting it away (its ×, Keep Waiting, opening the address) remembers, so it stays away until the run changes:
// - `ok`: a server came up while the page looked (`upSeen`), for 10 minutes;
// - `noaddr`: a command that looks like a server (SERVER_WORDS) running 2 minutes without listening, counted from when
//   its packages went in for one that installed them first (`installedAt`);
// - `itself`: a server that was up and stopped by itself; `packages`: one that failed for packages not installed;
//   `installFailed`: Install First's install that didn't go through, so the command never ran;
//   `failed`: any other run that didn't go through, with what it last said. These stay until put away or the next
//   deploy. `shut` is the key put away for the folder.
function deployRunCard(d, now, upSeen, shut) {
  const run = d.run || {}, command = d.command || '';
  let card = null;
  if (run.running && run.up) {
    if (upSeen && now - upSeen < DEPLOYED_CARD_MS) card = { kind: 'ok', up: run.up, key: `up:${run.up.at}` };
  } else if (run.running) {
    // Not while it installs the packages first (Install First), which can take minutes, and from when that ended.
    const since = run.installedAt || run.startedAt;
    if (!run.installing && now - (since || now) > 120000 && SERVER_WORDS.test(command)) {
      card = { kind: 'noaddr', minutes: Math.floor((now - since) / 60000), key: `wait:${run.startedAt}` };
    }
  } else if (run.ok === false && !run.stopped && run.finishedAt) {
    const kind = run.installFailed ? 'installFailed' : run.endedItself ? 'itself' : run.noPackages ? 'packages'
      : 'failed';
    card = { kind, lines: run.lastLines || (run.lastLine ? [run.lastLine] : []), up: run.up, install: run.install,
             lockfile: run.lockfile, installed: run.installFailed,
             minutes: run.up ? Math.max(1, Math.round((run.finishedAt - run.up.at) / 60000)) : 0,
             key: `end:${run.finishedAt}` };
  }
  return card && card.key !== shut ? card : null;
}

// How long, said: "4 min", "2 h".
const ranFor = (minutes) => (minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h`);

// The words of a run's own card (deployRunCard's), as deployCard's are: what happened, then what you can do. `first`
// says, once for a project, that each checkout runs beside the others. With no packages, the way forward is installing
// them: Install First… (it leads) asks first (`installing`, the card's second step) whether to run the install its
// lock file names once, then deploy, showing what that runs as the app followed it (`installing` is then that check,
// DeployInstallCheck in app/Deploys.m, or true while it's still being worked out): the project's own install scripts,
// all of them, or that it has none, the files checked again before it runs, and that its packages' own install scripts
// run too, unchecked. Copy and Go puts that install on the clipboard (the app's, from the files it reads) and opens the
// row's session, in that checkout, to run it there. Three buttons, so each fits on one line in the panel at its
// narrowest.
function deployRunCardWords(c, name, project, command, first, installing) {
  const server = SERVER_WORDS.test(command);
  [name, project, command] = [name, project, command].map((words) => deployWhole(words));
  const install = deployWhole(c.install || 'npm install');
  switch (c.kind) {
    case 'ok': return {
      titleHTML: `Deployed: open ${esc(project)} at <button class="d-link" data-act="open">${esc(upAddress(c.up))}</button>`,
      help: first ? `Each checkout gets its own address, so ${name} runs beside the others. It keeps running until`
        + ' you stop it from its button.' : '', acts: [] };
    case 'noaddr': return {
      title: `${name}'s build has run ${c.minutes} min without opening a port`,
      help: `It may still be starting: Deploy shows its address once it listens. If ${command} isn't a server, it`
        + ' should finish by itself.',
      acts: [['log', 'Open Log'], ['stop', 'Stop It'], ['wait', 'Keep Waiting', true]] };
    case 'itself': return {
      title: `${name}'s build stopped by itself after ${ranFor(c.minutes)}`,
      help: `It was running at ${upAddress(c.up)}. Its last lines:`, lines: c.lines,
      acts: [['log', 'Open Log'], ['again', 'Deploy Again', true]] };
    case 'installFailed': return {
      title: `${deployWhole(c.installed)} didn't go through in ${name}`,
      help: `Its packages aren't installed, so Deploy didn't run ${command}. Its last lines:`, lines: c.lines,
      acts: [['log', 'Open Log'], ['copyAndGo', 'Copy and Go', true]] };
    case 'packages': return installing ? installStep(c, name, project, command, installing) : {
      title: `${name} has no packages installed yet`,
      help: `A new worktree starts without them, so ${command} couldn't find what it needs. Install them with`
        + ` ${install} in ${name}, then deploy.`, lines: c.lines,
      acts: [['log', 'Open Log'], ['copyAndGo', 'Copy and Go'], ['install', 'Install First…', true]] };
    case 'failed': return {
      title: server ? `${name}'s build stopped before it was up` : `${name}'s deploy didn't go through`,
      help: `${command} ended with an error${server ? ` before ${project} listened on its port` : ''}. Its last lines:`,
      lines: c.lines, acts: [['log', 'Open Log'], ['again', 'Try Again', true]] };
  }
  return null;
}

// What Deploy checks before a command runs, and what it can't, as the app followed it (CheckDeploy or
// DeployInstallCheck in app/Deploys.m), for the set-up card's second step and Install First's: the files it checks,
// said with `before` and `as`; what isn't checked, each program by what it does ("what server.js loads" says itself),
// and the two the app marks, an install's packages' own install scripts (`packagesRun`, which Install First says on a
// line of its own, `install`) and the other files a package runner may read (`runnerFiles`), last; and what Whozmove
// can't tell.
function checkedHTML(check, { before, as, install = false }) {
  const others = (check.others || []).map((o) => (/^what /.test(o) ? o : `what ${o} does`));
  if (check.packagesRun && !install) others.push('what its packages\' install scripts do');
  if (check.runnerFiles) others.push('other files npm, pnpm, yarn or bun may read');
  const files = (check.files || []).map((file) => deployWhole(file));
  // Install First says its packages' scripts on a line of its own, and of the rest only that these files are checked,
  // not what they do: its list of programs would read as one more thing to look at, for a question about packages.
  const notChecked = install && files.length && others.length
    ? ' It checks these files, not what they do when they run.' : '';
  return (files.length ? `<div class="q-help">${before}, Deploy checks that ${esc(namesAnd(files))}`
      + ` ${files.length === 1 ? 'is' : 'are'} ${as}.${notChecked}</div>` : '')
    + (others.length && !install ? `<div class="q-help">Not checked: ${esc(namesAnd(others))}.</div>` : '')
    + (check.unsure?.length ? `<div class="c-note notice inline warn">Whozmove can't tell all this runs: `
      + `${esc(check.unsure.join('; '))}.</div>` : '');
}

// A command's or a file's name kept on one line of a card, its spaces and hyphens ones a line can't break at, so
// "pnpm install --frozen-lockfile" or "pnpm-lock.yaml" never reads as two things across a break. Only a name short
// enough to fit: a long command a session's project confirmed still wraps.
function deployWhole(words) {
  return words.length <= 40 ? words.replace(/ /g, '\u00a0').replace(/-/g, '\u2011') : words;
}

// Install First's second step: what the install runs, as the app followed it (`check`, or true until it has), and
// Install and Deploy, which takes a press only once that's shown. Every word from the project's files is escaped.
function installStep(c, name, project, command, check) {
  const known = check !== true ? check : null;
  const words = deployWhole(known?.words || c.install || 'npm install');
  const lockfile = deployWhole((known ? known.lockfile : c.lockfile) || '');
  const more = known?.cut ? '\n… and more than the card can show' : '';
  const detail = !known ? '<div class="q-help">Looking at what it runs…</div>'
    : (known.runs ? `<div class="q-help">That runs ${esc(project)}'s own install scripts:</div>`
        + `<pre class="perm-detail">${esc(known.runs + more)}</pre>`
      : `<div class="q-help">${esc(project)} has no install scripts of its own.</div>`)
      + '<div class="q-help">Its packages\' own install scripts run too, which Deploy doesn\'t check.</div>'
      + checkedHTML(known, { before: 'Just before it runs', as: 'as shown here, and shows you this again if not',
                             install: true });  // its packages' scripts are said above
  return {
    title: `Run ${words} in ${name}, then deploy?`,
    help: lockfile ? `Once, in ${name}, on this Mac, from ${project}'s ${lockfile}, which it leaves as it is.`
        + ` Deploy then runs ${command} as you confirmed it.`
      : `Once, in ${name}, on this Mac. ${project} has no lock file, so it makes a ${deployWhole('package-lock.json')}.`
        + ` Deploy then runs ${command} as you confirmed it.`,
    detailHTML: detail,
    acts: [['back', 'Back'], ['installNow', 'Install and Deploy', true, !known]] };
}

// The card itself, in the row's card place, with its ×: the app's (deployCard) or the run's own (deployRunCard, with
// `first` for the Deployed card's line). A run's last lines show whole, up to five, each cut with … at the card's edge
// rather than wrapped, its whole text in its tip.
function deployCardHTML(s, c, d, first = false, installing = false) {
  const card = c.key ? deployRunCardWords(c, base(d.folder), base(d.key), d.command || '', first, installing)
    : deployCard(c, base(d.folder), base(d.key));
  if (!card) return '';
  const acts = card.acts.map(([act, label, lead, off]) =>
    `<button class="${lead ? 'perm-allow ' : ''}d-act" data-act="${esc(act)}"${off ? ' disabled' : ''}>`
    + `${esc(label)}</button>`).join('');
  const lines = (card.lines || []).slice(-5).map((line) =>
    `<div class="d-line" title="${esc(line)}">${esc(line) || '&nbsp;'}</div>`).join('');
  return `<div class="perm deploy-state d-${esc(c.kind)}" data-dstate="${esc(s.sessionId)}">`
    + `<div class="q-top"><span class="card-title">${card.titleHTML ?? esc(card.title)}</span>`
    + '<button class="icon-button small q-close d-x" title="Close">×</button></div>'
    + (card.help ? `<div class="q-help">${esc(card.help)}</div>` : '')
    + (lines ? `<div class="perm-detail d-words">${lines}</div>` : '') + (card.detailHTML || '')
    + (acts ? `<div class="perm-actions">${acts}</div>` : '') + '</div>';
}

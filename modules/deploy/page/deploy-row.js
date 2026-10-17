// Deploy on a row: its round button, the line under the details about its folder's last deploy, the card where you
// set what it runs, and what the app says about it (deploys.js has the plain functions they're drawn from).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What the app knows, by project and folder (setDeploys); when Deploy was pressed in each folder, until the app's run
// shows; the set-up card open on each row, { step, text, then, checking, checked }; when each folder's sessions last
// changed or built something, and which are at work in it, from the last render (folderWork, agentsAtWork); and each
// folder's last run that went through, { finishedAt, at }, `at` being when the page first saw it had (0 for one that
// ended before the page could have seen it), which is when its check shows.
moduleState({ deploys: { projects: {}, folders: {} }, deployPressed: {}, deploySetup: {}, folderWork: {}, atWork: {},
              deploySeen: {} });

// What a row's Deploy knows (deployFor), with when it was pressed here (until the app's run shows), when any session
// in its folder last changed or built something, when the page saw its last run go through, and the titles of the
// other sessions at work in its folder, in order, which a deploy waits for; null while Show Deploy is off.
function rowDeploy(s) {
  if (!state.switches.deploy) return null;
  const deploy = deployFor(s, state.deploys);
  const others = (state.atWork[deploy.folder] || []).filter((x) => x.sessionId !== s.sessionId)
    .map((x) => x.name || base(x.cwd));
  return { ...deploy, pressed: state.deployPressed[deploy.folder], work: state.folderWork[deploy.folder],
           seenDone: state.deploySeen[deploy.folder]?.at,
           waitsFor: others.length ? [...new Set(others)].sort() : null };
}

// ---- Presses ----

// Deploy's round button (deployHTML): a press deploys the row's folder with the command saved for its project, or,
// with none saved yet, opens the set-up card. While a deploy runs, a press opens its menu instead (Stop Deploy, its
// log); only just pressed, before the run shows, or while the agent works or asks, it takes nothing. A Control-click is
// a right-click, which opens the menu whatever the button shows (deployMenu), so it's left to that. A button only just
// shown doesn't take a press yet.
function pressDeploy(button, e) {
  e.preventDefault();
  const sid = button.dataset.deploy;
  if (e.ctrlKey || justShown('deploy:' + sid)) return;
  if (button.classList.contains('running')) return deployMenu(button);
  if (button.classList.contains('going') || button.classList.contains('off')) return;
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s) return;
  const deploy = deployFor(s, state.deploys);
  if (deploy.run?.running || state.deployPressed[deploy.folder]) return;
  if (!deploy.command) return openSetup(sid, 'deploy');
  delete state.stepNotes[sid];
  state.deployPressed[deploy.folder] = Date.now();
  native({ type: 'deploy', sessionId: sid });
  render();
}

// Deploy's menu (the app's: what it runs, changing or forgetting that, stopping a run, the log), below its button.
function deployMenu(button) {
  const r = button.getBoundingClientRect();
  native({ type: 'stepMenu', step: 'deploy', sessionId: button.dataset.deploy, x: r.left - 4, y: r.bottom + 4 });
}

// A right-click (or Control-click) on Deploy's button opens its menu, in place of WebKit's own.
list.addEventListener('contextmenu', (e) => {
  const button = e.target.closest('.play[data-deploy]');
  if (!button) return;
  e.preventDefault();
  deployMenu(button);
});

// The set-up card for what Deploy runs, opened on a row: with the command saved for its project, or the one Whozmove
// suggests. `then` is 'deploy' when Deploy opened it (once confirmed, it deploys), 'save' when it's a change.
function openSetup(sid, then) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s || s.ask) return;  // a request waiting on the row comes first
  const deploy = deployFor(s, state.deploys);
  openingCard(sid, 'setup');
  state.deploySetup[sid] = { step: 1, text: deploy.command || deploy.suggested || '', then };
  state.shownAt['setup:' + sid] = Date.now();
  render();
}

// The set-up card: Use this goes on to confirming the command exactly as it will run, with what it really runs, once
// the app has said (deployChecked); Back returns to change it, and Yes saves it (and deploys, when Deploy
// opened the card); Cancel or × closes it. A button only just shown, as Yes is where Use this was and Cancel where
// Back was, doesn't count yet, so a double click can't confirm both steps, or close the card it has just gone back to.
function pressSetup(card, e) {
  const sid = card.dataset.setup, setup = state.deploySetup[sid], button = e.target.closest('button');
  if (!button || !setup) return;
  e.preventDefault();
  if (button.disabled || justShown('setup:' + sid)) return;
  if (button.matches('.q-close, .d-cancel')) delete state.deploySetup[sid];
  else if (button.matches('.d-back')) {
    Object.assign(setup, { step: 1, checked: null });
    state.shownAt['setup:' + sid] = Date.now();
  } else if (button.matches('.d-next') && setup.text.trim()) {
    setup.checking = setup.text.trim();
    native({ type: 'checkDeployCommand', sessionId: sid, command: setup.checking });
    return;
  } else if (button.matches('.d-yes')) {
    const s = state.last.sessions.find((x) => x.sessionId === sid), deployNow = setup.then === 'deploy';
    native({ type: 'saveDeployCommand', sessionId: sid, command: setup.text.trim(), deployNow });
    if (deployNow && s) state.deployPressed[folderOf(s)] = Date.now();
    delete state.deploySetup[sid];
  }
  render();
}

// ---- What the app says ----

// What Deploy knows (app/Deploys.m), whenever it changes: each project's saved command, and each folder's suggestion,
// last deploy, skip and run. A press here stands in for the run until the app's run shows (or for 15s). A run seen
// to have gone through for the first time gets its check from now, as the app looks only every couple of seconds:
// unless it ended longer ago than that, before the page could have seen it (it loaded since).
window.setDeploys = (deploys) => {
  state.deploys = { projects: deploys.projects || {}, folders: deploys.folders || {} };
  const now = Date.now();
  for (const [folder, at] of Object.entries(state.deployPressed)) {
    const run = state.deploys.folders[folder]?.run;
    if ((run && run.startedAt >= at - 1000) || now - at > 15000) delete state.deployPressed[folder];
  }
  for (const folder of Object.keys(state.deploySeen)) {
    if (!state.deploys.folders[folder]) delete state.deploySeen[folder];
  }
  for (const [folder, f] of Object.entries(state.deploys.folders)) {
    const run = f.run;
    if (!run?.ok || run.running || state.deploySeen[folder]?.finishedAt === run.finishedAt) continue;
    state.deploySeen[folder] = { finishedAt: run.finishedAt, at: now - run.finishedAt < 10000 ? now : 0 };
  }
  if (!state.sliding && !state.composing) render();
};

// What a command on the set-up card really runs, and whether it looks as if it could reach production, as the app
// found it (CheckDeploy in app/Deploys.m), asked when Use this was pressed: the card goes on to confirming it, with
// that. Not if the command has changed since it was asked about, or the card has moved on or gone.
window.deployChecked = (sid, check) => {
  const setup = state.deploySetup[sid];
  if (!setup || setup.step !== 1 || setup.checking !== check.command || setup.text.trim() !== check.command) return;
  Object.assign(setup, { step: 2, checking: null, checked: check });
  state.shownAt['setup:' + sid] = Date.now();
  render();
};

// Change Deploy Command… or Set Up Deploy…, in Deploy's menu: the set-up card opens on the row (openSetup).
window.openDeploySetup = (sid, then) => openSetup(sid, then);

// ---- What it plugs into ----

// Its button, while it's offered; when it isn't, what it showed is forgotten, so one that's back waits again before it
// takes a press, as the island does. It goes by the page's own clock (row.clock), which its press and animations are
// timed by.
core.rowLooks.push((row) => {
  row.deploy = rowDeploy(row.s);
  row.offer = deployOffer(row.s, row.kind, row.owner, row.deploy, row.clock);
  if (row.offer) state.shownAt['deploy:' + row.s.sessionId] ??= row.clock;
  else delete state.shownAt['deploy:' + row.s.sessionId];
});
core.slots.time.push((row) => (row.offer ? deployHTML(row.s, row.deploy, row.offer, row.clock) : ''));
// The line under the details, on a row with the button: what its folder's deploy has to say.
core.rowNotes.push((row) => (row.offer ? deployNote(row.deploy, Date.now()) : null));
// The set-up card, after a request or the Compact card on the row.
core.rowCards.push({
  name: 'setup', order: 30,
  wants: (row) => !!state.deploySetup[row.s.sessionId],
  html: (row) => setupHTML(row.s, state.deploySetup[row.s.sessionId], deployFor(row.s, state.deploys)),
});
core.presses.push(['.play[data-deploy]', pressDeploy], ['.perm[data-setup]', pressSetup]);
core.typing.push(['.d-cmd', (box) => {
  const setup = state.deploySetup[box.closest('.perm').dataset.setup];
  if (setup) setup.text = box.value;
  const next = box.closest('.perm').querySelector('.d-next');
  if (next) next.disabled = !box.value.trim();
}]);
core.pointerTargets.push('.play:not(.off)');
// When each folder's sessions last changed or built something, and which are at work in it, from the sessions listed.
core.beforeDraw.push((listed) => {
  state.folderWork = folderWork(listed);
  state.atWork = agentsAtWork(listed, state.shownKind);
});
// A step's note (why a deploy couldn't start, say): a Deploy pressed there stops standing in for a run.
core.noted.push((s) => { delete state.deployPressed[folderOf(s)]; });
core.forgotten.keys.push('deploySetup');
core.forgotten.prefixes.push('setup', 'deploy');

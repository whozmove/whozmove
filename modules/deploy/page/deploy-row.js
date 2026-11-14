// Deploy on a row: its round button, the row's note about its folder's last deploy, the card where you
// set what it runs, and what the app says about it (deploys.js has the plain functions they're drawn from).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What the app knows, by project and folder (setDeploys); when Deploy was pressed in each folder, until the app's run
// shows; the set-up card open on each row, { step, text, then, checking, checked }; when each folder's sessions last
// changed or built something, and which are at work in it, from the last render (folderWork, agentsAtWork); and each
// folder's last run that went through, { finishedAt, at }, `at` being when the page first saw it had (0 for one that
// ended before the page could have seen it), which is when its check shows; and each folder's build that's up,
// { at, seen }, `seen` being when the page first saw it up (0 for one up before the page loaded), which is when its arc
// closes into the ring and its address comes in; the run's own card put away in each folder, by its key
// (deployRunCard), and the one at Install First's second step, each by its key, with what its install runs as the app
// found it, by folder (deployInstallChecked), and whether that changed under a press, so the step shows again; and for each project, the Deployed card that says each checkout runs beside the others, once.
moduleState({ deploys: { projects: {}, folders: {} }, deployPressed: {}, deploySetup: {}, folderWork: {}, atWork: {},
              deploySeen: {}, deployUpSeen: {}, deployShut: {}, deploySide: {}, deployInstall: {},
              deployInstallChecks: {}, deployInstallAgain: {} });

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
// shown doesn't take a press yet. Dimmed while an agent works there, a press is kept by the app, to deploy once that's
// done (DeployKept), and while one is kept, a press opens the menu, with Don't Deploy.
function pressDeploy(button, e) {
  e.preventDefault();
  const sid = button.dataset.deploy;
  if (e.ctrlKey || justShown('deploy:' + sid)) return;
  if (button.classList.contains('running') || button.classList.contains('kept')) return deployMenu(button);
  if (button.classList.contains('keeps')) {
    native({ type: 'deploy', sessionId: sid });
    return;
  }
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

// The address of a build that's up: a press opens it in the app that opens web pages (the app makes the address from
// the port it read, never from the page). Not while it's only just shown.
function pressAddress(el, e) {
  e.preventDefault();
  if (justShown('addr:' + el.dataset.addr)) return;
  native({ type: 'openAddress', sessionId: el.dataset.addr });
  // Opened: the Deployed card has said what it had to.
  const s = state.last.sessions.find((x) => x.sessionId === el.dataset.addr);
  const up = s && deployFor(s, state.deploys).run?.up;
  if (up) {
    state.deployShut[folderOf(s)] = `up:${up.at}`;
    render();
  }
}

// Deploy's card: × or Cancel puts it away, Take Me There opens the session that started what holds the port, and the
// rest the app does (deployCard in DeployModule.m), deciding the port itself. A run's own card (deployRunCard) opens
// the address or the log, copies the install command and opens the row's session (Copy and Go), asks whether to
// install the packages first and then does (installAndDeploy, from this press alone), stops the run or deploys again,
// and is put away by its key, so it stays away for that run. Not while it's only just shown (its second step waits again, as a card just shown).
function pressCard(card, e) {
  const button = e.target.closest('button');
  if (!button) return;
  e.preventDefault();
  const sid = card.dataset.dstate;
  if (justShown('dcard:' + sid)) return;
  const act = button.matches('.d-x') ? 'close' : button.dataset.act;
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  const d = s && deployFor(s, state.deploys);
  if (!d) return;
  const seen = state.deployUpSeen[d.folder]?.seen || 0;
  const c = d.card || deployRunCard(d, Date.now(), seen, state.deployShut[d.folder]);
  // Take Me There: the session that started what holds the port.
  if (act === 'session') {
    const there = state.last.sessions.find((x) => x.sessionId === c?.session);
    if (there) openSession(there);
    return;
  }
  if (!c?.key) return native({ type: 'deployCard', sessionId: sid, act });
  // The run's own card: what it says to do, done here or by the app; putting it away is remembered by its key.
  if (act === 'open') native({ type: 'openAddress', sessionId: sid });
  else if (act === 'log') return native({ type: 'openDeployLog', sessionId: sid });
  else if (act === 'copyAndGo') {
    // Copy and Go: the install on the clipboard, then the row's own session, in that checkout, to paste it there.
    native({ type: 'copyInstall', sessionId: sid });
    return openSession(s);
  } else if (act === 'install' || act === 'back') {
    // Install First's second step, which asks before anything runs, showing what the install runs once the app has
    // looked; and Back from it.
    delete state.deployInstallChecks[d.folder];
    if (act === 'install') {
      state.deployInstall[d.folder] = c.key;
      native({ type: 'checkInstall', sessionId: sid });
    } else delete state.deployInstall[d.folder];
    state.shownAt['dcard:' + sid] = Date.now();
    return render();
  } else if (act === 'installNow') {
    // Only what the step showed, which the app checks is still what the install runs. The card isn't put away: once
    // the run starts it goes by itself; if the app refuses (an agent at work there), the row says why and the card is
    // still there, at its first step, for when it can; and if what it runs has changed, the step shows it again.
    const check = state.deployInstallChecks[d.folder];
    if (!check) return;
    delete state.stepNotes[sid];
    delete state.deployInstall[d.folder];
    state.deployPressed[d.folder] = Date.now();
    native({ type: 'installAndDeploy', sessionId: sid, words: check.words, hash: check.hash });
    return render();
  }
  else if (act === 'stop') native({ type: 'stopDeploy', sessionId: sid });
  else if (act === 'again') {
    delete state.stepNotes[sid];
    state.deployPressed[d.folder] = Date.now();
    native({ type: 'deploy', sessionId: sid });
  }
  state.deployShut[d.folder] = c.key;
  render();
}

// Deploy's menu (the app's: what it runs, changing or forgetting that, stopping a run, the log), below its button.
function deployMenu(button) {
  const r = button.getBoundingClientRect();
  native({ type: 'stepMenu', step: 'deploy', sessionId: button.dataset.deploy, x: r.left - 4, y: r.bottom + 4 });
}

// A right-click (or Control-click) on Deploy's button opens its menu, in place of WebKit's own, wherever its row is.
document.addEventListener('contextmenu', (e) => {
  const button = e.target.closest('.play[data-deploy]');
  if (!button) return;
  e.preventDefault();
  deployMenu(button);
});

// The set-up card for what Deploy runs, opened on a row: with the command saved for its project, or the one Whozmove
// suggests. `then` is 'deploy' when Deploy opened it (once confirmed, it deploys), 'save' when it's a change. `text`, when
// given, is the command to show in their place: the one just confirmed that macOS refused to save, and `refused` why,
// which the card says for as long as it's open, as the row's note goes after a few seconds.
function openSetup(sid, then, text, refused) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s || s.ask) return;  // a request waiting on the row comes first
  const deploy = deployFor(s, state.deploys);
  openingCard(sid, 'setup');
  const shown = typeof text === 'string' && text ? text : deploy.command || deploy.suggested || '';
  state.deploySetup[sid] = { step: 1, text: shown, then };
  if (typeof refused === 'string' && refused) state.deploySetup[sid].refused = refused;
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
    const up = f.run?.running && f.run.up;
    if (!up) delete state.deployUpSeen[folder];
    else if (state.deployUpSeen[folder]?.at !== up.at) {
      state.deployUpSeen[folder] = { at: up.at, seen: now - up.at < 10000 ? now : 0 };
    }
  }
  for (const [folder, f] of Object.entries(state.deploys.folders)) {
    const run = f.run;
    if (!run?.ok || run.running || state.deploySeen[folder]?.finishedAt === run.finishedAt) continue;
    state.deploySeen[folder] = { finishedAt: run.finishedAt, at: now - run.finishedAt < 10000 ? now : 0 };
  }
  if (!state.sliding && !state.composing) render();
};

// What Install First's install runs in a folder, as the app followed it (DeployInstallCheck in app/Deploys.m), for its
// card's second step; `again` when it changed under a press of Install and Deploy, so the step shows it again.
window.deployInstallChecked = (folder, check, again) => {
  state.deployInstallChecks[folder] = check;
  if (again) state.deployInstallAgain[folder] = true;
  render();
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

// Change Deploy Command… or Set Up Deploy…, in Deploy's menu: the set-up card opens on the row (openSetup); and again
// with the command just confirmed, and why, when macOS refused to save it.
window.openDeploySetup = (sid, then, text, refused) => openSetup(sid, then, text, refused);

// ---- What it plugs into ----

// Its button, while it's offered; when it isn't, what it showed is forgotten, so one that's back waits again before it
// takes a press, as the next steps do. It goes by the page's own clock (row.clock), which its press and animations are
// timed by.
core.rowLooks.push((row) => {
  row.deploy = rowDeploy(row.s);
  row.offer = deployOffer(row.s, row.kind, row.owner, row.deploy, row.clock);
  if (row.offer) state.shownAt['deploy:' + row.s.sessionId] ??= row.clock;
  else delete state.shownAt['deploy:' + row.s.sessionId];
  // Deploy's card for the folder: the app's, or else the run's own.
  if (row.deploy) {
    const seen = state.deployUpSeen[row.deploy.folder]?.seen || 0;
    row.deployCard = row.deploy.card
      || deployRunCard(row.deploy, row.clock, seen, state.deployShut[row.deploy.folder]);
  }
  // The address, while it shows: a press is taken once it's been shown a moment.
  if (row.offer?.look === 'up' && (!row.brief || row.tools)) state.shownAt['addr:' + row.s.sessionId] ??= row.clock;
  else delete state.shownAt['addr:' + row.s.sessionId];
});
// When the page first saw the row's build up (0 for one up before it loaded).
const upSeenOf = (row) => state.deployUpSeen[row.deploy.folder]?.seen || 0;
// At the end of the bottom line, after where the session runs: Deploy goes with the folder it puts in place, and a
// build that's up has its address between them. The button goes wherever the row's end does (a row shown briefly's
// note's end), and while the row asks something of you, only at the end of an ask to try, as its one action (askAct);
// the address stays on the bottom line, where it can still be pressed (a row shown briefly, but the row you're on, has
// it in the button's tip).
core.slots.placeStays.push((row) => (row.offer?.look === 'up' && (!row.brief || row.tools)
  ? deployAddressHTML(row.s, row.deploy, row.clock, upSeenOf(row)) : ''));
core.slots.placeEnd.push((row) => (row.offer
  ? deployHTML(row.s, row.deploy, row.offer, row.clock, upSeenOf(row)) : ''));
// An ask to try something has Deploy as its one action, at the ask's end, while it's offered (row.askWant).
core.slots.askAct.push((row) => (row.askWant === 'try' && row.offer
  ? deployHTML(row.s, row.deploy, row.offer, row.clock, upSeenOf(row)) : ''));
// The row's note, on a row with the button: what its folder's deploy has to say, unless Deploy's card says it. A row
// shows one card, the most pressing, so while another's in its place (a request, the set-up card), the note still says
// it.
const DEPLOY_CARD_ORDER = 31;
const deployCardShows = (row) => !!(row.offer && row.deployCard)
  && core.rowCards.every((card) => card.order >= DEPLOY_CARD_ORDER || !card.wants(row));
core.rowNotes.push((row) => (row.offer?.kept ? { text: keptNote(row.offer, base(row.deploy.folder)), quiet: true }
  : row.offer && !deployCardShows(row) ? deployNote(row.deploy, Date.now(), state.deployShut[row.deploy.folder])
  : null));
// The set-up card, after a request or the Compact card on the row; and after that, Deploy's card for its folder, when
// a press didn't run as it was or its run has something to say (deployCardHTML), on the row that has the button. The
// Deployed card says each checkout runs beside the others the first time a project's shows (deploySide), and while
// any card shows, the row's note leaves it to the card.
core.rowCards.push({
  name: 'setup', order: 30,
  wants: (row) => !!state.deploySetup[row.s.sessionId],
  html: (row) => setupHTML(row.s, state.deploySetup[row.s.sessionId], deployFor(row.s, state.deploys)),
}, {
  name: 'deployCard', order: DEPLOY_CARD_ORDER,
  wants: (row) => !!(row.offer && row.deployCard),
  html: (row) => {
    const c = row.deployCard;
    state.shownAt['dcard:' + row.s.sessionId] ??= Date.now();
    if (c.kind === 'ok') state.deploySide[row.deploy.key] ??= c.key;
    const folder = row.deploy.folder;
    // What it runs changed under Install and Deploy: its second step again, with what it runs now.
    if (state.deployInstallAgain[folder] && c.kind === 'packages') {
      delete state.deployInstallAgain[folder];
      state.deployInstall[folder] = c.key;
      state.shownAt['dcard:' + row.s.sessionId] = Date.now();
    }
    return deployCardHTML(row.s, c, row.deploy, c.kind === 'ok' && state.deploySide[row.deploy.key] === c.key,
                          state.deployInstall[folder] === c.key && (state.deployInstallChecks[folder] || true));
  },
  away: (row) => { delete state.shownAt['dcard:' + row.s.sessionId]; },
});
core.presses.push(['.play[data-deploy]', pressDeploy], ['.perm[data-setup]', pressSetup], ['.d-addr', pressAddress],
                  ['.perm[data-dstate]', pressCard]);
core.typing.push(['.d-cmd', (box) => {
  const setup = state.deploySetup[box.closest('.perm').dataset.setup];
  if (setup) setup.text = box.value;
  const next = box.closest('.perm').querySelector('.d-next');
  if (next) next.disabled = !box.value.trim();
}]);
core.pointerTargets.push('.play:not(.off)', '.play.keeps', '.play.kept', '.d-addr', '.d-link');
// When each folder's sessions last changed or built something, and which are at work in it, from the sessions listed.
core.beforeDraw.push((listed) => {
  state.folderWork = folderWork(listed);
  state.atWork = agentsAtWork(listed, state.kinds);
});
// A step's note (why a deploy couldn't start, say): a Deploy pressed there stops standing in for a run.
core.noted.push((s) => { delete state.deployPressed[folderOf(s)]; });
core.forgotten.keys.push('deploySetup');
core.forgotten.prefixes.push('setup', 'deploy', 'addr', 'dcard');

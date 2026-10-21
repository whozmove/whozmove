// The install module's part of the page, run outside the app by test.sh: what the line under the header says for each
// state the app sends, its button and its ×, and how a × holds until things change (install.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('What the line says');
const found = (state, more) => ({ state, since: 1000, ...more });
for (const state of ['added', 'notInApplications', 'noTools', 'installing', 'noCommand', 'removed', 'turnedOff',
                     'failed'])
  show(state, installLine(found(state), {}));
show('failed, with what Claude Code said', installLine(found('failed', { detail: 'Marketplace whozmove failed to '
  + 'load: cache-miss' }), {}));
show('failed, with a sentence of its own', installLine(found('failed', { detail: 'Claude Code took too long to '
  + 'answer.' }), {}));
show('failed, with nothing said', installLine(found('failed', { detail: '  ' }), {}));
show('a press under way: its button waits', installLine(found('removed', { busy: true }), {}));

section('No line');
for (const state of ['ready', 'updated', 'agentBuild', 'something new'])
  show(state, installLine(found(state), {}));
show('nothing found yet', installLine(null, {}));

section('Put away');
const awayFrom = (f, already = {}) => putAway(already, installLine(f, already));
const away = awayFrom(found('turnedOff'));
show('a × keeps the state, as the time it began', away);
show('…so the line stays away while it stays so', installLine(found('turnedOff'), away));
show('…and comes back once it has changed and come back', installLine(found('turnedOff', { since: 2000 }), away));
show('…other states still show', installLine(found('removed'), away));
show('a line with no × can\'t be put away', installLine(found('noTools'), awayFrom(found('noTools'))));
show('nothing to keep without a line', putAway(away, null));

section('Sessions open from before the hooks went in');
const open = (reload, state = 'ready') => found(state, { reload: { since: 500, waiting: 0, done: 0, total: 0,
                                                                  ...reload } });
show('just connected, three open', installLine(open({ open: 3, idle: 3 }, 'added'), {}));
show('just connected, one open', installLine(open({ open: 1, idle: 1 }, 'added'), {}));
show('just connected, all three at work', installLine(open({ open: 3, idle: 0 }, 'added'), {}));
show('later, two still to reload', installLine(open({ open: 2, idle: 2 }), {}));
show('later, one still to reload', installLine(open({ open: 1, idle: 1 }), {}));
show('later, one still to reload, at work', installLine(open({ open: 1, idle: 0 }), {}));
show('later, three still to reload, one idle', installLine(open({ open: 3, idle: 1 }), {}));
show('reloading them: 1 of 3 done', installLine(open({ open: 2, idle: 2, waiting: 2, done: 1, total: 3,
                                                       going: 'Release notes' }), {}));
show('reloading the one pressed, others still to reload', installLine(open({ open: 3, idle: 3, waiting: 1, total: 1,
                                                                            going: 'Release notes' }), {}));
show('all reloaded', installLine(open({ allSet: true, since: 900 }), {}));
const first = { sessionId: 's2', name: 'Pricing cards', command: '/reload-plugins', held: false };
const held = { ...first, command: '/reload-plugins --force', held: true };
show('one left for you, as Whozmove can\'t type into it', installLine(open({ open: 0, byHand: 1, first, done: 2,
                                                                             total: 2 }), {}));
show('three left for you', installLine(open({ open: 0, byHand: 3, first }), {}));
show('two left for you', installLine(open({ open: 0, byHand: 2, first }), {}));
show('one Claude Code held back', installLine(open({ open: 0, byHand: 1, first: held }), {}));
show('one left for you, two more the panel can reload', installLine(open({ open: 2, idle: 2, byHand: 1, first }), {}));
show('none open: the usual line', installLine(found('added'), {}));
const reloadAway = awayFrom(open({ open: 3, idle: 3 }, 'added'));
show('a × on it keeps the reload, and the Connected line it stood for', reloadAway);
show('…so neither shows', installLine(open({ open: 3, idle: 3 }, 'added'), reloadAway));
show('…nor while they reload', installLine(open({ open: 2, idle: 2, waiting: 2, done: 1, total: 3 }, 'added'),
                                          reloadAway));
show('all set, put away by itself: the Connected line stays away',
     installLine(found('added'), awayFrom(open({ allSet: true, since: 900 }, 'added'))));
show('a session needing it shows Reload on its row', reloadHTML({ s: { sessionId: 's1', reload: { state: 'needed' } } }));
show('one Whozmove can\'t type into says what to type in it, with Try Again', reloadHTML({ s: { sessionId: 's2', reload: {
  state: 'byHand', why: 'Another tab in this folder looks the same: reload it there', command: '/reload-plugins',
  held: false } } }));
show('one Claude Code held back says what takes it anyway', reloadHTML({ s: { sessionId: 's3', reload: {
  state: 'byHand', why: 'This reload changes MCP tools (notes). Run /reload-plugins --force to apply.',
  command: '/reload-plugins --force', held: true } } }));
show('…and once on its way, its note', [reloadNote({ reload: { state: 'waiting' } }),
                                        reloadNote({ reload: { state: 'reloading' } }), reloadNote({})]);

section('A newer Whozmove out');
const update = { version: '0.2.1', command: 'brew upgrade --cask whozmove/tap/whozmove' };
show('all set up: it says so, with the command to copy', installLine(found('ready', { update }), {}));
show('setting up needs you first: its line wins', installLine(found('noTools', { update }), {}));
show('…and the plugin turned off too', installLine(found('turnedOff', { update }), {}));
show('…but once that\'s put away, the new version shows', installLine(found('turnedOff', { update }),
                                                                     { turnedOff: 1000 }));
show('just connected: the Connected line first', installLine(found('added', { update }), {}));
const updateAway = awayFrom(found('ready', { update }));
show('a × keeps that version away', updateAway);
show('…so it stays away', installLine(found('ready', { update }), updateAway));
show('…and a newer one shows again', installLine(found('ready', { update: { ...update, version: '0.2.2' } }),
                                                 updateAway));
show('nothing newer: no line', installLine(found('ready'), {}));
show('Homebrew put it in, this copy still runs: Restart', installLine(found('ready', { update: { version: '0.2.1',
                                                                                                installed: true } }),
                                                                       {}));

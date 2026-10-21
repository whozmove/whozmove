// The panel's back's logic, run outside the app by modules/apps/tests/test.sh: what an app's page says of what macOS
// lets Whozmove do with it, what its cards show, and the apps' switches once one is pressed (apps.js). Nothing is
// drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the back page's scripts and the helpers below use

section('Permissions');
const app = (permission, more) => ({ id: 'com.example.terminal', name: 'Example Terminal', permission, switches: [],
                                     ...more });
const AUTOMATION = { kind: 'automation', use: 'Finds each session’s tab, and types into it' };
for (const state of ['allowed', 'denied', 'ask', 'closed', 'unknown', 'something else'])
  show(`automation, ${state}`, permissionView(app({ ...AUTOMATION, state })));
show('accessibility, allowed', permissionView(app({ kind: 'accessibility', use: 'Presses its buttons',
                                                   state: 'allowed' })));
show('accessibility, denied', permissionView(app({ kind: 'accessibility', state: 'denied' })));
show('nothing to allow', permissionView(app(null)));
show('a permission the page doesn’t know', permissionView(app({ kind: 'camera', state: 'allowed' })));

section('Cards');
const card = (more) => ({ key: 'tools', title: 'Apple’s command line developer tools', section: 'Developer tools',
                          said: 'Not installed', note: 'Git needs them.', ok: false, button: 'Install', busy: false,
                          ...more });
show('with its button', statusView(card()));
show('all’s well: its tick, and no button', statusView(card({ said: 'Installed', ok: true, button: undefined })));
show('a press under way: its button waits', statusView(card({ busy: true })));
show('under way with no button: nothing waits', statusView(card({ button: undefined, busy: true })));
show('no heading over it', statusView(card({ section: null })));
show('nothing more than its heading', statusView({ key: 'plugin', title: 'Whozmove’s plugin' }));
show('no heading: not drawn', statusView({ key: 'plugin' }));
show('nothing', statusView(null));

section('Switches');
const on = (apps) => apps && apps.map((a) => `${a.id}: ${a.switches.map((s) => `${s.key} ${s.on ? 'on' : 'off'}`)
  .join(', ')}`);
const apps = [
  { id: 'ghostty', switches: [{ key: 'startHere', on: true, group: 'startTerminal', enabled: true }] },
  { id: 'iterm2', switches: [{ key: 'startHere', on: false, group: 'startTerminal', enabled: true }] },
  { id: 'spotify', switches: [{ key: 'song', on: true, group: null, enabled: true },
                              { key: 'lyrics', on: false, group: null, enabled: true }] },
  { id: 'git', switches: [{ key: 'nextSteps', on: false, group: null, enabled: false },
                          { key: 'deploy', on: true, group: null, enabled: true }] },
];
show('turning lyrics on', on(afterPress(apps, 'spotify', 'lyrics')));
show('turning the song off', on(afterPress(apps, 'spotify', 'song')));
show('the other terminal picked: the first goes off', on(afterPress(apps, 'iterm2', 'startHere')));
show('the picked terminal pressed again: it stays', afterPress(apps, 'ghostty', 'startHere'));
show('Show Next Steps without Apple’s developer tools: nothing', afterPress(apps, 'git', 'nextSteps'));
show('Show Deploy, pressable while the next steps are off', on(afterPress(apps, 'git', 'deploy')));
show('a switch that isn’t there', afterPress(apps, 'spotify', 'volume'));
show('an app that isn’t there', afterPress(apps, 'zoom', 'song'));
show('the apps it was given are left as they were', on(apps));

section('A tile’s letter');
show('a name', initialOf('git'));
show('no name', initialOf(''));

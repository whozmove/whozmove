// The panel's back's logic, run outside the app by modules/apps/tests/test.sh: what an app's page says of what macOS
// lets Whozmove do with it, and the apps' switches once one is pressed (apps.js). Nothing is drawn.
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

section('Switches');
const on = (apps) => apps && apps.map((a) => `${a.id}: ${a.switches.map((s) => `${s.key} ${s.on ? 'on' : 'off'}`)
  .join(', ')}`);
const apps = [
  { id: 'ghostty', switches: [{ key: 'startHere', on: true, group: 'startTerminal', enabled: true }] },
  { id: 'iterm2', switches: [{ key: 'startHere', on: false, group: 'startTerminal', enabled: true }] },
  { id: 'spotify', switches: [{ key: 'song', on: true, group: null, enabled: true },
                              { key: 'lyrics', on: false, group: null, enabled: true }] },
  { id: 'git', switches: [{ key: 'nextSteps', on: false, group: null, enabled: true },
                          { key: 'deploy', on: true, group: null, enabled: false }] },
];
show('turning lyrics on', on(afterPress(apps, 'spotify', 'lyrics')));
show('turning the song off', on(afterPress(apps, 'spotify', 'song')));
show('the other terminal picked: the first goes off', on(afterPress(apps, 'iterm2', 'startHere')));
show('the picked terminal pressed again: it stays', afterPress(apps, 'ghostty', 'startHere'));
show('Show Deploy while the next steps are off: nothing', afterPress(apps, 'git', 'deploy'));
show('a switch that isn’t there', afterPress(apps, 'spotify', 'volume'));
show('an app that isn’t there', afterPress(apps, 'zoom', 'song'));
show('the apps it was given are left as they were', on(apps));

section('A tile’s letter');
show('a name', initialOf('git'));
show('no name', initialOf(''));

// What the panel's back shows of the apps, from what the app sends (app/AppsModule.m): what an app's permission says,
// and the apps' switches once one is pressed. Plain functions, checked by modules/apps/tests/test.sh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Where in System Settings ▸ Privacy & Security each permission is.
const PERMISSION_NAMES = { accessibility: 'Accessibility', automation: 'Automation' };

// What an app's page says of what macOS lets Whozmove do with it: the permission's name and what it's for, and how it
// stands (`state`): allowed; denied, offering System Settings, where it's changed; not asked about yet (Automation,
// which macOS asks about the first time); can't be told while the app isn't open (Automation again); or not checked
// yet, which says nothing. Null for an app with nothing to allow.
function permissionView(app) {
  const p = app.permission;
  if (!p || !PERMISSION_NAMES[p.kind]) return null;
  const state = ['allowed', 'denied', 'ask', 'closed'].includes(p.state) ? p.state : 'unknown';
  const said = { allowed: 'Allowed', denied: 'Not allowed', ask: 'Not asked yet', closed: `Open ${app.name} to check`,
                 unknown: '' }[state];
  // Denied, it says what to turn on in System Settings: Whozmove itself in Accessibility's list, or the app under
  // Whozmove in Automation's.
  const turnOn = p.kind === 'accessibility' ? 'Turn on Whozmove there.' : `Turn on ${app.name} under Whozmove there.`;
  const note = state === 'ask' ? 'macOS asks the first time Whozmove needs it.' : state === 'denied' ? turnOn : '';
  return { name: PERMISSION_NAMES[p.kind], use: p.use || '', state, said, note, settings: state === 'denied' };
}

// The apps after one of their switches is pressed: it turns on or off; one in a group (the terminal new conversations
// open in) turns the others in its group off, in any app, and pressed while it's on, it stays. Null when the press
// changes nothing: a switch that isn't there, can't be pressed now, or stays.
function afterPress(apps, appId, key) {
  const pressed = apps.find((a) => a.id === appId)?.switches.find((s) => s.key === key);
  if (!pressed || pressed.enabled === false || (pressed.group && pressed.on)) return null;
  return apps.map((a) => ({
    ...a,
    switches: a.switches.map((s) => a.id === appId && s.key === key ? { ...s, on: !s.on }
      : pressed.group && s.group === pressed.group ? { ...s, on: false } : s),
  }));
}

// The letter drawn on the tile of an app with no icon of its own.
const initialOf = (name) => (String(name || '').trim()[0] || '?').toUpperCase();

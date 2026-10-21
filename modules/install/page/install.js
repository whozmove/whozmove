// What the line under the header says while Whozmove sets itself up, for each state the app sends (setInstall, from
// the install module's app part): its words, its button and what a press of it asks the app, and whether it has a ×.
// Plain functions, checked by modules/install/tests/test.sh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each state's line. One without a × stays until things change: running from outside an Applications folder, which
// nothing here can put right; Apple's developer tools, which your sessions can't be followed without; and macOS's
// installer putting them in, which goes by itself. One that says all went well (`done`) has a tick before its words,
// and puts itself away a few seconds after it shows (install-line.js).
const INSTALL_LINES = {
  added: { text: 'Connected to Claude Code: sessions you start from now on show here in full.', close: true,
           done: true },
  notInApplications: { text: 'Move Whozmove into your Applications folder, then open it again, to finish setting it '
    + 'up.' },
  noTools: { text: "Install Apple's developer tools to see what each session is doing, and answer its requests "
    + 'here.', button: 'Install', action: 'tools' },
  installing: { text: "Waiting for Apple's developer tools to finish installing." },
  noCommand: { text: "Install Claude Code, or open Claude Desktop's Code tab once, to see your sessions here.",
               button: 'Get Claude Code', action: 'getAgent', close: true },
  removed: { text: "Add Whozmove's plugin back to see what each session is doing, and answer its requests here.",
             button: 'Add Back', action: 'addBack', close: true },
  turnedOff: { text: "Turn Whozmove's plugin back on to see what each session is doing, and answer its requests "
    + 'here.', button: 'Turn On', action: 'turnOn', close: true },
  failed: { text: "Couldn't connect to Claude Code, so sessions show only part of what they do.", button: 'Try Again',
            action: 'retry', close: true },
};

// The line for how things stand (`found`, as the app sends it: {state, detail, since, busy}), or null for none: none
// while all's well (ready, updated, an agent's own build), and none once you've put it away with its ×, which `away`
// keeps by state as the time that state began, so it comes back only once things have changed. `busy` while what a
// press set going is under way: its button waits; `done` when it says all went well.
function installLine(found, away) {
  const line = INSTALL_LINES[found?.state];
  if (!line || (line.close && found.since != null && away?.[found.state] === found.since)) return null;
  let text = line.text;
  if (found.state === 'failed' && String(found.detail || '').trim()) {
    const said = String(found.detail).trim();
    text = `Couldn't connect to Claude Code (${said.replace(/[.!?]+$/, '')}), so sessions show only part of what they `
      + 'do.';
  }
  return { text, button: line.button || null, action: line.action || null, close: !!line.close, done: !!line.done,
           busy: !!found.busy };
}

// Your × on the line: kept by state, as the time that state began, so it holds until things have changed.
function putAway(away, found) {
  return found?.state && found.since != null ? { ...away, [found.state]: found.since } : away;
}

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

// The sessions running since before the hooks went in, which show only part of what they do until they reload them
// (found.reload, while the hooks are in: Reloads' summary): how many, with Reload Them for the ones idle now (one at
// work is reloaded from its row once it's done, never queued to go in by itself later); while they reload, how far
// they've got; the ones left for you to reload in their tabs (`first` names the first, with the command to type, and
// whether Claude Code held its reload back), with Take me there; and once a press has reloaded the last of them, that
// all's well, which puts itself away as `added` does. It speaks in place of `added`'s line, and a × on it puts that
// away too.
function reloadLine(r, added) {
  if (!r || r.since == null) return null;
  if (r.allSet) return { text: 'All set: every open session shows here in full.', close: true, done: true,
                         key: 'reloaded' };
  if (r.waiting > 0) {
    const text = r.total > 1 ? `Reloading your open sessions: ${r.done} of ${r.total} done.`
      : `Reloading “${r.going || 'the session'}”.`;
    return { text, close: true, key: 'reload' };
  }
  const n = r.open, one = n === 1;
  if (n > 0) {
    const they = one ? "it's" : "they're", count = `${n} open session${one ? '' : 's'} show${one ? 's' : ''}`;
    const connected = `Connected to Claude Code. New sessions show here in full, and ${one ? 'the one' : `the ${n}`} `
      + `already open will once ${they} reloaded`;
    // All at work: each is reloaded from its row once it's done.
    if (!(r.idle > 0))
      return { text: added ? `${connected}, from ${one ? 'its row' : 'each one\'s row'} once ${they} done working.`
        : `${count} here only in part, and can be reloaded from ${one ? 'its row' : 'their rows'} once ${they} done `
          + 'working.', close: true, key: 'reload' };
    return { text: added ? `${connected}.` : `${count} here only in part until ${they} reloaded, which keeps `
      + `${one ? 'its' : 'their'} conversation as it is.`,
             button: one ? 'Reload It' : 'Reload Them', action: 'reloadAll', close: true, key: 'reload' };
  }
  const f = r.first;
  if (!(r.byHand > 0) || !f?.sessionId || !f.command) return null;
  const more = r.byHand - 1, name = `“${f.name || 'A session'}”`;
  const who = more ? `${name} and ${more} more session${more > 1 ? 's' : ''} show` : `${name} shows`;
  const text = f.held
    ? `${who} here only in part: Claude Code held the reload back, as the next message would read the whole `
      + `conversation again. Type ${f.command} in ${more ? 'each' : 'it'} to reload ${more ? 'them' : 'it'} anyway.`
    : `${who} here only in part, and Whozmove can't type into ${more ? 'them' : 'it'}: type ${f.command} in `
      + `${more ? 'each' : 'it'} to reload ${more ? 'them' : 'it'}.`;
  return { text, button: 'Take me there', action: 'open', session: f.sessionId, close: true, key: 'reload' };
}

// A newer Whozmove out (found.update, {version, command}: the app's Updates), once setting up needs nothing of you:
// the command that updates it, which its button puts on the clipboard (Whozmove never runs it), and a × that puts that
// version away, in Whozmove's folder, until a newer one.
function updateLine(u) {
  if (u?.installed && u.version)
    return { text: `Whozmove ${u.version} is installed: restart it to use it.`, button: 'Restart', action: 'restart',
             close: true, closeTitle: 'Hide until a newer version', done: false, busy: false, key: 'update',
             since: u.version, also: {}, version: u.version };
  if (!u?.version || !u.command) return null;
  return { text: `Whozmove ${u.version} is out. Run ${u.command} to update.`, button: 'Copy Command',
           action: 'copyUpgrade', close: true, closeTitle: 'Hide until a newer version', done: false, busy: false,
           key: 'update', since: u.version, also: {}, version: u.version };
}

// The line for how things stand (`found`, as the app sends it: {state, detail, since, busy, reload, update}), or null
// for none: none while all's well (ready, updated, an agent's own build), no session needs reloading and no new version
// is out, and none once you've put it away with its ×, which `away` keeps by the line's key (its state, the reload's,
// or the update's) as when it began (the update's, as its version), so it comes back only once things have changed.
// `busy` while what a press set going is under way: its button waits; `done` when it says all went well. `key` and
// `since` are what its × keeps, and `also` what else it puts away.
function installLine(found, away) {
  const reload = reloadLine(found?.reload, found?.state === 'added');
  if (reload && away?.[reload.key] !== found.reload.since)
    return { button: null, action: null, done: false, ...reload, busy: !!found.busy, since: found.reload.since,
             also: found.state === 'added' ? { added: found.since } : {} };
  const line = INSTALL_LINES[found?.state];
  const update = updateLine(found?.update);
  if (!line || (line.close && found.since != null && away?.[found.state] === found.since))
    return update && away?.update !== update.since ? update : null;
  let text = line.text;
  if (found.state === 'failed' && String(found.detail || '').trim()) {
    const said = String(found.detail).trim();
    text = `Couldn't connect to Claude Code (${said.replace(/[.!?]+$/, '')}), so sessions show only part of what they `
      + 'do.';
  }
  return { text, button: line.button || null, action: line.action || null, close: !!line.close, done: !!line.done,
           busy: !!found.busy, key: found.state, since: found.since, also: {} };
}

// Your × on the line: kept by its key, as the time it began, so it holds until things have changed.
function putAway(away, line) {
  return line?.key && line.since != null ? { ...away, ...line.also, [line.key]: line.since } : away;
}

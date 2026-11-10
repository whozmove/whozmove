// Where a ticket starts, in words: the guide the first time in a project, the line under the card's box saying where
// and why, and the warning where another ticket's conversation works. Plain functions, so the page cases check every
// state without the screen; routing.js draws them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A ticket's worktree, by its key: lower case, letters, digits, dots and dashes, starting with a letter or a digit,
// never ending in a dot, a dash or ".lock" (PAY-142 → pay-142). Nothing else of a key gets through: the card and git
// check the name again before a worktree is made.
function ticketWorktreeName(key) {
  let name = String(key ?? '').toLowerCase().replace(/[^a-z0-9.-]+/g, '-').replace(/\.{2,}/g, '.')
    .replace(/-{2,}/g, '-').replace(/^[^a-z0-9]+/, '').slice(0, 60).replace(/[.-]+$/, '');
  while (name.endsWith('.lock')) name = name.slice(0, -5).replace(/[.-]+$/, '');
  return name;
}

// The conversation already working a ticket, newest first among those listed (one still starting isn't), or null.
function ticketWorkedBy(sessions, ticket) {
  if (!ticket) return null;
  const same = (b) => b && b.key === ticket.key && b.tracker === ticket.tracker && (b.site || '') === (ticket.site || '');
  return sessions.filter((s) => !s.pending && same(s.ticket?.bound))
    .sort((a, b) => (b.lastPromptAt || 0) - (a.lastPromptAt || 0))[0] || null;
}

// Another ticket's conversation, still open, in the folder it would start in (`path`), or null.
function otherTicketIn(sessions, path, key) {
  if (!path) return null;
  return sessions.find((s) => !s.pending && s.status !== 'closed' && s.git?.root === path && s.ticket?.bound?.key
    && s.ticket.bound.key !== key) || null;
}

// Where in its project a conversation runs, as its row names it: its worktree, else its project.
const runsInName = (s) => s.git?.worktree || s.git?.branch || (s.cwd || '').split('/').pop();

// Where the routing part has the card start: { name } its own worktree, { path } a folder of the project's, { here }
// the project's own; null while there's nothing to say (no answer yet, outside git, a conversation working it, or
// a way it can't follow). `lit` is the guide's choice while it shows, `notNow` the guide put away (Not Now or Esc).
function routeWhere(answer, { lit, notNow, worked } = {}) {
  if (!answer?.git || worked) return null;
  const name = { name: ticketWorktreeName(answer.key) };
  if (notNow) return { here: true };
  if (!answer.way) {
    if (lit === 'folder') return { here: true };
    if (lit === 'field') {
      const f = answer.guide?.field;
      return f?.here ? { here: true } : f?.path ? { path: f.path } : name;
    }
    return name;
  }
  const p = answer.place;
  // While a field's option is read, nothing is proposed yet (Start waits: routing.js).
  if (p?.reading) return null;
  return !p || p.kind === 'own' ? name : p.kind === 'here' ? { here: true } : { path: p.folder };
}

// The guide, in the card's line's place: why a folder of its own, each way with where this ticket would open by it
// (the one lit picked), the field's way only where the project's tickets have one, and its foot: Start keeps the lit
// one, Not Now starts this one in the project's folder.
function routeGuideHTML(answer, lit, terminal, app) {
  const project = esc(answer.name), field = answer.guide?.field;
  const opt = (way, name, line, rec) => `<div class="rt-opt" data-way="${way}" role="radio" aria-checked="${lit === way}"`
    + ` aria-label="${esc(`${name}: ${line}`)}"><span class="tickbox round${lit === way ? ' on' : ''}"></span>`
    + `<span class="rt-words"><b>${esc(name)}${rec ? '<span class="tag new rt-rec">Recommended</span>' : ''}</b>`
    + `<i>${esc(line)}</i></span></div>`;
  // With no terminal, anywhere but the project's own folder starts there for now: worktrees start in a terminal.
  const forNow = `${answer.key} → ${answer.name} for now: worktrees start in a terminal`;
  // Lit while Claude Desktop is the card's app: the start goes to the terminal, and it says so.
  const inTerminal = lit === 'own' && app === 'desktop' && terminal ? ` · worktrees start in ${terminal}` : '';
  const own = terminal ? `${answer.key} → a new worktree, ${ticketWorktreeName(answer.key)}${inTerminal}` : forNow;
  const byField = !field ? '' : opt('field', `By its ${field.name} field`, !terminal && !field.here ? forNow
    : field.value ? `${answer.key} (${field.value}) → ${field.folder || 'its own worktree, until it has a folder'}`
    : `${answer.key} has no ${field.name} yet → its own worktree`);
  const looking = answer.guide?.reading ? `<div class="rt-why">Looking at ${project}’s fields…</div>` : '';
  return `<div class="c-under rt-guide" data-k="u" role="radiogroup" aria-label="How should ${project}’s tickets open?">`
    + `<div class="rt-head">How should ${project}’s tickets open?</div>`
    + '<div class="rt-why">Each ticket works best in a folder of its own (a worktree): two tickets never work in the '
    + 'same copy of your files.</div>'
    + opt('own', 'Its own worktree', own, true) + byField
    + opt('folder', `In ${answer.name} itself`, `${answer.key} → ${answer.name}, with your other work`)
    + looking
    + `<div class="rt-gfoot"><span>Start keeps this for ${project}’s tickets. You can change it in Settings ▸ Tickets.`
    + `</span><button class="button quiet small rt-notnow">Not Now</button></div></div>`;
}

// The line under the box once the way is set: where it starts and why, with one press back to the project's folder
// (or to set a field's folder, or to read the ticket again), from the answer and where the card would start now
// (`place`, the card's). { text, button: { act, title } } or null for the card's own line.
function routeLine(answer, place, worked) {
  const key = answer.key, project = answer.name;
  // With Claude Desktop picked on the card, a worktree starts in the terminal instead: the line says so, and Use
  // <project> says it starts in Claude Desktop there.
  const desktop = place?.app === 'desktop' && !!place.terminal;
  const back = { act: 'here', title: `Use ${project}`, tip: desktop ? `Starts in ${project}, in Claude Desktop` : '' };
  const inTerminal = desktop ? ` · worktrees start in ${place.terminal}` : '';
  if (worked) return { text: `${key} is being worked in ${runsInName(worked)}.`, button: { act: 'reopen', title: 'Go to It' } };
  if (!place || !answer.git) return null;
  const p = answer.place, f = answer.way?.field;
  const forNow = 'its own worktree for now';
  if (answer.way && !place.terminal && p?.kind !== 'here')
    return { text: `Worktrees start in a terminal, and there’s none here: ${key} starts in ${project}.` };
  if (p?.reading) return { text: `Reading ${key}’s ${f?.name || 'field'}…` };
  if (p?.why === 'noValue') return { text: `${key} has no ${f.name} yet: ${forNow}`, button: back };
  if (p?.why === 'noFolder') return { text: `${f.name} ${p.value?.name} has no folder yet: ${forNow}`,
                                      button: { act: 'setIt', title: 'Set It' } };
  if (p?.why === 'gone') return { text: `${p.where || 'Its folder'} has gone: ${forNow}`,
                                  button: { act: 'setIt', title: 'Set It' } };
  // Not read for want of a sign-in: Sign In, which reads it again once it's done; else Try Again.
  if (p?.why === 'unread') return { text: `${answer.problem?.why || `Couldn’t read ${key}’s ${f?.name}`}: ${forNow}`,
                                    button: answer.problem?.kind === 'signIn' ? { act: 'signIn', title: 'Sign In' }
                                      : { act: 'again', title: 'Try Again' } };
  if (p?.kind === 'here') return { text: `${key} starts in ${project}, with your other work.` };
  // The option's folder, said only once the card starts there: one the card can't start in gets the card's own line.
  if (p?.kind === 'folder') return place.path === p.folder
    ? { text: `${key}’s ${f?.name}, ${p.value?.name}: ${p.where}${inTerminal}`, button: back } : null;
  if (place.kind === 'open') return { text: `Carries on in ${place.name}: ${place.where}${inTerminal}`, button: back };
  if (place.kind === 'branch') return { text: `${place.name}, in a new folder${inTerminal}`, button: back };
  if (place.kind === 'new') return { text: `${key}’s own folder: ${place.where}${inTerminal}`, button: back };
  return null;
}

// The line drawn, in the card's line's place.
function routeLineHTML(line) {
  if (!line) return '';
  return `<div class="c-under rt-row" data-k="u"><span>${esc(line.text)}</span>`
    + (line.button ? `<button class="button quiet small rt-act" data-act="${esc(line.button.act)}"`
      + `${line.button.tip ? ` title="${esc(line.button.tip)}"` : ''}>`
      + `${esc(line.button.title)}</button>` : '') + '</div>';
}

// Another ticket's conversation where it would start: one notice, in the busy notice's place, its button giving this
// ticket its own worktree.
function routeWarn(other, key) {
  return other ? { text: `${other.ticket.bound.key} is being worked here. Two tickets in one folder can clash.`,
                   name: ticketWorktreeName(key) } : null;
}

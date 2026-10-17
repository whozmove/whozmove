// The card that asks, once, whether Whozmove may run the command a checkout's git config names for its extra stage
// (docs/reference/stages.md), and your answer.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Your answer to each row's card, { command, at }, until the checkout's next read shows it; and the command each card
// showed when last drawn, the only one its Allow answers (trustHTML).
moduleState({ trustAnswered: {}, trustShown: {} });

// Whether a command runs a file inside the checkout it runs in, as far as its words show: a path from there (./tool,
// scripts/stage.py, --config=./review.toml), a script named by itself (python3 stage.py), or a task runner that reads the
// checkout's own files (make, npm run …); not a path from the root, the home folder, a variable or a web address.
const SCRIPT_FILE = /^[\w.-]+\.(py|sh|bash|zsh|js|mjs|cjs|ts|rb|pl|php)$/i;
const TASK_RUNNER = /(^|[;&|(]\s*)((make|just|rake|task)\b|(npm|pnpm|yarn|bun)\s+run\b)/;
function runsRepoFile(command) {
  if (TASK_RUNNER.test(command.trim())) return true;
  return command.split(/\s+/).some((word) => {
    const w = word.replace(/^['"]+|['"]+$/g, '').replace(/^--?[\w-]+=/, '');
    return /^\.\.?\//.test(w) || SCRIPT_FILE.test(w)
      || (w.includes('/') && !/^[/~$-]/.test(w) && !/^[a-z]+:\/\//i.test(w));
  });
}

// The command a row's checkout asks to run for its extra stage while it waits for your answer, or null: only on the
// row that speaks for the checkout (`owner`), after any request waiting there, and not for 10s after you've answered,
// until the checkout's next read shows the answer.
function trustAsked(s, owner) {
  const ask = s.checkout?.stage?.ask, answered = state.trustAnswered[s.sessionId];
  if (!owner || !ask || s.ask) return null;
  return answered?.command === ask && Date.now() - answered.at < 10000 ? null : ask;
}

// The card. The command is shown in full, as Deploy's card shows one before it's saved, since Whozmove runs it each time
// it reads the checkout. One that runs a file inside the checkout gets a warning: an agent working there could change
// what that file does. Not now keeps the card away until the command changes. A card that's back (it's forgotten while
// it's away), or showing another command, waits again before it takes a press (justShown).
function trustHTML(s, command) {
  if (state.trustShown[s.sessionId] !== command) state.shownAt['trust:' + s.sessionId] = Date.now();
  state.trustShown[s.sessionId] = command;
  const folder = base((s.workGit || s.git)?.root || s.cwd);
  return `<div class="perm stage-trust" data-trust="${esc(s.sessionId)}">`
    + '<div class="q-top"><span class="q-head">Show this checkout\'s extra stage?</span></div>'
    + `<pre class="perm-detail">${esc(command)}</pre>`
    + `<div class="q-help">Its git config (whozmove.stage) asks Whozmove to run this in ${esc(folder)} each time it`
    + ' reads the checkout, and show what it prints between your edits and your commits.</div>'
    + (runsRepoFile(command)
      ? '<div class="c-note">It runs a file in this checkout, which an agent working here could change.</div>' : '')
    + '<div class="perm-actions"><button class="t-no">Not now</button>'
    + '<button class="perm-allow t-yes">Allow</button></div></div>';
}

// Allow lets Whozmove run the command, the one the rows say the checkout asks for (never text from the page); Not now
// keeps the card away until the command changes. A card only just shown doesn't take a press yet.
function pressTrust(card, e) {
  const sid = card.dataset.trust, button = e.target.closest('button');
  if (!button) return;
  e.preventDefault();
  if (justShown('trust:' + sid)) return;
  // The answer is for the command on the card, and only while it's still the one asked about: one that has changed
  // since is drawn first (and waits again), then answered.
  const command = state.last.sessions.find((x) => x.sessionId === sid)?.checkout?.stage?.ask;
  if (!command || command !== state.trustShown[sid]) return;
  state.trustAnswered[sid] = { command, at: Date.now() };
  native({ type: 'stageTrust', sessionId: sid, command, allow: button.classList.contains('t-yes') });
  render();
}

// The least pressing of a row's cards: it shows only when no other takes its place. While it's away, what it showed is
// forgotten, so it waits again when it's back.
core.rowCards.push({
  name: 'trust', order: 40,
  wants: (row) => !!(row.trust = trustAsked(row.s, row.owner)),
  html: (row) => trustHTML(row.s, row.trust),
  away(row) {
    delete state.shownAt['trust:' + row.s.sessionId];
    delete state.trustShown[row.s.sessionId];
  },
});
core.presses.push(['.perm[data-trust]', pressTrust]);
core.forgotten.keys.push('trustAnswered', 'trustShown');
core.forgotten.prefixes.push('trust');

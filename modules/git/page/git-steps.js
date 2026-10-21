// The next steps on a row's work line: an icon for each step its checkout has to take (stepsOf), its word coming in
// beside it as it's pointed at, a press asking the session's agent to take it; once a branch is pushed with no pull
// request, Create PR where the pull requests go, whose card says which branch it goes into, the repo's default picked,
// another to be picked there; and, while no pull request shows, how the last code review went while there's work to
// go, else, while commits wait to go, where the branch stands, there too.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The step pointed at ("sid:step"), drawn open as the list is drawn again, so its word doesn't come in afresh each
// second; and for Create PR's card: the branch picked for each session's pull request, the session whose card has its
// list of branches open, and the branches each session's repo has on GitHub, as the app last read them, with when.
moduleState({ hoverStep: null, prInto: {}, prPicking: null, prBranches: {} });

const STEP_ICONS = {
  // A commit: a dot on its line.
  commit: '<svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="2.9" fill="none" '
    + 'stroke="currentColor" stroke-width="1.6"/><path d="M1.5 8h3.6M10.9 8h3.6" stroke="currentColor" stroke-width="1.6" '
    + 'stroke-linecap="round"/></svg>',
  // Up, to GitHub.
  push: '<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M5 8.6V1.8M2.2 4.5 5 1.6 7.8 4.5" '
    + 'fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  // Up into the cloud: a branch that isn't there yet.
  publish: '<svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M4.6 12.5h7.1a3 3 0 0 0 .4-6 '
    + '4.1 4.1 0 0 0-7.9-1A3.5 3.5 0 0 0 4.6 12.5Z" fill="none" stroke="currentColor" stroke-width="1.3" '
    + 'stroke-linejoin="round"/><path d="M8 11V7.2M6.4 8.7 8 7l1.6 1.7" fill="none" stroke="currentColor" '
    + 'stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};
const PICKED_ICON = '<svg width="10" height="10" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5 6.4 12 13 4.5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
// A tick in a ring: a code review with nothing left to fix, in the colour of what's finished.
const REVIEWED_ICON = '<svg class="review-tick" width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><circle '
  + 'cx="8" cy="8" r="6.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M5.3 8.2 7.2 10.1 10.8 6.2" '
  + 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

// A step's icon on the work line, with the count of commits to push, and its word, which comes in beside it while it's
// pointed at. While the row's agent works or asks, the work line isn't there (workHTML).
function stepHTML(row, step) {
  const sid = row.s.sessionId, [word, tip] = stepWords(step, row.steps);
  const open = state.hoverStep === `${sid}:${step}` ? ' open' : '';
  const count = step === 'push' ? `<span class="step-n">${thousands(row.steps.push)}</span>` : '';
  return `<span class="step${open}" data-step="${step}" data-sid="${esc(sid)}"`
    + ` title="${esc(tip)}">${STEP_ICONS[step]}${count}`
    + `<span class="step-word">${word}</span></span>`;
}

// Where the pull requests go, while the branch has none: Create PR, whose card says into which branch.
function noPRHTML(row) {
  if (!row.steps?.pr) return '';
  return `<div class="nopr" data-pr-for="${esc(row.s.sessionId)}">${PR_ICON}<span class="pt">No pull request</span>`
    + '<span class="create-pr">Create PR</span></div>';
}

// Where the pull requests go, while none shows and Create PR isn't offered, and the work has a step still to take: how
// the checkout's last code review went (reviewOf, reviewWords), uncommitted changes and all, as that's when it matters
// most; else, while the branch has commits to push or publish, where it stands, in git's words (outgoingWords), which
// pressed opens those commits, in the changes view's Outgoing. With nothing left uncommitted, the numbers that open the
// changes view aren't there, so the review opens those commits too; otherwise a press on it is the row's.
function outgoingHTML(row) {
  if (!row.steps || row.steps.pr || shownPRs(row.s).length) return '';
  const review = reviewOf(row.s, state.last.sessions);
  if (review) {
    const [word, left, tip, done] = reviewWords(review);
    const opens = !row.steps.commit && (row.steps.push || row.steps.publish);
    const press = opens ? ` outgoing" data-outgoing="${esc(row.s.sessionId)}` : '';
    return `<div class="nopr review${press}" title="${esc(opens ? `${tip}. See the commits not on GitHub yet` : tip)}">`
      + `${done ? REVIEWED_ICON : ''}<span class="pt">${esc(word)}</span>`
      + `${left ? `<span class="out-n">${esc(left)}</span>` : ''}</div>`;
  }
  const words = outgoingWords(row.s.checkout, row.steps);
  if (!words) return '';
  return `<div class="nopr outgoing" data-outgoing="${esc(row.s.sessionId)}" title="See the commits not on GitHub yet">`
    + `<span class="pt">${esc(words[0])}</span><span class="out-n">${words[1]}</span></div>`;
}

// Create PR's card: the branch it goes into, the repo's default to begin with; pressed, the branches GitHub's copy has,
// as the app read them, to pick another; then Create PR and Create Draft PR.
function createPRCardHTML(s, steps) {
  const sid = s.sessionId, known = state.prBranches[sid];
  const base = known?.base ?? steps.pr.into, into = state.prInto[sid] ?? base;
  const branch = (s.workGit || s.git)?.branch || '';
  const names = known?.branches && [...new Set([base, ...known.branches].filter(Boolean))].filter((b) => b !== branch);
  const list = state.prPicking !== sid ? ''
    : `<div class="cp-list">${names ? names.map((b) => `<button class="cp-opt${b === into ? ' on' : ''}"`
        + ` data-act="into:${esc(b)}"><span class="cp-tick">${PICKED_ICON}</span>${esc(b)}`
        + `${b === base ? '<i>default</i>' : ''}</button>`).join('')
        : '<div class="cp-wait">Reading the branches on GitHub…</div>'}</div>`;
  return '<div class="cp-head">Create a pull request</div>'
    + `<div class="cp-into"><span>${esc(branch)} into</span><button class="cp-pick" data-act="pick">`
    + `${esc(into || 'its default branch')}${CHEVRON_ICON}</button></div>${list}`
    + '<div class="st-steps"><button class="st-step" data-act="pr">Create PR</button>'
    + '<button class="st-step" data-act="draftPR">Create Draft PR</button></div>'
    + '<div class="cp-hint">Into the repo\'s default branch, unless you pick another.</div>';
}

// The branches GitHub's copy of a session's repo has, as the app read them for Create PR's card ({base, branches}).
window.setPRBranches = (sid, known) => {
  state.prBranches[sid] = { ...known, at: Date.now() };
  syncHover();  // the card, drawn again with them if it's up
};

// ---- What it plugs into ----

// Its steps, worked out first. Gone, it's forgotten when they were first shown, so steps that are back wait again
// before they take a press.
core.rowLooks.push((row) => {
  row.steps = stepsOf(row.s, row.owner);
  if (row.steps) state.shownAt['steps:' + row.s.sessionId] ??= Date.now();
  else delete state.shownAt['steps:' + row.s.sessionId];
});
// Create PR first where the pull requests go (prs.js's come after it), then the review or where the branch stands; the
// steps after the numbers.
core.slots.workStart.push(noPRHTML, outgoingHTML);
core.slots.steps.push((row) => (row.steps ? ['commit', 'push', 'publish'].filter((step) => row.steps[step])
  .map((step) => stepHTML(row, step)).join('') : ''));
// A step pressed: the app asks the agent, once it has checked the step is still there to take and nothing waits.
core.presses.push(['.step[data-step]', (el, e) => {
  e.preventDefault();
  if (!justShown('steps:' + el.dataset.sid)) native({ type: 'gitStep', sessionId: el.dataset.sid, step: el.dataset.step });
}]);
// Where the branch stands, pressed: the changes view on its commits, as the numbers open it on what isn't committed.
core.presses.push(['.outgoing[data-outgoing]', (el, e) => {
  e.preventDefault();
  if (!justShown('steps:' + el.dataset.outgoing)) toggleReader(el.dataset.outgoing, null, 'changes', 'outgoing');
}]);
core.pointerTargets.push('.step[data-step]', '.nopr[data-pr-for]', '.outgoing[data-outgoing]');
core.cards.push({
  selector: '.nopr[data-pr-for]',
  key: (el) => 'pr-create:' + el.dataset.prFor,
  html(el) {
    const s = state.last.sessions.find((x) => x.sessionId === el.dataset.prFor);
    const steps = s && stepsOf(s, state.switches.nextSteps && state.owners.has(s.sessionId));
    return steps?.pr ? createPRCardHTML(s, steps) : '';
  },
  // Picking a branch keeps the card up, drawn again; Create PR asks the agent, into the branch picked, and its row
  // stays where it is meanwhile.
  press(key, act) {
    const sid = key.slice('pr-create:'.length);
    if (act === 'pick') { state.prPicking = state.prPicking === sid ? null : sid; return true; }
    if (act.startsWith('into:')) { state.prInto[sid] = act.slice(5); state.prPicking = null; return true; }
    if (act === 'pr' || act === 'draftPR') {
      keepInPlace(sid);
      native({ type: 'gitStep', sessionId: sid, step: act, ...(state.prInto[sid] ? { into: state.prInto[sid] } : {}) });
    }
    return false;
  },
});
// A step pointed at opens, its word coming in; Create PR pointed at has the branches asked for (again after a minute),
// and its card's list folds once the pointer has left both.
core.pointerWatchers.push((el) => {
  const step = el?.closest('.step[data-step]');
  state.hoverStep = step ? `${step.dataset.sid}:${step.dataset.step}` : null;
  for (const s of document.querySelectorAll('.step[data-step]'))
    s.classList.toggle('open', `${s.dataset.sid}:${s.dataset.step}` === state.hoverStep);
  const sid = el?.closest('.nopr[data-pr-for]')?.dataset.prFor;
  if (sid && !(Date.now() - (state.prBranches[sid]?.asked || 0) < 60000)) {
    state.prBranches[sid] = { ...state.prBranches[sid], asked: Date.now() };
    native({ type: 'prBranches', sessionId: sid });
  }
  if (!sid && !el?.closest('#card')) state.prPicking = null;
});
core.forgotten.keys.push('prInto', 'prBranches');
core.forgotten.prefixes.push('steps');

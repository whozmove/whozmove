// The panel page's logic, run outside the app by tests/panel.sh: which section, label and colour each sample
// session gets, how rows sort, and the HTML of sample rows. Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Stand-ins for what the page touches when it loads.
var window = this;
const element = () => ({
  addEventListener() {}, style: {}, dataset: {}, hidden: true,
  classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
  querySelector() { return null; }, querySelectorAll() { return []; },
});
var document = {
  body: element(), getElementById: element, addEventListener() {}, activeElement: null,
  querySelector: element, querySelectorAll() { return []; },
};
var matchMedia = () => ({ matches: true });
var performance = { now: () => 0 };
var requestAnimationFrame = () => {};

arguments.forEach((file) => load(file));  // the page's scripts, in the order the page loads them

// A fixed "now", so every time reads the same on every run.
const NOW = 2e12;
const min = (n) => NOW - n * 60000;
const show = (name, value) => print(`${name}: ${typeof value === 'string' ? value : JSON.stringify(value)}`);
const section = (title) => print(`\n== ${title}`);
const session = (fields) => Object.assign({
  sessionId: 's', name: 'demo', cwd: '/work/app', status: 'idle', statusUpdatedAt: min(60), entrypoint: 'cli',
  pid: 100, git: { branch: 'main', root: '/work/app' }, prs: [], agent: {},
}, fields);

section('Sections, grouped by status');
const reply = { lastPrompt: 'fix it', lastPromptAt: min(6), lastReply: 'Fixed.', lastReplyAt: min(5) };
const byStatus = { groupBy: 'status', current: null, seen: {} };
const openedR2 = { ...byStatus, seen: { r2: min(1) } };
show('a request waiting', classify(session({ ask: { id: 'a', tool: 'Bash', input: {} } }), NOW, byStatus));
show('Claude waiting on you', classify(session({ status: 'waiting' }), NOW, byStatus));
show('working', classify(session({ status: 'busy' }), NOW, byStatus));
show('replied 5 min ago, not opened', classify(session({ ...reply, sessionId: 'r1' }), NOW, byStatus));
show('replied, opened here since', classify(session({ ...reply, sessionId: 'r2' }), NOW, openedR2));
show('replied, open in Claude since',
  classify(session({ ...reply, sessionId: 'r3', lastFocusedAt: min(1) }), NOW, byStatus));
show('replied and opened, but the one you are on',
  classify(session({ ...reply, sessionId: 'r2' }), NOW, { ...openedR2, current: 'r2' }));
show('replied 40 min ago', classify(session({ ...reply, lastPromptAt: min(41), lastReplyAt: min(40) }), NOW, byStatus));

section('Sections, grouped by activity');
const byActivity = { groupBy: 'activity', current: null, seen: { r4: min(1) } };
show('replied 40 min ago, opened',
  classify(session({ ...reply, sessionId: 'r4', lastPromptAt: min(41), lastReplyAt: min(40) }), NOW, byActivity));
show('replied 2 h ago',
  classify(session({ ...reply, lastPromptAt: min(121), lastReplyAt: min(120) }), NOW, byActivity));

section('Sorting');
const since = (t) => `now-${Math.round((NOW - t) / 60000)}m`;
show('working, your message newer than its reply',
  since(sortKey(session({ lastPromptAt: min(3), lastReplyAt: min(9), statusUpdatedAt: min(1) }), 'busy')));
show('working, no new message',
  since(sortKey(session({ lastPromptAt: min(9), lastReplyAt: min(8), statusUpdatedAt: min(2) }), 'busy')));
show('idle, by its newest message',
  since(sortKey(session({ lastPromptAt: min(30), lastReplyAt: min(20), messageAt: min(15) }), 'idle')));

section('A new turn held steady');
const fresh = { statusUpdatedAt: NOW - 1000 };
show('says working, but its message is older and replied',
  steady(session({ ...fresh, status: 'busy', lastPromptAt: NOW - 10000, lastReplyAt: NOW - 5000 }), NOW).status);
show('says idle, but a new message is waiting for a reply',
  steady(session({ ...fresh, status: 'idle', lastPromptAt: NOW - 500, lastReplyAt: NOW - 60000 }), NOW).status);
show('changed over 3 s ago',
  steady(session({ status: 'idle', statusUpdatedAt: NOW - 5000, lastPromptAt: NOW - 500 }), NOW).status);

section("Current action: label and colour (the README's table)");
const pr = (fields) => Object.assign({ url: 'https://github.com/e/app/pull/1', number: 1, state: 'OPEN',
                                       isDraft: false, review: '', checks: 'passing' }, fields);
const actions = [
  ['In development', { outcome: 'Implemented', checkout: { changes: 2 } }],
  ['Ready to commit', { outcome: 'Tested', checkout: { changes: 2 } }],
  ['Committed, not pushed', { outcome: 'Committed', checkout: { changes: 0, ahead: 1 } }],
  ['Live in prod', { outcome: 'Deployed' }],
  ['On staging', { outcome: 'On staging' }],
  ['Merged this turn', { outcome: 'Merged' }],
  ['CI failing', { prs: [pr({ checks: 'failing' })] }],
  ['Changes requested', { prs: [pr({ review: 'CHANGES_REQUESTED' })] }],
  ['CI running', { prs: [pr({ checks: 'running' })] }],
  ['Draft PR', { prs: [pr({ isDraft: true })] }],
  ['Approved', { prs: [pr({ review: 'APPROVED' })] }],
  ['In review', { prs: [pr({ review: 'REVIEW_REQUIRED' })] }],
  ['In review, PR just raised', { outcome: 'PR raised' }],
  ["the branch's PR, in a worktree",
   { git: { branch: 'f', root: '/work/app-f', worktree: 'app-f' }, checkout: { pr: pr({ checks: 'failing' }) } }],
  ['Review posted', { outcome: 'Reviewed' }],
  ['Exploring', { outcome: 'Researched' }],
  ['Planning', { outcome: 'Planned' }],
  ['Merged, by its PR', { outcome: 'Answered', prs: [pr({ state: 'MERGED' })] }],
  ['Pushed, no PR', { outcome: 'Pushed' }],
  ['Committed, branch tracks a remote', { outcome: 'Committed', checkout: { upstream: true } }],
  ['Committed, a remote but no tracking', { outcome: 'Committed', checkout: { remotes: 1 } }],
  ['Committed, no remote', { outcome: 'Committed', checkout: { remotes: 0 } }],
  ['Done', { outcome: 'Answered' }],
  ['Done, Claude says completed', { summaryStatus: 'completed' }],
  ['nothing to say', {}],
  ['Waiting on you', { summaryStatus: 'blocked' }],
  ['blocked, Ready to commit stays', { summaryStatus: 'blocked', outcome: 'Tested', checkout: { changes: 1 } }],
  ['blocked, CI failing stays urgent', { summaryStatus: 'blocked', prs: [pr({ checks: 'failing' })] }],
  ["a chat in a busy checkout doesn't take its state", { outcome: 'Researched', checkout: { changes: 3 } }],
  ['a worktree owns its checkout',
   { outcome: 'Researched', git: { branch: 'f', root: '/work/app-f', worktree: 'app-f' }, checkout: { changes: 3 } }],
];
for (const [name, fields] of actions) show(name, currentAction(session(fields)));
show('the label as drawn', stageHTML(session({ outcome: 'Tested', checkout: { changes: 2 } }), 'idle'));
show('no label while working', stageHTML(session({ outcome: 'Tested' }), 'busy'));

section('What the work has been through');
const ready = { outcome: 'Tested', checkout: { changes: 1 }, workSteps: ['Built', 'Tested'] };
show('built and tested', proofHTML(session(ready), 'idle'));
show('audit, before fixing', proofHTML(session({ ...ready, audit: { found: 15, left: 15, settled: false } }), 'idle'));
show('audit, one left', proofHTML(session({ ...ready, audit: { found: 15, left: 1, settled: true } }), 'idle'));
show('audit, all settled', proofHTML(session({ ...ready, audit: { found: 15, left: 0, settled: true } }), 'idle'));
show('audit, nothing found', proofHTML(session({ ...ready, audit: { found: 0, left: 0, settled: false } }), 'idle'));
show('nothing while working', proofHTML(session(ready), 'busy'));
show('nothing beside a vague state', proofHTML(session({ outcome: 'Answered', workSteps: ['Tested'] }), 'idle'));

section('Details line');
for (const id of ['claude-opus-5-5', 'claude-sonnet-5-5[1m]', 'claude-haiku-5-5', 'claude-fable-5-1', 'claude-opus-5',
                  'other-model'])
  show(`model name of ${id}`, modelName(id));
show('context window, Opus 5.5', contextWindow('claude-opus-5-5', 1000));
show('context window, Sonnet 5.5', contextWindow('claude-sonnet-5-5', 1000));
show('context window, Sonnet 5.5 [1m]', contextWindow('claude-sonnet-5-5[1m]', 1000));
show('context window, Sonnet 5.5 past 200k', contextWindow('claude-sonnet-5-5', 250000));
show('auto-compact at, 1M window', compactLimit({ model: 'claude-opus-5-5', tokens: 1000 }));
show('auto-compact at, your own setting',
  compactLimit({ model: 'claude-sonnet-5-5', tokens: 1000, compactWindow: 150000 }));
show('auto-compact at, 200k window', compactLimit({ model: 'claude-sonnet-5-5', tokens: 1000 }));
for (const n of [427000, 1000000, 1500000]) show(`tokens ${n}`, kTokens(n));
for (const s of [5, 45, 300, 3 * 3600, 2 * 86400]) show(`ago ${s}s`, ago(s * 1000));
for (const s of [12, 76, 3780]) show(`elapsed ${s}s`, elapsed(s * 1000));
const ringColour = (agent) => (/color:([^;]+);/.exec(contextRing(session({ agent })) || '') || [])[1];
show('ring colour, 10% used', ringColour({ model: 'claude-opus-5-5', tokens: 100000 }));
show('ring colour, 70% used', ringColour({ model: 'claude-sonnet-5-5', tokens: 140000 }));
show('ring colour, 90% used', ringColour({ model: 'claude-sonnet-5-5', tokens: 180000 }));

section('Projects');
show('a worktree counts toward its repo', projectOf(session({
  git: { branch: 'f', root: '/work/app-f', worktree: 'app-f', worktreeOf: 'app', mainRoot: '/work/app' } })));
show("Claude Desktop's scratch conversations",
  projectOf(session({ cwd: '/Users/x/Library/Application Support/Claude/scratch-workspaces/abc', git: null })));
show('a repo', projectOf(session({ cwd: '/work/app/src', git: { branch: 'main', root: '/work/app' } })));
show('outside git', projectOf(session({ cwd: '/work/notes', git: null })));

section('HTML of sample rows');
const rows = [
  ['a command waiting for your OK', session({ sessionId: 'p1', status: 'waiting',
    ask: { id: 'a1', tool: 'Bash', input: { command: 'npm test', description: 'Run the tests' }, truncated: false } })],
  ['an edit waiting for your OK', session({ sessionId: 'p2', ask: { id: 'a2', tool: 'Edit',
    input: { file_path: '/work/app/a.ts', old_string: 'let x = 1;', new_string: 'const x = 1;' },
    truncated: false } })],
  ['a write too long to show in full', session({ sessionId: 'p3', ask: { id: 'a3', tool: 'Write',
    input: { file_path: '/work/app/big.txt', content: 'x\n…' }, truncated: true } })],
  ["Claude's questions", session({ sessionId: 'p4', ask: { id: 'a4', tool: 'AskUserQuestion', input: { questions: [
    { question: 'Which database?', header: 'Database',
      options: [{ label: 'Postgres', description: 'the usual' }, { label: 'SQLite' }] },
    { question: 'Name it?', kind: 'text' }] }, truncated: false } })],
  ['working', session({ sessionId: 'w1', status: 'busy', statusUpdatedAt: min(2), lastPrompt: 'run the suite',
    lastPromptAt: min(2), activity: 'Run the tests',
    agent: { model: 'claude-opus-5-5', effort: 'high', mode: 'acceptEdits', tokens: 120000 } })],
  ['your turn, with PRs, a worktree and an audit', session({ sessionId: 't1', ...reply, outcome: 'Tested',
    workSteps: ['Built', 'Tested'], audit: { found: 3, left: 1, settled: true }, checkout: { changes: 1 },
    git: { branch: 'feature', root: '/work/app-f', worktree: 'app-f', worktreeOf: 'app', mainRoot: '/work/app' },
    prs: [pr({ title: 'Fix the tests', repo: 'e/app' }),
          pr({ url: 'https://github.com/e/app/pull/2', number: 2, isDraft: true, title: 'Draft' })],
    agent: { model: 'claude-sonnet-5-5', effort: 'medium', mode: 'bypassPermissions', tokens: 150000 } })],
  ['a closed Claude Desktop conversation, open in Claude', session({ sessionId: 'd1', status: 'closed',
    entrypoint: 'claude-desktop', focused: true, name: 'Desk chat', pid: 0, lastReply: 'Done.', lastReplyAt: min(300),
    lastPromptAt: min(301), outcome: 'Answered', git: null, cwd: '/work/notes' })],
];
for (const [name, s] of rows) print(`-- ${name}\n${rowHTML(s, classify(s, NOW, view()), NOW)}`);
state.compactOpen.c1 = true;
const compacting = session({ sessionId: 'c1', agent: { model: 'claude-opus-5-5', tokens: 900000 } });
print(`-- the Compact card open\n${rowHTML(compacting, classify(compacting, NOW, view()), NOW)}`);
delete state.compactOpen.c1;

section('HTML of projects');
state.groupBy = 'project';
state.closedProjects['/work/other'] = true;
print(projectsHTML([
  session({ sessionId: 'g1', ...reply }),
  session({ sessionId: 'g2', status: 'busy', lastPromptAt: min(1) }),
  session({ sessionId: 'g3', cwd: '/work/other', git: { branch: 'main', root: '/work/other' }, outcome: 'Answered',
    lastReplyAt: min(500) }),
], NOW));
state.groupBy = 'status';

section('Command cards');
// Allow once allows the command exactly as asked, so how it would run is in the card's title.
const commandTitle = (input) => /class="perm-title">([^<]*)</.exec(askHTML({ id: 'k', tool: 'Bash', input }))[1];
show('a command', commandTitle({ command: 'make' }));
show('in the background', commandTitle({ command: 'make', run_in_background: true }));
show('outside the sandbox', commandTitle({ command: 'make', dangerouslyDisableSandbox: true }));
show('both', commandTitle({ command: 'make', run_in_background: true, dangerouslyDisableSandbox: true }));

section('What the page forgets');
// forgetGone works from the page's own clock.
const earlier = (ms) => Date.now() - ms;
Object.assign(state, {
  loadedAt: earlier(5 * 60000),
  seen: { listed: earlier(3600000), endedLongAgo: earlier(3600000), endedJustNow: earlier(3600000),
          readRecently: earlier(60000) },
  listedAt: { endedJustNow: earlier(10000), askJustAnswered: earlier(10000) },
  quiz: { askWaiting: {}, askJustAnswered: {}, askAnsweredLongAgo: {} },
  compactOpen: { listed: true, endedLongAgo: true },
  shownAt: { askWaiting: earlier(1000), 'compact:endedLongAgo': earlier(600000) },
});
forgetGone([session({ sessionId: 'listed', ask: { id: 'askWaiting', tool: 'Bash', input: {} } })]);
show('what you read, kept', Object.keys(state.seen).sort());
show('question state, kept', Object.keys(state.quiz).sort());
show('Compact cards, kept', Object.keys(state.compactOpen).sort());
show('when cards first showed, kept', Object.keys(state.shownAt).sort());

// The panel page's logic, run outside the app by tests/panel.sh: which section, label and colour each sample
// session gets, how rows sort, and the HTML of sample rows. Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

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
show("a terminal session that's the one you're on says where it's open",
     /title="Open in your terminal now"/.test(rowHTML(session({ sessionId: 'f1', focused: true }), 'idle', NOW)));
state.opening = { sessionId: 'd2', at: NOW };
show('a Claude Desktop conversation just clicked is the only one marked, not the terminal session you were on',
     [session({ sessionId: 'd2', entrypoint: 'claude-desktop' }), session({ sessionId: 'f1', focused: true })]
       .map((s) => openedNow(s).focused));
state.opening = null;

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

section('Tool cards');
// Any other tool's input, field by field as Claude's own prompt lists it: the shortest first, a text with its line
// breaks, a list of texts one to a line, anything else as JSON. With no input there's no box, just the title.
print(askHTML({ id: 'w', tool: 'mcp__charts__draw_chart', input: {
  chart_code: '<style>\n.bars { display: flex; gap: 6px; }\n</style>\n<div class="bars"></div>',
  title: 'sales_by_month', status_notes: ['Gathering the numbers', 'Drawing the bars'] } }));
print(askHTML({ id: 'e', tool: 'mcp__planner__add_event', input: {
  alerts: { minutesBefore: 10 }, title: 'Planning call', minutes: 30, notifyGuests: false, guests: [],
  room: null } }));
print(askHTML({ id: 'n', tool: 'mcp__server__list_things', input: {} }));

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
  shownAt: { askWaiting: earlier(1000), 'compact:endedLongAgo': earlier(600000), 'island:listed': earlier(1000),
             'trust:endedLongAgo': earlier(600000), 'steps:listed': earlier(500), 'steps:endedLongAgo': earlier(600000) },
  trustAnswered: { listed: { command: 'x', at: earlier(1000) }, endedLongAgo: { command: 'x', at: earlier(600000) } },
});
forgetGone([session({ sessionId: 'listed', ask: { id: 'askWaiting', tool: 'Bash', input: {} } })]);
show('what you read, kept', Object.keys(state.seen).sort());
show('question state, kept', Object.keys(state.quiz).sort());
show('Compact cards, kept', Object.keys(state.compactOpen).sort());
show('when cards first showed, kept', Object.keys(state.shownAt).sort());
show('answers about extra stages, kept', Object.keys(state.trustAnswered).sort());
state.trustAnswered = {};

section('The running build, in the header');
const buildOf = (fields) => Object.assign({ root: '/work/app', branch: 'main', commit: 'abc1234def', changes: false,
                                           builtAt: min(2) }, fields);
for (const [name, fields] of [['a worktree', { worktree: 'app-fix', branch: 'fix-hover' }], ['a branch', {}],
                              ['a detached commit', { branch: undefined, detached: 'abc1234' }],
                              ['outside git', { branch: undefined, commit: undefined, root: '/work/tool' }]])
  show(`named, from ${name}`, buildLabel(buildOf(fields)));
show('the header, two minutes after the build', headerBuild(buildOf({ worktree: 'app-fix' }), NOW));
show('the header, just built', headerBuild(buildOf({ builtAt: NOW - 3000 }), NOW));

section('Deploy');
const fixHover = { branch: 'fix-hover', root: '/work/app-fix', worktree: 'app-fix', worktreeOf: 'app',
                   mainRoot: '/work/app' };
show('a worktree: its project, and the folder it deploys from',
  [projectKey(session({ git: fixHover })), folderOf(session({ git: fixHover }))]);
show('outside git: the folder is both', [projectKey(session({ git: null, cwd: '/work/notes' })),
                                         folderOf(session({ git: null, cwd: '/work/notes' }))]);
show('what a worktree session knows', deployFor(session({ git: fixHover }), {
  projects: { '/work/app': { command: 'make install' } },
  folders: { '/work/app-fix': { suggested: 'make install', at: min(30) } } }));
const built = { outcome: 'Built', outcomeAt: min(5), builtAt: min(5) };
const editedHere = (at, fields) => ({ workRoot: '/work/app', editedAt: at, ...fields });
const due = (fields, d) => deployDue(session(fields), d);
show('due: built since the last deploy', due(built, { command: 'x', at: min(30) }));
show('due: files edited since the last deploy, though the turn ended committing',
  due(editedHere(min(5), { outcome: 'Committed', outcomeAt: min(2) }), { command: 'x', at: min(30) }));
show('not due: committed since, with nothing edited after the last deploy',
  due(editedHere(min(40), { outcome: 'Committed', outcomeAt: min(2) }), { command: 'x', at: min(30) }));
show('not due: a turn that only ran the tests',
  due({ outcome: 'Tested', outcomeAt: min(2) }, { command: 'x', at: min(30) }));
show('due: an older hook (no time noted): the end of its last turn that changed or built something',
  due({ outcome: 'Implemented', outcomeAt: min(5), workRoot: '/work/app' }, { command: 'x', at: min(30) }));
show('…but not a turn of its that only committed',
  due({ outcome: 'Committed', outcomeAt: min(5), workRoot: '/work/app' }, { command: 'x', at: min(30) }));
show('not due: deployed since', due(built, { command: 'x', at: min(1) }));
show('not due: skipped since', due(built, { command: 'x', at: min(30), skippedAt: min(1) }));
show('due: never deployed, with only a suggestion', due(built, { suggested: 'x' }));
show('not due: no command saved, and nothing to suggest', due(built, {}));
show('not due: the last turn only looked things up',
  due({ outcome: 'Researched', outcomeAt: min(5) }, { command: 'x' }));
show('due: the hook noted a build after that turn', due({ outcome: 'Committed', outcomeAt: min(9), builtAt: min(4) },
                                                     { command: 'x', at: min(6) }));
show('due: another session in the folder built since, though this one only committed',
  due({ outcome: 'Committed', outcomeAt: min(2) }, { command: 'x', at: min(30), work: min(10) }));
show('not due: deployed since the other session built',
  due({ outcome: 'Committed', outcomeAt: min(2) }, { command: 'x', at: min(5), work: min(10) }));
show('not due: what it edited since landed in another checkout, which is nothing new here',
  due({ workRoot: '/work/lib', editedAt: min(5) }, { command: 'x', at: min(30), folder: '/work/app' }));
show('due: it built here since, though its edits landed in another checkout (it builds where it runs)',
  due({ workRoot: '/work/lib', editedAt: min(40), builtAt: min(5) },
      { command: 'x', at: min(30), folder: '/work/app' }));
show('when each folder last had files edited or something built, by any session there', folderWork([
  session({ sessionId: 'a', outcome: 'Built', outcomeAt: min(10), builtAt: min(10) }),
  session({ sessionId: 'b', ...editedHere(min(8), { outcome: 'Committed', outcomeAt: min(2) }) }),
  session({ sessionId: 'c', outcome: 'Researched', outcomeAt: min(1), git: fixHover, builtAt: min(20) }),
  session({ sessionId: 'd', outcome: 'Researched', outcomeAt: min(1), git: null, cwd: '/work/notes' }),
]));
show('…counted where the work landed: edits in another checkout count there, not in the session\'s own', folderWork([
  session({ sessionId: 'e', workRoot: '/work/lib', editedAt: min(3), outcome: 'Implemented', outcomeAt: min(3) }),
]));
show('…and builds where the session runs, however long ago its edits went elsewhere', folderWork([
  session({ sessionId: 'f', workRoot: '/work/lib', editedAt: min(300), builtAt: min(2) }),
]));
const dep = (fields) => ({ key: '/work/app', folder: '/work/app', command: 'make install', ...fields });
const offer = (fields, kind, d, owner = true) => deployOffer(session(fields), kind, owner, d, NOW);
const suggested = (fields) => dep({ command: undefined, suggested: 'cargo install --path .', ...fields });
const doneRun = { running: false, ok: true, startedAt: NOW - 9000, finishedAt: NOW - 400 };
const failedRun = { running: false, ok: false, startedAt: NOW - 5000, finishedAt: NOW - 200,
                    lastLine: 'make: *** No rule to make target `install`.' };
show('confirmed, nothing new: always there', offer(built, 'idle', dep({ at: min(1) })));
show('confirmed, new work since the last deploy: the dot', offer(built, 'idle', dep({ at: min(30) })));
show('confirmed, no work in the folder at all: still there', offer({}, 'idle', dep({})));
show('confirmed, the agent working: dimmed', offer(built, 'busy', dep({ at: min(30) })));
show('confirmed, the agent asking: dimmed', offer(built, 'needs', dep({})));
show('just pressed', offer({}, 'idle', dep({ pressed: NOW - 300 })));
show('running, whatever the agent does', offer({}, 'busy', dep({ run: { running: true, startedAt: NOW - 2000 } })));
show('went through a moment ago: the check', offer({}, 'idle', dep({ run: doneRun, at: doneRun.finishedAt,
                                                                  seenDone: NOW - 400 })));
show('went through 2.5s ago, but the page sees it only now: the check, from now',
  offer({}, 'idle', dep({ run: { ...doneRun, finishedAt: NOW - 2500 }, seenDone: NOW - 100 })));
show('went through before the page could have seen it: no check',
  offer({}, 'idle', dep({ run: { ...doneRun, finishedAt: NOW - 1000 }, seenDone: 0 })));
show('only a suggestion, after new work: offered', offer(built, 'idle', suggested({})));
show('only a suggestion, deployed since: not offered', offer(built, 'idle', suggested({ at: min(1) })));
show('only a suggestion, passed on since: not offered', offer(built, 'idle', suggested({ skippedAt: min(1) })));
show('nothing to suggest: never', offer(built, 'idle', dep({ command: undefined })));
show('not the row that speaks for the folder: none', offer(built, 'idle', dep({}), false));
show('Show Deploy off: none', offer(built, 'idle', null));
show('another agent working in the folder: dimmed, saying which', offer(built, 'idle', dep({ at: min(30),
                                                                                    waitsFor: ['codegen'] })));
show('…the row\'s own agent working as well: its own', offer(built, 'busy', dep({ waitsFor: ['codegen'] })));
show('…a deploy running: whatever the agents do', offer({}, 'idle', dep({ waitsFor: ['codegen'],
  run: { running: true, startedAt: NOW - 2000 } })));
const byKind = (sessions) => agentsAtWork(sessions,
  Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, NOW, byStatus)])));
show('the agents at work, by each folder they work in (their own checkout, and the one their edits land in); not one '
  + 'waiting on you, which changes nothing until you answer it',
  Object.fromEntries(Object.entries(byKind([
    session({ sessionId: 'working', status: 'busy' }),
    session({ sessionId: 'asking', git: fixHover, ask: { id: 'q', tool: 'Bash', input: {} } }),
    session({ sessionId: 'plan-waiting-days', status: 'waiting', statusUpdatedAt: min(4000) }),
    session({ sessionId: 'editing-elsewhere', status: 'busy', git: fixHover, workRoot: '/work/lib' }),
    session({ sessionId: 'edited-there-this-turn', status: 'busy', workRoot: '/work/lib', lastPromptAt: min(10),
              editedAt: min(2) }),
    session({ sessionId: 'edited-there-turns-ago', status: 'busy', workRoot: '/work/lib', lastPromptAt: min(10),
              editedAt: min(300) }),
    session({ sessionId: 'compacting', compacting: NOW - 1000, git: null, cwd: '/work/notes' }),
    session({ sessionId: 'idle' }),
    session({ sessionId: 'replied', ...reply }),
  ])).map(([folder, sessions]) => [folder, sessions.map((s) => s.sessionId)])));
show('how a wait for other agents is said', [['a'], ['a', 'b'], ['a', 'b', 'c']].map(untilDone));
const look = (fields, kind, d) => deployHTML(session({ sessionId: 'd1', ...fields }), d,
                                             deployOffer(session(fields), kind, true, d, NOW), NOW);
print('-- the button, confirmed, nothing new');
print(look(built, 'idle', dep({ at: min(1) })));
print('-- with new work: the dot');
print(look(built, 'idle', dep({ at: min(30) })));
print('-- only suggested');
print(look(built, 'idle', suggested({})));
print('-- the agent working');
print(look(built, 'busy', dep({ at: min(30) })));
print('-- agents in two other sessions working in the folder');
print(look(built, 'idle', dep({ at: min(30), waitsFor: ['codegen', 'formatter'] })));
print('-- 300ms after the press');
print(look({}, 'idle', dep({ pressed: NOW - 300 })));
print('-- running for 2s');
print(look({}, 'idle', dep({ run: { running: true, startedAt: NOW - 2000 } })));
print('-- went through 400ms ago: the check');
print(look({}, 'idle', dep({ run: doneRun, at: doneRun.finishedAt, seenDone: doneRun.finishedAt })));
print('-- back to play, 300ms after the check');
print(look({}, 'idle', dep({ run: { ...doneRun, finishedAt: NOW - 1800 }, at: NOW - 1800, seenDone: NOW - 1800 })));
print("-- didn't go through");
print(look(built, 'idle', dep({ run: failedRun, at: min(30) })));
show('the line under the row, while it runs', deployNote(dep({ run: { running: true, startedAt: NOW - 2000 } }), NOW));
show('…just pressed', deployNote(dep({ pressed: NOW - 300 }), NOW));
show('…still running after 3 minutes', deployNote(dep({ run: { running: true, startedAt: NOW - 180000 } }), NOW));
show("…after one that didn't go through", deployNote(dep({ run: failedRun }), NOW));
show('…ten minutes on, nothing more', deployNote(dep({ run: { ...failedRun, finishedAt: min(11) } }), NOW));
show('…after you stopped it',
  deployNote(dep({ run: { running: false, ok: false, stopped: true, finishedAt: NOW - 5000 } }), NOW));
show('…nothing after one that went well', deployNote(dep({ run: doneRun }), NOW));
print('-- the set-up card: the suggested command, to change');
print(setupHTML(session({ sessionId: 'd6' }), { step: 1, text: 'cargo install --path .', then: 'deploy' },
                dep({ command: undefined })));
print('-- the set-up card with its box empty: Use this waits');
print(setupHTML(session({ sessionId: 'd6' }), { step: 1, text: '', then: 'deploy' }, dep({})));
print('-- the set-up card, confirming the command as it will run, with what its target really runs (from the app)');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'make install', then: 'save', checked: {
  command: 'make install', production: false, runs: 'cc -o tool main.c\ncp tool ~/bin/' } }, dep({})));
print('-- confirming a command the app says looks as if it could reach production');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'npm run deploy:local', then: 'save', checked: {
  command: 'npm run deploy:local', production: true, runs: 'fly deploy --local-only' } }, dep({})));
print('-- …and one that runs more than the card shows');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'make', then: 'save', checked: {
  command: 'make', production: false, runs: 'one\ntwo', more: 3 } }, dep({})));
// The app's answer about a command (deployChecked in deploy-row.js) moves the card on only while it still shows that
// command.
const drawn = render;
render = () => {};
state.deploySetup.d7 = { step: 1, text: 'make install', then: 'save', checking: 'make install' };
deployChecked('d7', { command: 'make install', production: false });
show("the app's answer moves the card on to confirming", state.deploySetup.d7.step);
show('…and the new step waits before it takes a press', justShown('setup:d7'));
state.deploySetup.d8 = { step: 1, text: 'make install-all', then: 'save', checking: 'make install' };
deployChecked('d8', { command: 'make install', production: false });
show('…not when the command was changed after it was asked about', state.deploySetup.d8.step);
state.shownAt['setup:d7'] -= 5000;  // up a while
const press = (sid, cls) => pressSetup({ dataset: { setup: sid } }, { preventDefault() {}, target: { closest: (sel) =>
  (sel === 'button' ? { disabled: false, matches: (m) => m.split(', ').includes(cls) } : null) } });
press('d7', '.d-back');
show('Back goes back to the command', state.deploySetup.d7.step);
show("…and Cancel, where Back was, doesn't take a press at once", justShown('setup:d7'));
press('d7', '.d-cancel');
show('…so a double click on Back leaves the card up', !!state.deploySetup.d7);
render = drawn;
state.deploySetup = {};

section('The island');
const remote = { remotes: 1, upstream: true, base: 'main' };
const owned = { outcome: 'Implemented', outcomeAt: min(5) };
const onF = { git: { branch: 'f', root: '/work/app' } };
const extra = (fields) => ({ count: 2, label: 'to review', ...fields });
// Each stage, briefly: what it says, * where your next move is, and → the step its menu offers first.
const brief = (stages) => stages && stages.map((st) => `${st.stage} ${st.text}${st.move ? ' *' : ''}`
  + (st.step ? ' → ' + st.step : '') + (st.parts ? ` [${st.parts.staged} staged, ${st.parts.partly} partly, `
  + `${st.parts.unstaged} unstaged]` : ''));
const split = { filesStaged: 29, filesPartly: 31, filesUnstaged: 4 };
const islands = [
  ['clean: none', { ...owned, checkout: { ...remote, changes: 0 } }],
  ['changed files', { ...owned, checkout: { ...remote, changes: 2 } }],
  ['new files only', { ...owned, checkout: { ...remote, changes: 0, newFiles: 3 } }],
  ['while the agent works: shown all the same', { ...owned, status: 'busy', checkout: { ...remote, changes: 2 } }],
  ['no remote, with changes: no commits or GitHub', { ...owned, checkout: { remotes: 0, changes: 1 } }],
  ['no remote, committed: finished, none', { ...owned, checkout: { remotes: 0, changes: 0, aheadOfBase: 1 } }],
  ['on main, commits not pushed', { ...owned, checkout: { ...remote, ahead: 2 } }],
  ['on main, never pushed', { ...owned, checkout: { ...remote, upstream: false, aheadOfBase: 1 } }],
  ['on main, all pushed: none', { ...owned, checkout: { ...remote, ahead: 0, aheadOfBase: 0 } }],
  ['on main, changed files and commits', { ...owned, checkout: { ...remote, changes: 1, ahead: 2 } }],
  ['a branch not pushed', { ...owned, ...onF, checkout: { ...remote, upstream: false, aheadOfBase: 2 } }],
  ['a branch pushed with no PR, as GitHub says', { ...owned, ...onF, checkout: { ...remote, ahead: 0, aheadOfBase: 2,
                                                                                pr: null } }],
  ['…GitHub not asked yet (or no gh): not "no PR", none', { ...owned, ...onF, checkout: { ...remote, ahead: 0,
                                                                                          aheadOfBase: 2 } }],
  ['…a PR the session raised from another branch doesn\'t count: "no PR"', { ...owned, ...onF, checkout: { ...remote,
    ahead: 0, aheadOfBase: 2, pr: null }, prs: [pr({ headRefName: 'g' })] }],
  ['…one it raised from this branch does', { ...owned, ...onF, checkout: { ...remote, ahead: 0, aheadOfBase: 2,
    pr: null }, prs: [pr({ headRefName: 'f' })] }],
  ['…a PR raised since GitHub last looked: not "no PR", none', { ...owned, ...onF, outcome: 'PR raised',
    outcomeAt: min(1), checkout: { ...remote, ahead: 0, aheadOfBase: 2, pr: null, prCheckedAt: min(5) / 1000 } }],
  ['a branch with an open PR, nothing new: none', { ...owned, ...onF, checkout: { ...remote, aheadOfBase: 2 },
                                                  prs: [pr({})] }],
  ['a branch with an open PR and new commits', { ...owned, ...onF, checkout: { ...remote, ahead: 1, aheadOfBase: 3 },
                                                prs: [pr({})] }],
  ['a branch with an open PR and changed files', { ...owned, ...onF, checkout: { ...remote, changes: 2, aheadOfBase: 3,
                                                  pr: pr({ number: 14 }) } }],
  ['a branch whose PR was merged: none', { ...owned, ...onF, checkout: { ...remote, aheadOfBase: 2,
                                                                       pr: pr({ state: 'MERGED' }) } }],
  ['the extra stage', { ...owned, checkout: { ...remote, changes: 3, ahead: 1, stage: extra({ edits: 1 }) } }],
  ['the extra stage holding every change', { ...owned, checkout: { ...remote, changes: 3, stage: extra({ edits: 0 }) } }],
  ['the extra stage, empty', { ...owned, checkout: { ...remote, changes: 3, stage: extra({ count: 0 }) } }],
  ['the extra stage, with no remote', { ...owned, checkout: { remotes: 0, changes: 0, stage: extra({ edits: 0 }) } }],
  ['…naming the files outside it: a gauge of those, split as git sees them', { ...owned, checkout: { ...remote,
    changes: 64, newFiles: 2, ...split, stage: extra({ edits: 3, parts: { staged: 0, partly: 2, unstaged: 1 } }) } }],
  ['the extra stage still asking: left out', { ...owned, checkout: { ...remote, changes: 3, stage: { ask: 'x' } } }],
  ['git says how the files split: a gauge, new files counted as unstaged', { ...owned, checkout: { ...remote,
    changes: 64, newFiles: 2, ...split } }],
  ['…all of them staged', { ...owned, checkout: { ...remote, changes: 5, filesStaged: 5, filesPartly: 0,
                                                 filesUnstaged: 0 } }],
  ['…but the extra stage counts the files itself: no split', { ...owned, checkout: { ...remote, changes: 64,
    newFiles: 2, ...split, stage: extra({ edits: 3 }) } }],
  ['…unless it holds nothing: every change is outside it, so git\'s count and split', { ...owned, checkout: {
    ...remote, changes: 64, newFiles: 2, ...split, stage: extra({ count: 0, edits: 67 }) } }],
  ['big counts, shortened', { ...owned, checkout: { ...remote, changes: 12345, ahead: 1260, filesStaged: 4120,
                                                   filesPartly: 6930, filesUnstaged: 1295, stage: extra({ count: 140 }) } }],
];
for (const [name, fields] of islands) show(name, brief(stagesOf(session(fields), true)));
show("not the checkout's owner", stagesOf(session({ ...owned, checkout: { ...remote, changes: 2 } }), false));
show('outside git: none', stagesOf(session({ ...owned, git: null, cwd: '/work/notes' }), true));
show('tooltips', stagesOf(session({ ...owned, ...onF, checkout: { ...remote, changes: 1, ahead: 0, aheadOfBase: 1,
                                                                pr: null, stage: extra({}) } }), true).map((st) => st.tip));
show('counts, as the island writes them', [0, 999, 1000, 1234, 9950, 12345, 999999].map(compact));
show('commands that run a file in the checkout', Object.fromEntries(['./review.sh', 'python3 scripts/review.py',
  'python3 review.py', 'sh review.sh', 'cd tools && node review.js', 'review --config=./review.toml', 'make review',
  'npm run review', 'git review stage', 'python3 -m review', '~/bin/review', '/usr/local/bin/review --json',
  'curl -s https://example.com/review', '$HOME/review'].map((command) => [command, runsRepoFile(command)])));
const edited = (root, at) => ({ workRoot: root, editedAt: at });
show('who speaks for each checkout or folder: the session that edited files there last', [...checkoutOwners([
  session({ sessionId: 'chat', lastPromptAt: min(1) }),
  session({ sessionId: 'worker', outcome: 'Researched', lastPromptAt: min(5), ...edited('/work/app', min(20)) }),
  session({ sessionId: 'earlier', outcome: 'Implemented', lastPromptAt: min(50), ...edited('/work/app', min(50)) }),
  session({ sessionId: 'tree', git: fixHover, lastPromptAt: min(9), ...edited('/work/app-fix', min(9)) }),
  session({ sessionId: 'notes', git: null, cwd: '/work/notes', lastPromptAt: min(7),
            ...edited('/work/notes', min(7)) }),
])].sort());
show('…closed or not, and whatever it has done since', [...checkoutOwners([
  session({ sessionId: 'edited-then-closed', status: 'closed', outcome: 'Researched', lastPromptAt: min(30),
            ...edited('/work/app', min(40)) }),
  session({ sessionId: 'chat-since', outcome: 'Documented', lastPromptAt: min(1) }),
])]);
show('…its edits counted only where they landed: notes written elsewhere don\'t count', [...checkoutOwners([
  session({ sessionId: 'did-the-work', outcome: 'Researched', lastPromptAt: min(30), ...edited('/work/app', min(35)) }),
  session({ sessionId: 'wrote-notes-elsewhere', outcome: 'Documented', outcomeAt: min(2), lastPromptAt: min(2) }),
])]);
show('…and only for the checkout it runs in: what it edits in another leaves that one\'s island where it is',
  [...checkoutOwners([
    session({ sessionId: 'main-chat', lastPromptAt: min(1), ...edited('/work/app-fix', min(1)) }),
    session({ sessionId: 'tree', git: fixHover, lastPromptAt: min(20), ...edited('/work/app-fix', min(20)) }),
  ])].sort());
show('…with an older hook (no time noted): the end of its last turn that changed something', [...checkoutOwners([
  session({ sessionId: 'built-later', outcome: 'Built', outcomeAt: min(10), workRoot: '/work/app' }),
  session({ sessionId: 'documented-earlier', outcome: 'Documented', outcomeAt: min(60), workRoot: '/work/app' }),
  session({ sessionId: 'only-looked-since', outcome: 'Researched', outcomeAt: min(1), workRoot: '/work/app' }),
])]);
show('no listed session edited there: the session last active there', [...checkoutOwners([
  session({ sessionId: 'asked-earlier', outcome: 'Researched', lastPromptAt: min(30) }),
  session({ sessionId: 'asked-since', outcome: 'Researched', lastPromptAt: min(3) }),
])]);
show('…one still running before a closed one, though the closed one was used later', [...checkoutOwners([
  session({ sessionId: 'running', outcome: 'Researched', lastPromptAt: min(30) }),
  session({ sessionId: 'closed', status: 'closed', outcome: 'Researched', lastPromptAt: min(3) }),
])]);
show('…a closed one when none there is running', [...checkoutOwners([
  session({ sessionId: 'closed-earlier', status: 'closed', outcome: 'Researched', lastPromptAt: min(30) }),
  session({ sessionId: 'closed-later', status: 'closed', outcome: 'Researched', lastPromptAt: min(3) }),
])]);

print('-- a row with changed files it didn\'t change itself: what the work has been through at the end of the details line,'
      + ' the island under it, no tag');
state.owners = new Set(['w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7']);
const withSteps = (sessionId, checkout, fields = {}) => session({ sessionId, outcome: 'Tested', workSteps: ['Built',
  'Tested'], checkout: { ...remote, added: 1493, removed: 62, ...checkout }, ...fields });
print(rowHTML(withSteps('w1', { changes: 3 }), 'idle', NOW));
print('-- git says how the files split: the files stage is a gauge, with each part\'s count in words and as a number');
print(rowHTML(withSteps('w1', { changes: 64, newFiles: 2, ahead: 2, ...split }), 'idle', NOW));
print('-- …kept open through a rebuild while it\'s pointed at');
state.islandOpen = 'w1';
print(islandHTML(withSteps('w1', {}), stagesOf(withSteps('w1', { changes: 64, newFiles: 2, ...split }), true)));
state.islandOpen = null;
print('-- no remote: only the files');
print(rowHTML(withSteps('w2', { changes: 3, remotes: 0 }), 'idle', NOW));
print('-- a branch pushed with no pull request yet, as GitHub says: that is the move');
print(rowHTML(withSteps('w3', { ahead: 0, aheadOfBase: 1, added: 212, removed: 9, pr: null },
                        { git: { branch: 'f', root: '/work/app' } }), 'idle', NOW));
show('the part of the gauge whose files are listed is drawn lit, so a rebuild doesn\'t light it afresh',
     (state.filesShown = 'w1:staged', /band st is-on/.test(islandHTML(withSteps('w1', {}),
       stagesOf(withSteps('w1', { changes: 64, newFiles: 2, ...split }), true)))));
state.filesShown = null;
show('no lines to count (only a binary file changed): what the work has been through, in words',
     /class="proof"[^>]*>built · tested</.test(rowHTML(withSteps('w1', { changes: 1, added: 0, removed: 0 }), 'idle',
                                                     NOW)));
print("-- the files of a part of the gauge, as its list shows them: each part titled and explained, new ones marked");
state.checkoutFiles = { '/work/app': { staged: ['app/Git.m'], partly: ['panel/scripts/rows.js'],
                                       unstaged: ['README.md'], new: ['docs/stages.md'] } };
const inApp = session({ git: { branch: 'main', root: '/work/app' } });
for (const [part, n] of [['staged', 1], ['partly', 1], ['unstaged', 2]]) print(filesHTML(inApp, part, n));
state.checkoutFiles = { '/work/app': { unstaged: Array.from({ length: 100 }, (_, i) => `src/file${i}.js`),
                                       new: ['docs/stages.md'] } };
show('…the first 100, and how many more', filesHTML(inApp, 'unstaged', 150).match(/<div class="f-more">[^<]*/)[0]);
state.checkoutFiles = {};
print('-- the extra stage, and how a step from its menu went, said quietly under the details');
state.stepNotes.w4 = { text: 'Done, 1 left.', quiet: true, at: Date.now() };
print(rowHTML(withSteps('w4', { changes: 3, ahead: 1, stage: extra({ edits: 1 }) }), 'idle', NOW));
print("-- a step that couldn't go in, said under the details");
state.stepNotes.w4 = { text: 'Claude is working: ask again when it\'s done', at: Date.now() };
print(rowHTML(withSteps('w4', { changes: 3 }), 'idle', NOW));
state.stepNotes = {};
print('-- asked once whether its extra stage may run, with a warning: it runs a file in the checkout');
print(rowHTML(withSteps('w7', { changes: 3, stage: { ask: 'python3 ./review.py --json' } }), 'idle', NOW));
state.trustAnswered.w7 = { command: 'python3 ./review.py --json', at: Date.now() };
show('…not asked again just after an answer',
     trustAsked(withSteps('w7', { stage: { ask: 'python3 ./review.py --json' } }), true));
show('…but asked again when the command changes', trustAsked(withSteps('w7', { stage: { ask: 'review --json' } }), true));
show('…and never on a row that doesn\'t speak for the checkout', trustAsked(withSteps('w7', { stage: { ask: 'x' } }),
                                                                             false));
show('…nor while a request waits on the row', trustAsked(withSteps('w7', { stage: { ask: 'x' } },
  { ask: { id: 'a1', tool: 'Bash', input: { command: 'ls' } } }), true));
state.trustAnswered = {};
const asking = withSteps('w7', { changes: 3, stage: { ask: 'review --json' } });
rowHTML(asking, 'idle', NOW);
state.shownAt['trust:w7'] -= 5000;  // up a while
show('…a card that has been up a while takes a press', !justShown('trust:w7'));
state.trustAnswered.w7 = { command: 'review --json', at: Date.now() };
rowHTML(asking, 'idle', NOW);  // away, just after an answer
state.trustAnswered = {};
rowHTML(asking, 'idle', NOW);
show('…one that\'s back waits again before it does', justShown('trust:w7'));
state.shownAt['trust:w7'] -= 5000;
rowHTML(withSteps('w7', { changes: 3, stage: { ask: 'review --json --all' } }), 'idle', NOW);
show('…as does one now showing another command', justShown('trust:w7'));
delete state.shownAt['trust:w7'];
delete state.trustShown.w7;
// Deploy's button and line go by the page's own clock: held at NOW while they're drawn, so they read the same each run.
const pageClock = Date.now;
Date.now = () => NOW;
print("-- Deploy's button on the title line, with the dot; the island; why its last deploy didn't go through");
state.deploys = { projects: { '/work/app': { command: 'make install' } },
                  folders: { '/work/app': { at: min(30), run: failedRun } } };
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5))), 'idle', NOW));
print('-- while the agent works: Deploy dimmed, the island shown all the same');
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5), { status: 'busy' })), 'busy', NOW));
state.shownAt['deploy:w5'] -= 5000;  // up a while
state.owners.delete('w5');  // another row speaks for the folder for a while
rowHTML(withSteps('w5', { changes: 3 }), 'idle', NOW);
state.owners.add('w5');
rowHTML(withSteps('w5', { changes: 3 }), 'idle', NOW);
show("Deploy's button, gone and back, waits again before it takes a press", justShown('deploy:w5'));
state.atWork = { '/work/app': [session({ sessionId: 'w9', name: 'codegen', status: 'busy' }),
                               session({ sessionId: 'w5', status: 'busy' })] };
show("what a row's Deploy waits for: the other sessions at work in its folder, by title",
     rowDeploy(withSteps('w5', {})).waitsFor);
state.atWork = {};
show("the line when a deploy couldn't start: why, for a few seconds, in place of the deploy's own",
  (state.stepNotes.w5 = { text: 'Deploy waits until the agent is done', at: Date.now() },
   stepLine({ s: withSteps('w5', {}), deploy: rowDeploy(withSteps('w5', {})), offer: {} })));
state.stepNotes = {};
print('-- the set-up card on its row');
state.deploySetup.w5 = { step: 1, text: 'make install', then: 'save' };
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5))), 'idle', NOW));
state.deploySetup = {};
print('-- Show Next Steps off: the tag and what the work has been through, as before');
state.switches = { ...state.switches, nextSteps: false };
print(rowHTML(withSteps('w6', { changes: 3 }), 'idle', NOW));
state.switches = { ...state.switches, nextSteps: true };
state.deploys = { projects: {}, folders: {} };
Date.now = pageClock;
state.owners = new Set();

section('Plan usage, in the strip');
const HOUR = 3600e3, MINUTE = 60e3;
// What the app sends (modules/usage/app/Usage.m), for a session and a week; clock times in UTC, written the US way, on
// every Mac.
const plan = (session, week, more) => ({ state: 'ok', plan: 'pro', session, week, limits: [], extraUsage: false,
                                        ...more });
const viewOf = (data, now = NOW) => usageView(data, now, 'en-US', 'UTC');
show('time left, 2h 59m', timeLeft(2 * HOUR + 59 * MINUTE));
show('time left, 1d 17h', timeLeft(41 * HOUR + 17 * MINUTE));
show('time left, 2h 5m', timeLeft(2 * HOUR + 5 * MINUTE));
show('time left, 42m', timeLeft(42 * MINUTE));
show('time left, 20 seconds (rounded up)', timeLeft(20e3));
show('time left, none', timeLeft(0));
show('hours next to Session, 2h 59m', hoursLeft(2 * HOUR + 59 * MINUTE));
show('hours next to Session, 2h 10m', hoursLeft(2 * HOUR + 10 * MINUTE));
show('hours next to Session, 42m', hoursLeft(42 * MINUTE));
show('clock time, within 12 hours', clockAt(NOW + 2 * HOUR, NOW, 'en-US', 'UTC'));
show('clock time, in two days', clockAt(NOW + 41 * HOUR, NOW, 'en-US', 'UTC'));
show('clock time, a week off', clockAt(NOW + 6.5 * 24 * HOUR, NOW, 'en-US', 'UTC'));
show('Claude Code not signed in', viewOf({ state: 'signedOut' }).state);
show('signed in with an API key or another provider', viewOf({ state: 'other' }).state);
show('no claude on this Mac', viewOf({ state: 'none' }).state);
show('not asked yet', viewOf(null).state);
const earlyView = viewOf(plan({ used: 20, resetsAt: NOW + 4.5 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('20% half an hour in', { state: earlyView.state, session: [earlyView.session.used, earlyView.session.severity,
                                                            earlyView.session.colour], pace: earlyView.pace });
const steadyView = viewOf(plan({ used: 30, resetsAt: NOW + 2 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('30% three hours in: on course, no note', steadyView.pace);
const warnedView = viewOf(plan({ used: 82, resetsAt: NOW + 2 * HOUR + 59 * MINUTE },
                               { used: 30, resetsAt: NOW + 41 * HOUR },
                               { limits: [{ kind: 'session', percent: 82, severity: 'warning' },
                                          { kind: 'weekly_all', percent: 30, severity: 'normal' }] }));
show("82% two hours in, Claude says warning",
  [warnedView.session.severity, warnedView.session.colour, warnedView.week.severity]);
show('82% two hours in: the pace', warnedView.pace);
show('82% with no severity from Claude',
  viewOf(plan({ used: 82, resetsAt: NOW + 3 * HOUR }, { used: 30, resetsAt: NOW + 41 * HOUR })).session.severity);
show("90% and a word past warning",
  viewOf(plan({ used: 90, resetsAt: NOW + 3 * HOUR }, { used: 30, resetsAt: NOW + 41 * HOUR },
              { limits: [{ kind: 'session', percent: 90, severity: 'critical' }] })).session.severity);
const atLimitPlan = plan({ used: 100, resetsAt: NOW + 20 * MINUTE }, { used: 30, resetsAt: NOW + 41 * HOUR });
show('at the session limit', viewOf(atLimitPlan).state);
show('at the limit with extra usage on: no wait', viewOf({ ...atLimitPlan, extraUsage: true }).state);
const afterReset = viewOf(atLimitPlan, NOW + 21 * MINUTE);
show('the limit has just reset: 0% until the app asks again',
  [afterReset.state, afterReset.session.used, afterReset.session.left]);
show('while waiting, hours off', backLine(2 * HOUR, NOW, NOW + 2 * HOUR, 'en-US', 'UTC'));
show('while waiting, the last hour', backLine(42 * MINUTE, NOW, NOW + 42 * MINUTE));
show('while waiting, the last minute', backLine(9e3, NOW, NOW + 9e3));
show('how far through the wait',
  [waitProgress(NOW - HOUR, NOW + HOUR, NOW), waitProgress(NOW, NOW + HOUR, NOW + 2 * HOUR)]);

section("The vine's growth and reset (wait-vine.js)");
show('growth at the limit, halfway, at the reset', [0, 0.5, 1].map((p) => {
  const g = vineGrowth(p);
  return { leaves: g.leaves, bud: !!g.bud };
}));
// The session's bar in the normal strip with no time left beside it, as just after a reset, and the strip's heights.
const vineBar = { x0: 72, x1: 278, y: 20 }, vineHeights = { wait: 84, normal: 61 };
const vineAt = (t) => vineFrame(t, vineBar, vineHeights);
const stemEnds = (t) => {
  const s = vineAt(t).stem;
  return s && [s[0], s[s.length - 1]].map((p) => p.map((v) => +v.toFixed(1)));
};
const restEnds = stemEnds(1100), movedEnds = stemEnds(1150);
show('both ends of the stem start moving together (1.1s)',
  [Math.hypot(movedEnds[0][0] - restEnds[0][0], movedEnds[0][1] - restEnds[0][1]) > 0,
   Math.hypot(movedEnds[1][0] - restEnds[1][0], movedEnds[1][1] - restEnds[1][1]) > 0]);
show('and land together on the bar (2.1s)', stemEnds(2100 - 1e-6));
// The bar's right end: the stem's until it lands (its round end reaching 2px further), then the fill's.
const rightEnd = (t) => {
  const f = vineAt(t);
  return f.stem ? f.stem[f.stem.length - 1][0] + 2 : vineBar.x0 + f.fill.width * (vineBar.x1 - vineBar.x0);
};
show('the drain carries on at the speed the stem landed with (px a ms)',
  [(rightEnd(2099.9) - rightEnd(2099.8)) / 0.1, (rightEnd(2100.2) - rightEnd(2100.1)) / 0.1].map((v) => v.toFixed(3)));
let highestLeaf = Infinity;
for (let t = 0; t <= VINE_RESET_MS; t += 5)
  for (const leaf of vineAt(t).leaves)
    if (leaf.opacity > 0.01) highestLeaf = Math.min(highestLeaf, leaf.y - 11 * leaf.scale);
show('no leaf flies into the text lane (above y 32)', highestLeaf >= 32 ? 'clear' : highestLeaf);
let laneEntered = null;
for (let t = 0; t <= VINE_RESET_MS && laneEntered === null; t += 5)
  if (vineAt(t).stem?.some(([, y]) => y < 31)) laneEntered = t;
const entryFrame = vineAt(laneEntered);
show('the session line is clear before the stem rises into it',
  { at: laneEntered, message: +entryFrame.message.opacity.toFixed(3), right: +entryFrame.right.opacity.toFixed(3) });
const lastFrame = vineAt(VINE_RESET_MS);
show('the last frame is the normal strip', {
  stem: lastFrame.stemShown, flower: lastFrame.flower, fill: lastFrame.fill.width, height: lastFrame.height,
  week: lastFrame.week.opacity, percent: lastFrame.percent.opacity, message: lastFrame.message.opacity,
  right: lastFrame.right.opacity,
});

section('What a session wrote: the tag, the plan card, the reader');
const planWriting = (id, status, at, title) => ({ id, kind: 'plan', title, path: '/h/.claude/plans/p.md', at: min(at), status });
const wrote = [planWriting('p2', 'waiting', 2, 'Dark mode, again'),
               { id: '/work/app/v.html', kind: 'prototype', title: 'Two layouts', path: '/work/app/v.html', at: min(5) },
               planWriting('p1', 'declined', 9, 'Dark mode'),
               { id: '/work/app/n.md', kind: 'notes', title: 'Notes', path: '/work/app/n.md', at: min(20) }];
const planAsk = { id: 'pa', tool: 'ExitPlanMode', at: min(1), input: { plan: '# Dark mode, again\nText', planFilePath: '/p.md' } };
show('no writings: no tag', writingsTag(session({})));
show('the newest thing, and how many more', writingsTag(session({ writings: wrote.slice(1) })));
show('the plan waiting for you leads, while Claude asks about it', writingsTag(session({ writings: wrote, ask: planAsk })));
state.reading = { sessionId: 's', mode: 'writings' };
show("the tag shows as pressed while the reader is open on its session", writingsTag(session({ writings: wrote.slice(1) })).includes('wtag k-prototype on'));
state.reading = null;
show('a plan only just asked about shows from its request, before the transcript lists it',
     writingsOf(session({ ask: planAsk })).map((w) => [w.id, w.title, w.status]));
show('the plan Claude waits on', waitingPlan(session({ writings: wrote, ask: planAsk }))?.id);
show('no plan waits once the request is gone', waitingPlan(session({ writings: wrote })));
show("each one's status in the list", wrote.map((w) => writingStatus(w, session({ writings: wrote, ask: planAsk }))));
show('a waiting plan whose request has gone: no answer', writingStatus(wrote[0], session({ writings: wrote })));
show('a new request with only an old unanswered plan listed: the request\'s own plan, never the old one',
     waitingPlan(session({ writings: [planWriting('old', 'waiting', 30, 'Old')], ask: planAsk }))?.id);
state.last = { sessions: [], now: NOW };
print(shelfHTML(session({ writings: wrote, ask: planAsk }), wrote, 'p2'));
const markupName = { id: '/work/app/<b>n.md', kind: 'notes', path: '/work/app/<b>n.md', at: min(3) };
show('a file named like markup is listed as text',
     !shelfHTML(session({ writings: [markupName] }), [markupName], null).includes('<b>'));
print(askHTML(planAsk));
state.reading = { sent: {}, revising: false, notes: '' };
print(answerHTML(wrote[0], session({ writings: wrote, ask: planAsk })));
state.reading.revising = true;
print(answerHTML(wrote[0], session({ writings: wrote, ask: planAsk })));
state.reading.sent = { p2: 'revise' };
print(answerHTML(wrote[0], session({ writings: wrote, ask: planAsk })));
show('no answer bar under a plan that was answered', answerHTML(wrote[2], session({ writings: wrote, ask: planAsk })));
state.reading = null;

section('Markdown, as plans and notes are shown');
const md = (name, text) => print(`-- ${name}\n${markdownHTML(text)}`);
md('headings, a paragraph over two lines, bold, italic and code', '# Plan\n\nRead **this** and *that*, `a <b>`\nnext line\n## Steps');
md('lists, nested, numbered from 3, with a task', '- one\n  - inner\n- [x] done\n\n3. three\n4. four');
md('a table and a rule', '| Q | A |\n|---|:-:|\n| colour | blue |\n\n---');
md('a code block keeps its text as it is', '```js\nconst a = "<b>" && 1;\n```');
md('HTML in the text stays text, and a link shows its words', '<script>alert(1)</script> [docs](https://x.dev/a?b=1&c) > not a quote');
md('a quote', '> quoted **line**\n> second');

section('What a session changed: its numbers, their card, the changes view');
const chSessions = [session({ sessionId: 'me', name: 'Retry queue' }), session({ sessionId: 'tests', name: 'Retry tests' })];
const chMine = { added: 26, removed: 13, v: 4, files: [
  { path: 'billing/retry.py', added: 20, removed: 0, edits: 2, at: min(1), created: true, saved: false, shared: true },
  { path: 'docs/retries.md', added: 6, removed: 13, edits: 1, at: min(40), created: false, saved: true }],
  parts: { me: [26, 13], tests: [24, 1], outside: [1464, 123] } };
const chRow = session({ sessionId: 'me', name: 'Retry queue', changes: chMine, checkout: { ...remote, base: 'main' } });
print('-- its numbers end the details line, as a button; the proof goes in their card');
print(metaHTML({ s: chRow, kind: 'idle' }));
state.reading = { sessionId: 'me', mode: 'changes' };
show('pressed while its changes are open', countsHTML(chRow, 'idle').includes('counts on'));
state.reading = { sessionId: 'me', mode: 'writings' };
show('…not while what it wrote is', countsHTML(chRow, 'idle').includes('counts on'));
state.reading = null;
show('nothing changed: no numbers', countsHTML(session({ changes: { added: 0, removed: 0, files: [] } }), 'idle'));
show('the branch, from its side: itself, the others biggest first, then outside these sessions', branchParts(chRow, chSessions));
show('…from the other session\'s', branchParts({ ...chRow, sessionId: 'tests' }, chSessions).parts.map((p) => p.name));
state.last = { sessions: chSessions, now: NOW };
print(changesCardHTML(chRow, 'built · tested'));
const chHunk = { oldStart: 10, newStart: 10, lines: [[' ', 'def a():'], ['-', '    old()', 'me'], ['-', '    older()', 'me'],
                                                   ['+', '    new()', 'me'], [' ', ''], ['+', '# tested', 'tests']] };
const chView = { scope: 'session', v: 4, files: [
  { path: 'billing/retry.py', status: 'new', saved: false, counts: { me: [20, 0], tests: [1, 0] }, hunks: [chHunk] },
  { path: 'docs/retries.md', status: 'changed', saved: true, counts: { me: [6, 13] }, hunks: [] }] };
show('its own files: not staged yet, then staged whole', changeGroups(chView, 'me', chSessions).map((g) => [g[0], g[2].map((f) => f.path)]));
const chBranch = { scope: 'branch', files: [...chView.files,
  { path: 'tests/test_retry.py', status: 'new', counts: { tests: [23, 0] }, hunks: [] },
  { path: 'config/settings.py', status: 'changed', counts: { outside: [2, 1] }, hunks: [] },
  { path: 'billing/queue.py', status: 'new', counts: { short: [40, 0] }, hunks: [] }] };
show('the branch\'s: by whose, a file under the first to change it',
     changeGroups(chBranch, 'me', chSessions).map((g) => [g[0], g[1], g[2].map((f) => f.path)]));
show('a file\'s count: its own lines in its view, everyone\'s in the branch\'s',
     [fileCount(chView.files[0], 'me', 'session'), fileCount(chView.files[0], 'me', 'branch')]);
show('its line in the list', [fileLine(chView.files[0], 'me', 'session', chSessions, chMine.files[0], NOW),
                              fileLine(chView.files[1], 'me', 'session', chSessions, chMine.files[1], NOW),
                              fileLine(chView.files[0], 'me', 'branch', chSessions, null, NOW)]);
show('…and its group in the branch\'s list is just other changes',
     changeGroups({ ...chBranch, complete: false }, 'me', chSessions).map((g) => g[0]));
const chUnknown = session({ sessionId: 'me', name: 'Retry queue', checkout: { ...remote, base: 'main' },
  changes: { known: false, added: 1514, removed: 137, files: [], parts: {}, v: 5 } });
print('-- a session whose changes aren\'t known: the branch\'s numbers on its row, quieter, and a card saying why');
print(countsHTML(chUnknown, 'idle'));
print(changesCardHTML(chUnknown, 'built'));
show('…its branch switch has the branch\'s total', branchParts(chUnknown, chSessions).total);
const chBlind = blindView(chBranch);
show('…and its view names no one: files by how far they\'ve got, each just new or changed',
     [changeGroups(chBlind, 'me', chSessions).map((g) => [g[0], g[2].length]),
      fileLine(chBlind.files[0], 'me', 'branch', chSessions, null, NOW)]);
show('side by side: taken-out lines beside the ones put in after them', splitRows(chHunk).map(([l, r]) =>
  [l && `${l.at}${l.line[0]}`, r && `${r.at}${r.line[0]}`]));
show('unchanged lines before a hunk, and between two', [linesBetween(null, chHunk),
     linesBetween(chHunk, { oldStart: 30, newStart: 30, lines: [] })]);
show('where Open in Editor opens it: the first line the session put in, or anyone in the branch\'s view',
     [firstChangedLine(chView.files[0], 'me', 'session'), firstChangedLine(chView.files[0], 'tests', 'session'),
      firstChangedLine(chView.files[1], 'me', 'session')]);
show('a little colour for code', [codeHTML('  // a <note>'), codeHTML('say("hi") + \'x\''), codeHTML('# heading')]);
show('…and none for prose', [codeHTML("# Claude's own \"words\"", 'docs/a.md'), codeHTML("it's Claude's", 'notes.txt')]);
const chState = { scope: 'session', views: { session: chView }, path: null, layout: 'all', split: false, seen: null };
print('-- the list of its files, the first lit');
print(changesShelfHTML(chRow, chState));
print('-- its changes inline: another session\'s line quiet, under whose it is; the file\'s head with Open in Editor');
state.editors = { apps: [{ id: 'com.microsoft.VSCode', name: 'Visual Studio Code' }] };
print(changesBodyParts(chRow, chState, chView).map((p) => p.html).join(''));
print('-- side by side, and the first Open in Editor asking which editor; a line new since the last view lit');
Object.assign(chState, { split: true, picking: 'billing/retry.py' });
chHunk.lines.push(['+', 'def later():', 'me']);
print(changesBodyParts(chRow, chState, chView).map((p) => p.html).join(''));
print('-- once an editor is chosen, it\'s named on the button');
state.editors = { apps: state.editors.apps, choice: 'com.microsoft.VSCode' };
Object.assign(chState, { split: false, picking: null, layout: 'one', path: 'docs/retries.md' });
print(changesBodyParts(chRow, chState, chView).map((p) => p.html).join(''));
state.editors = { apps: [] };

section('New conversations');
const startable = [
  session({ sessionId: 'n1', name: 'api', cwd: '/work/api', git: { branch: 'main', root: '/work/api' }, lastPromptAt: min(30) }),
  session({ sessionId: 'n2', name: 'app work', lastPromptAt: min(5) }),
  session({ sessionId: 'n3', cwd: '/work/app-wt', lastPromptAt: min(2),
            git: { branch: 'feat', root: '/work/app-wt', worktree: 'app-wt', worktreeOf: 'app', mainRoot: '/work/app' } }),
  session({ sessionId: 'n4', cwd: '/Users/me/Library/Application Support/Claude/scratch-workspaces/x1', git: null,
            lastPromptAt: min(1) }),
];
show('the folders a card offers, newest first (a worktree counts as its repo; scratch is left out)',
     startProjects(startable));
show('where a card starts: the session marked as the one you\'re on, in Claude or Ghostty',
     defaultStartFolder(startable.map((s) => (s.sessionId === 'n1' ? { ...s, focused: true } : s)), null));
show('…else the one the list keeps in place for you', defaultStartFolder(startable, 'n1'));
show('…else the newest', defaultStartFolder(startable, null));
show('…nowhere with nothing listed', defaultStartFolder([], null));
const startCard = { id: 'card1', folder: '/work/app', name: 'app', app: 'desktop', text: '', problem: null };
show('the card while the app is asked about its folder', startState(startCard, {}));
show('…a folder Claude has worked in, with no words', startState(startCard, { '/work/app': { trusted: true } }));
show('…with words', startState({ ...startCard, text: 'fix the build' }, { '/work/app': { trusted: true } }));
show('…a folder Claude hasn\'t worked in', startState({ ...startCard, text: 'fix it' }, { '/work/app': { trusted: false } }));
show('…a folder that has gone', startState(startCard, { '/work/app': { gone: true } }));
show('…no folder yet', startState({ ...startCard, folder: null, name: 'Choose a folder' }, {}));
show('…why the last one didn\'t start, still asking about trust',
     startState({ ...startCard, problem: 'Claude was busy saving its settings: try again' }, { '/work/app': { trusted: false } }));
print('-- the card in Claude, with Ghostty to switch to, asking about trust');
state.startOptions = { terminal: 'Ghostty' };
state.folders = { '/work/app': { trusted: false } };
print(startCardHTML({ ...startCard, text: 'Add <b>dark</b> mode' }, startable));
print('-- in Ghostty, in a worktree');
state.folders = { '/work/app-wt': { trusted: true } };
print(startCardHTML({ ...startCard, folder: '/work/app-wt', name: 'app-wt', app: 'terminal' }, startable));
print('-- with no terminal to switch to: only its icon');
state.startOptions = { terminal: null };
state.folders = { '/work/app': { trusted: true } };
print(startCardHTML(startCard, startable));
const startOf = (fields) => ({ id: 's1', key: 'u-1', folder: '/work/app', name: 'app', app: 'terminal',
                               words: 'write the tests', at: NOW, drawn: true, ...fields });
print('-- a start not listed yet, as a working row');
print(rowHTML(pendingSessions({ s1: startOf({}) }, startable, 'Ghostty')[0], 'busy', NOW));
print("-- one in Claude that waits on you, and one that didn't start");
print(rowHTML(pendingSessions({ s1: startOf({ app: 'desktop', note: "Your words are in Claude's message box: press Send there" }) },
                              startable, 'Ghostty')[0], 'busy', NOW));
print(rowHTML(pendingSessions({ s1: startOf({ why: 'Nothing started in Ghostty: look there for what Claude Code says' }) },
                              startable, 'Ghostty')[0], 'busy', NOW));
show('one still handing over in the box isn\'t drawn yet',
     pendingSessions({ s1: startOf({ drawn: false }) }, startable, 'Ghostty').length);
show('one Claude has listed isn\'t drawn again', pendingSessions({ s1: startOf({ key: 'n2' }) }, startable, 'Ghostty').length);
show('its row stays hidden while its card hands over', (state.starts = { s1: startOf({ key: 'n2', drawn: false }) },
                                                         startLanding('n2')));
show('…and while its copy rises to it', (state.starts = { s1: startOf({ key: 'n2', flying: true }) }, startLanding('n2')));
show('…but not once it has landed', (state.starts = { s1: startOf({ key: 'n2' }) }, startLanding('n2')));
forgetStarted(startable);
show('a start Claude has listed is let go once its row has landed', Object.keys(state.starts));
state.starts = { s1: startOf({ key: 'n2', flying: true }) };
forgetStarted(startable);
show('…not while its copy is still rising', Object.keys(state.starts));
state.starts = {};
state.folders = {};
globalThis.crypto = { getRandomValues: (bytes) => bytes.fill(0xab) };
show('a new session\'s id, where WebKit has no randomUUID: version 4, in lower case', newSessionId());
delete globalThis.crypto;

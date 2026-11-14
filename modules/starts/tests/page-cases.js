// The starts module's part of the page, run outside the app by test.sh: the folders a new conversation's card offers
// and the one it starts in, what the card says and asks, its HTML, and the pending row a start shows as until it's
// listed (starts.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

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
print('-- the card, starting in Claude with Ghostty in its menu, asking about trust');
state.startOptions = { terminal: 'Ghostty' };
state.folders = { '/work/app': { trusted: false } };
print(startCardHTML({ ...startCard, text: 'Add <b>dark</b> mode' }, startable));
print('-- in Ghostty, in a worktree');
state.folders = { '/work/app-wt': { trusted: true } };
print(startCardHTML({ ...startCard, folder: '/work/app-wt', name: 'app-wt', app: 'terminal' }, startable));
print('-- with Claude Desktop’s sessions not tracked: Ghostty, and no menu');
state.startOptions = { terminal: 'Ghostty', desktop: false, choice: false };
state.folders = { '/work/app': { trusted: true } };
print(startCardHTML(startCard, startable));
print('-- …with another terminal to pick: the menu stays');
state.startOptions = { terminal: 'Ghostty', desktop: false, choice: true };
print(startCardHTML(startCard, startable));
print('-- with no terminal to choose: Claude, and no menu');
state.startOptions = { terminal: null };
state.folders = { '/work/app': { trusted: true } };
print(startCardHTML(startCard, startable));
const startOf = (fields) => ({ id: 's1', key: 'u-1', folder: '/work/app', name: 'app', app: 'terminal',
                               words: 'write the tests', at: NOW, drawn: true, ...fields });
print('-- a start not listed yet, as a working row');
print(rowHTML(pendingSessions({ s1: startOf({}) }, startable, 'Ghostty')[0], 'busy', NOW));
show('…in the terminal it started in, though another is picked since',
     pendingSessions({ s1: startOf({ terminal: 'iTerm2' }) }, startable, 'Ghostty')[0].activity);
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

section('Where in its project: @ and #');
show('a name from your words', worktreeName('Add a dark mode switch, please'));
show('…words that say little keep what there is', worktreeName('Can you fix it?'));
show('…letters lose their accents, the rest goes', worktreeName('Réparer le café #42 (vite)'));
show('…an @ or a # is where it starts, not what it does', worktreeName('@api fix the login loop #hello from main'));
show('…at most four words, within 40 characters', worktreeName('rewrite the importer, exporter, scheduler and retry queue'));
show('…nothing to go on', worktreeName('  ?! '));
show('a name as you write it', cleanName('My  new Branch!/x..y--z'));
show('once settled, never ending in .lock', trimName('fix.lock'));
show('@ being written', startToken('fix the build @no'));
show('# being written', startToken('fix the build #fix-login'));
show('…with from', startToken('fix the build #fix-login from rel'));
show('…from, nothing after it yet', startToken('fix the build #fix-login from '));
show('…only right before the caret', startToken('#fix-login then more words'));
show('…not inside a word', startToken('mail me at someone@example'));
show('…an @ takes no from', startToken('fix @api from main'));
const projects = [{ folder: '/work/app', name: 'app' }, { folder: '/work/api', name: 'api' }, { folder: '/work/notes', name: 'notes' }];
show('@ offers the projects holding what follows it', projectChoices(projects, 'ap'));
const repo = { here: { path: '/work/app', where: '~/work/app', branch: 'main' },
               worktrees: [{ branch: 'usage', path: '/work/app-wt/usage', where: '~/work/app-wt/usage' }],
               branches: ['release'], base: 'main', folder: '~/work/app-worktrees',
               folderPath: '/work/app-worktrees' };
show('# offers its folder, its worktrees, its branches and a new worktree named from your words',
     worktreeChoices(repo, '', undefined, 'fix the login loop'));
show('…what holds what follows it', worktreeChoices(repo, 'us', undefined, 'fix the login loop'));
show('…a name that isn’t there: a new worktree by that name, from the base', worktreeChoices(repo, 'hello', undefined, ''));
show('…with from: a new worktree from each branch holding what follows', worktreeChoices(repo, 'hello', 're', ''));
show('…a branch that’s there isn’t offered as new', worktreeChoices(repo, 'release', undefined, ''));
show('in a worktree: one that’s there, a branch, a new one', [null, { kind: 'here' }, { kind: 'open' }, { kind: 'branch' }, { kind: 'new' }].map(inWorktree));

section('The card, in a repo');
state.startOptions = { terminal: 'Ghostty' };
state.folders = { '/work/app': { trusted: true } };
state.repos = { '/work/app': repo };
const startCard2 = (fields) => ({ id: 'card2', folder: '/work/app', name: 'app', app: 'desktop', text: 'fix the login loop',
                            problem: null, target: null, list: null, ...fields });
const fresh = { kind: 'new', name: 'hello', base: 'usage', named: true };
const freeHello = { name: 'hello', base: 'usage', path: '/work/app-worktrees/hello', where: '~/work/app-worktrees/hello' };
show('the app: as chosen, in its own folder', startApp(startCard2({})));
show('…the terminal for anything in a worktree', startApp(startCard2({ target: { kind: 'open', branch: 'usage' } })));
show('…Claude with no terminal to choose', (state.startOptions = { terminal: null }, startApp(startCard2({ app: 'terminal' }))));
show('…the terminal while Claude Desktop’s sessions aren’t tracked',
     (state.startOptions = { terminal: 'Ghostty', desktop: false }, startApp(startCard2({}))));
show('…nowhere, with no terminal either: Track Them', (state.startOptions = { terminal: null, desktop: false,
  installed: true }, cardState(startCard2({}))));
show('…nowhere, without Claude Desktop on the Mac: Get Claude Desktop', (state.startOptions = { terminal: null,
  desktop: false, installed: false }, cardState(startCard2({}))));
state.startOptions = { terminal: 'Ghostty' };
show('a new worktree waits for git to say it can be made', cardState(startCard2({ target: { ...fresh } })));
show('…an answer for another base is let go', cardState(startCard2({ target: { ...fresh, check: { ...freeHello, base: 'main' } } })));
show('…a name that’s taken', cardState(startCard2({ target: { ...fresh, check: { name: 'hello', why: "There's a branch named hello already: pick it with #hello, or rename this one" } } })));
show('…free', cardState(startCard2({ target: { ...fresh, check: freeHello } })));
show('…no name', cardState(startCard2({ target: { kind: 'new', name: '', base: 'main' } })));
show('a word while another agent works there', busyHint(startCard2({}), [session({ sessionId: 'w1', status: 'busy' })]));
show('…while changes wait there', busyHint(startCard2({}), [session({ sessionId: 'w1', checkout: { changes: 3 } })]));
show('…none once it starts in a worktree', busyHint(startCard2({ target: fresh }), [session({ sessionId: 'w1', status: 'busy' })]));
print('-- in its own folder, Claude at work there');
print(startCardHTML(startCard2({}), [...startable, session({ sessionId: 'w1', status: 'busy' })]));
print('-- # written: what it offers, the line under the box giving way to it');
print(startCardHTML(startCard2({ text: 'fix the login loop #', list: listFor(startCard2({}), startToken('fix the login loop #')) }), startable));
print('-- a new worktree from usage, its folder under the box');
print(startCardHTML(startCard2({ target: { ...fresh, check: freeHello } }), startable));
print('-- a worktree that’s there');
print(startCardHTML(startCard2({ target: { kind: 'open', branch: 'usage', path: '/work/app-wt/usage', where: '~/work/app-wt/usage' } }), startable));
print('-- @ written: the projects of the sessions listed, and any other folder');
const listed = state.last.sessions;
state.last.sessions = startable;
print(listHTML(startCard2({ list: listFor(startCard2({}), startToken('fix it @a')) })));
state.last.sessions = listed;
print('-- # outside git, and before the app has said what the repo has');
state.repos = { '/work/notes': { none: true, where: '~/work/notes' } };
print(listHTML(startCard2({ folder: '/work/notes', name: 'notes', list: listFor(startCard2({ folder: '/work/notes', name: 'notes' }), startToken('#')) })));
print(underHTML(startCard2({ folder: '/work/notes', name: 'notes' })));
print(listHTML(startCard2({ list: listFor(startCard2({}), startToken('#')) })));
const startOf2 = (fields) => ({ id: 's2', key: 'u-2', folder: '/work/app', name: 'app', app: 'terminal',
                                words: 'say hello', at: NOW, drawn: true, ...fields });
print('-- the row a new worktree starts as, and one in a worktree that’s there');
print(rowHTML(pendingSessions({ s2: startOf2({ worktree: 'hello', path: freeHello.path, makes: true }) }, startable, 'Ghostty')[0], 'busy', NOW));
print(rowHTML(pendingSessions({ s2: startOf2({ worktree: 'usage', path: '/work/app-wt/usage', makes: false }) }, startable, 'Ghostty')[0], 'busy', NOW));
print('-- what a card not sent yet keeps for the next one: nothing of yours in it, then your words, where in its project')
print('   (without what git said, asked again), and the project you chose')
const keptBy = (fields) => { state.dock = startCard2(fields); keepDraft(); state.dock = null; return state.startDraft; };
show('opened and closed', keptBy({ text: '  ' }));
show('words', keptBy({ app: 'terminal' }));
show('a new worktree', keptBy({ text: '', target: { ...fresh, check: freeHello } }));
show('a project chosen', keptBy({ text: '', folder: '/work/api', name: 'api', picked: true }));
state.startDraft = null;

section('Where a part has it start (where, under, warn, note)');
// A sample part standing in for another module's, saying what `sample` says: never a module's own.
const sample = { name: 'sample', where: () => sample.w, under: () => sample.u, warn: () => sample.x,
                 note: () => sample.n };
core.startCardParts.push(sample);
state.repos = { '/work/app': repo };
const followed = (fields, w) => {
  sample.w = w;
  const card = startCard2(fields);
  followWhere(card);
  return { target: card.target, followed: card.followed };
};
show('a name with a worktree on that branch: that worktree', followed({}, { name: 'usage' }));
show('…a branch with no folder: it, in a new folder', followed({}, { name: 'release' }));
show('…neither: a new worktree by that name, from the base, named', followed({}, { name: 'PAY 142!' }));
show('…the branch its own folder is on: its own folder', followed({}, { name: 'main' }));
show('…one of its folders, by path', followed({}, { path: '/work/app-wt/usage' }));
show('…its own folder', followed({ target: { kind: 'open', branch: 'usage' } }, { here: true }));
show('…nothing: where it was stays', followed({ target: { kind: 'branch', name: 'release' } }, null));
show('your own pick wins', followed({ chosen: true }, { name: 'usage' }));
show('the proposal going: where it was before comes back', (() => {
  const card = startCard2({ target: { kind: 'branch', name: 'release' } });
  sample.w = { name: 'usage' };
  followWhere(card);
  sample.w = null;
  followWhere(card);
  return { target: card.target, followed: card.followed };
})());
state.startOptions = { terminal: null };
show('no terminal: its own folder, worktrees starting only in one', followed({}, { name: 'usage' }));
state.startOptions = { terminal: 'Ghostty' };
state.repos['/work/notes'] = { none: true, where: '~/work/notes' };
show('outside git: nowhere else to go', followed({ folder: '/work/notes', name: 'notes' }, { name: 'usage' }));
show('where it would start now, for the parts', (() => {
  const card = startCard2({});
  sample.w = { name: 'pay-142' };
  followWhere(card);
  return cardPlace(card);
})());
show('…not followed while you picked it', cardPlace(startCard2({ chosen: true })));
show('a proposal isn’t kept for the next card', (() => {
  state.dock = startCard2({ text: '', target: { kind: 'new', name: 'pay-142', base: 'main', named: true },
                            followed: { key: 'name:pay-142', was: null } });
  keepDraft();
  state.dock = null;
  return state.startDraft;
})());
show('your own pick is kept for the next card, and wins there', (() => {
  state.dock = startCard2({ text: '', target: { kind: 'open', branch: 'usage', path: '/work/app-wt/usage' }, chosen: true });
  keepDraft();
  state.dock = null;
  return state.startDraft;
})());
show('…a proposal’s place isn’t, but where it was before is', (() => {
  state.dock = startCard2({ text: '', target: { kind: 'new', name: 'pay-142', base: 'main', named: true },
                            followed: { key: 'name:pay-142', was: { kind: 'branch', name: 'release' } } });
  keepDraft();
  state.dock = null;
  return state.startDraft;
})());
state.startDraft = null;
sample.waits = () => true;
show('a part still finding out where it starts holds Start', cardState(startCard2({})).go);
sample.waits = null;
show('…and lets it go once it knows', cardState(startCard2({})).go);
state.folders = { '/work/app': { trusted: false } };
show('where it would start now says Start would also trust the folder', cardPlace(startCard2({ text: 'go' })).trust);
state.folders = { '/work/app': { trusted: true } };
sample.w = null;
sample.u = '<div class="c-under sample-line" data-k="u">Its own line</div>';
print('-- a part’s line in place of the card’s');
print(startCardHTML(startCard2({}), startable));
print('-- …not once you picked where yourself');
print(startCardHTML(startCard2({ chosen: true }), startable));
sample.u = null;
sample.n = 'Start also does <this>, as text.';
print('-- a part’s note under the card’s line, as text');
print(startCardHTML(startCard2({}), startable));
sample.n = null;
sample.x = { text: 'Another sample is at work here.', name: 'sample-1' };
print('-- a part’s warning in the busy notice’s place, its button naming its worktree');
print(startCardHTML(startCard2({}), startable));
state.startOptions = { terminal: null };
print('-- …with no terminal: the words alone');
print(startCardHTML(startCard2({}), startable));
state.startOptions = { terminal: 'Ghostty' };
sample.x = null;
core.startCardParts.splice(core.startCardParts.indexOf(sample), 1);
state.startDraft = null;
state.repos = {};
state.folders = {};

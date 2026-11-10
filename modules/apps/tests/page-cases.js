// The panel's back's logic, run outside the app by modules/apps/tests/test.sh: Settings' cards and pages, and the
// settings once one is pressed; what an app's page says of what macOS lets Whozmove do with it, what its cards show,
// the apps' switches once one is pressed, and a tool's card (apps.js). Nothing is drawn.
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
show('full disk access, denied', permissionView(app({ kind: 'fullDiskAccess', use: 'Lets the map look inside',
                                                     state: 'denied' })));
show('nothing to allow', permissionView(app(null)));
show('a permission the page doesn’t know', permissionView(app({ kind: 'camera', state: 'allowed' })));

section('Cards');
const card = (more) => ({ key: 'tools', title: 'Apple’s command line developer tools', section: 'Developer tools',
                          said: 'Not installed', note: 'Git needs them.', ok: false, button: 'Install', busy: false,
                          ...more });
show('with its button', statusView(card()));
show('all’s well: its tick, and no button', statusView(card({ said: 'Installed', ok: true, button: undefined })));
show('a press under way: its button waits', statusView(card({ busy: true })));
show('under way with no button: nothing waits', statusView(card({ button: undefined, busy: true })));
show('no heading over it', statusView(card({ section: null })));
show('nothing more than its heading', statusView({ key: 'plugin', title: 'Whozmove’s plugin' }));
show('no heading: not drawn', statusView({ key: 'plugin' }));
show('nothing', statusView(null));

section('Switches');
const on = (apps) => apps && apps.map((a) => `${a.id}: ${a.switches.map((s) => `${s.key} ${s.on ? 'on' : 'off'}`)
  .join(', ')}`);
const apps = [
  { id: 'ghostty', switches: [{ key: 'startHere', on: true, group: 'startTerminal', enabled: true }] },
  { id: 'iterm2', switches: [{ key: 'startHere', on: false, group: 'startTerminal', enabled: true }] },
  { id: 'spotify', switches: [{ key: 'song', on: true, group: null, enabled: true },
                              { key: 'lyrics', on: false, group: null, enabled: true }] },
  { id: 'git', switches: [{ key: 'nextSteps', on: false, group: null, enabled: false },
                          { key: 'deploy', on: true, group: null, enabled: true }] },
];
show('turning lyrics on', on(afterPress(apps, 'spotify', 'lyrics')));
show('turning the song off', on(afterPress(apps, 'spotify', 'song')));
show('the other terminal picked: the first goes off', on(afterPress(apps, 'iterm2', 'startHere')));
show('the picked terminal pressed again: it stays', afterPress(apps, 'ghostty', 'startHere'));
show('Show Next Steps without Apple’s developer tools: nothing', afterPress(apps, 'git', 'nextSteps'));
show('Show Deploy, pressable while the next steps are off', on(afterPress(apps, 'git', 'deploy')));
show('a switch that isn’t there', afterPress(apps, 'spotify', 'volume'));
show('an app that isn’t there', afterPress(apps, 'zoom', 'song'));
show('the apps it was given are left as they were', on(apps));

section('A tool’s card');
const toolCard = (fields) => ({ figure: '18 GB free', of: 'of 460 GB', bar: 0.96, tone: 'low',
                                lines: ['Full in about 6 days at this pace'], ...fields });
show('low', cardView(toolCard()));
show('nearly out', cardView(toolCard({ tone: 'severe' })));
show('plenty', cardView(toolCard({ tone: null, bar: 0.4, lines: [] })));
show('a bar past either end', [cardView(toolCard({ bar: 1.4 })).bar, cardView(toolCard({ bar: -0.2 })).bar]);
show('no bar', cardView(toolCard({ bar: undefined })).bar);
show('a tone the page doesn’t know', cardView(toolCard({ tone: 'purple' })).tone);
show('lines that aren’t words', cardView(toolCard({ lines: ['A line', 42, '', null] })).lines);
show('no figure', cardView(toolCard({ figure: '' })));
show('nothing', cardView(null));
show('what it can’t do without its permission', cardView(toolCard({ need: 'Desktop isn’t in the map yet.' })).need);
show('nothing it needs', cardView(toolCard()).need);
show('a need that isn’t words', cardView(toolCard({ need: 42 })).need);
show('its buttons', cardView(toolCard({ actions: [{ id: 'map', title: 'Open the Map', main: true },
                                                  { id: 'x', title: '' }, { title: 'No id' }, null] })).actions);

section('An app’s groups');
// A tool's page as the app sends it: its own groups, under its switch, which dims them while it's off, and a group
// another module adds, which it doesn't.
const tool = (on, more) => ({ id: 'sample-tool', switches: [], recommended: true, groups: [
  { title: null, foot: 'Settings ▸ Sample Tool opens this page.', enabled: true,
    rows: [{ kind: 'switch', key: 'on', title: 'Sample Tool', help: 'The one thing.', on, enabled: true }] },
  { title: 'Who may send', foot: 'A session that may not is told so.', enabled: on, rows: [
    { kind: 'choice', key: 'who', title: 'Who may send', value: 'any', fixed: null, enabled: true, choices: [
      { id: 'any', name: 'Any session', help: 'Every agent can.', isNew: false, enabled: true },
      { id: 'lead', name: 'Only a team’s chief', help: 'The others are told why.', isNew: true, enabled: true },
      { id: 'allowed', name: 'Only those you’ve allowed', help: '', isNew: false, enabled: false }] }] },
  { title: 'Quiet hours', foot: null, enabled: true, rows: [
    { kind: 'switch', key: 'quiet', title: 'Quiet hours', help: '', on: false, enabled: true, isNew: true },
    { kind: 'time', key: 'quietHours', title: 'Hours', help: 'Only what’s urgent.', from: 1320, to: 480,
      fromSaid: '22:00', toSaid: '08:00', enabled: false }] },
  { title: 'What comes first', foot: null, enabled: on, rows: [
    { kind: 'choice', key: 'next', title: 'What comes first', value: 'picks', enabled: true,
      fixed: { name: 'Urgent ones, always', help: 'First, whatever else you choose.' },
      choices: [{ id: 'picks', name: 'Then a chief’s picks' }, { id: 'oldest', name: 'Then the oldest' }] }] },
  { title: null, foot: 'A change applies to what comes next.', enabled: true, rows: [] },
], ...more });
show('on: each group, its rows and whether they can be pressed', groupsView(tool(true)));
show('off: its own groups dimmed, the other module’s not', groupsView(tool(false)).map((g) => `${g.title || '(none)'}: `
  + g.rows.map((r) => `${r.key}${r.off ? ' off' : ''}`).join(', ')));
show('rows the page doesn’t know, or with no key, left out', groupsView({ groups: [{ title: 'Odd', rows: [
  { kind: 'slider', key: 'volume' }, { kind: 'switch', title: 'No key' }, null,
  { kind: 'choice', key: 'c', choices: [{ id: 'a', name: 'A' }, { name: 'No id' }], fixed: { help: 'No name' } }] }] }));
show('a choice with nothing to pick, only the row above that can\'t be pressed: no radio group under it',
     groupRowHTML({ kind: 'choice', key: 'order', title: 'What comes first', choices: [], value: null,
                    fixed: { name: 'Each ticket\'s own priority', help: 'Always.' } }));
show('no groups', [groupsView({}), groupsView(null), groupsView({ groups: 'groups' })]);
const pages = (on) => [tool(on), { id: 'git', switches: [{ key: 'deploy', on: true, group: null, enabled: true }] }];
const groupOf = (apps, key) => apps && groupsView(apps[0]).flatMap((g) => g.rows).find((r) => r.key === key);
show('a switch in a group turned on', groupOf(afterPress(pages(true), 'sample-tool', 'quiet'), 'quiet')?.on);
show('turning the tool off', groupOf(afterPress(pages(true), 'sample-tool', 'on'), 'on')?.on);
show('a switch in a dimmed group: nothing', afterPress([{ ...tool(true), groups: [{ enabled: false,
  rows: [{ kind: 'switch', key: 'why', on: false }] }] }], 'sample-tool', 'why'));
show('the other app’s switches are left as they were', on(afterPress(pages(true), 'sample-tool', 'quiet').slice(1)));
show('Only a team’s chief picked', groupOf(afterChoice(pages(true), 'sample-tool', 'who', 'lead'), 'who')?.value);
show('one that can’t be picked now', afterChoice(pages(true), 'sample-tool', 'who', 'allowed'));
show('the one already picked', afterChoice(pages(true), 'sample-tool', 'who', 'any'));
show('one that isn’t among its choices', afterChoice(pages(true), 'sample-tool', 'who', 'everyone'));
show('a choice in a dimmed group', afterChoice(pages(false), 'sample-tool', 'who', 'lead'));
show('a choice that isn’t there', afterChoice(pages(true), 'sample-tool', 'colour', 'red'));
show('the apps it was given are left as they were', groupOf(pages(true), 'who').value);
// A group that matters more than most, and a choice whose change shows first.
const weighed = { id: 'sample-tool', name: 'Sample Tool', switches: [], groups: [{ title: 'Who may send', important: true,
  enabled: true, rows: [{ kind: 'choice', key: 'who', title: 'Who may send', value: 'any', enabled: true,
  choices: [{ id: 'any', name: 'Any session' }, { id: 'lead', name: 'Only a team’s chief' }],
  confirms: { lead: { before: 'Any session sends', after: 'Only a team’s <b>chief</b> sends', warn: 'The others are told why.',
                      keep: null }, any: { before: 'x' }, gone: { before: 'a', after: 'b' } } }] }] };
show('important, and what picking each would change: only the choices it has, whole', groupsView(weighed));
bk.apps = [weighed];
bk.stack = ['apps', 'app:sample-tool'];
print(groupsHTML(weighed));
bk.confirm = { app: 'sample-tool', key: 'who', value: 'lead' };
print('-- Only a team’s chief pressed: its before and after, with Keep It and Change');
print(groupsHTML(weighed));
bk.confirm = { app: 'another', key: 'who', value: 'lead' };
show('…not on another app’s page', /b-ba/.test(groupsHTML(weighed)));
bk.confirm = null;
// A row opening a page of its own, and a choice there drawn as one row with the Mac's menu of them.
const paged = { id: 'sample-tool', name: 'Sample Tool', switches: [], glyph: 'ticket', groups: [{ title: 'Places',
  enabled: true, rows: [{ kind: 'page', key: 'north', title: 'North', said: 'Here', groups: [{ title: 'North’s',
  enabled: true, rows: [{ kind: 'choice', key: 'where', title: 'Where North’s go', value: 'here', enabled: true,
  menu: true, fixed: { name: 'Where North’s go', help: 'Picked from a <b>menu</b>' },
  choices: [{ id: 'here', name: 'Here' }, { id: 'there', name: 'There' }] }] }] }] }] };
show('a row opening a page of its own, and its rows found within it', rowsIn(paged.groups).map((r) => `${r.kind} ${r.key}`));
show('…the row by its key', pageRowOf(paged, 'north')?.title);
bk.apps = [paged];
bk.stack = ['apps', 'app:sample-tool'];
print(groupsHTML(paged));
bk.stack = ['apps', 'app:sample-tool', 'sub:sample-tool:north'];
show('on its page: its app, and the row', { app: subHere()?.app.id, row: subHere()?.row.title });
print(bodyHTML());
show('a choice there, picked', groupOf(afterChoice([paged], 'sample-tool', 'where', 'there'), 'where')?.value
  ?? rowsIn(afterChoice([paged], 'sample-tool', 'where', 'there')[0].groups).find((r) => r.key === 'where').value);
show('a tool’s tile with a mark of Settings’', iconHTML(paged, 40));
show('a menu choice whose pick has gone asks for one', /Choose…/.test(groupRowHTML({ ...rowsIn(paged.groups)[1],
  value: '/gone' })));
show('shown on the page a row opens', showingStack('sample-tool', 'north'));
show('…or on the app’s own, when there’s no such row', showingStack('sample-tool', 'nowhere'));
show('a row opening a page in a dimmed group: nothing to press', /data-go/.test(groupRowHTML({ kind: 'page', key: 'north',
  title: 'North', said: '', groups: [], off: true })));
bk.apps = [];
bk.stack = ['apps'];

section('A tile’s letter');
show('a name', initialOf('git'));
show('no name', initialOf(''));

section('Settings');
const settings = [
  { key: 'look', kind: 'choice', title: 'Look', glyph: 'look', group: 10, page: 'Appearance', style: 'looks',
    value: 'grey', choices: [{ id: 'grey', name: 'Grey' }, { id: 'black', name: 'Black' },
                             { id: 'glass', name: 'Glass', enabled: false }] },
  { key: 'appearance', kind: 'choice', title: 'Light or Dark', glyph: 'look', group: 10, page: 'Appearance',
    value: 'system', foot: 'Match the Mac follows System Settings ▸ Appearance.',
    choices: [{ id: 'system', name: 'Match the Mac' }, { id: 'light', name: 'Light' }, { id: 'dark', name: 'Dark' }] },
  { key: 'ownChoice', kind: 'choice', title: 'A Choice of Its Own', glyph: 'list', group: 10, page: null, value: 'one',
    choices: [{ id: 'one', name: 'One' }, { id: 'two', name: 'Two' }] },
  { key: 'openWith', kind: 'choice', title: 'Open Files With', glyph: 'file', group: 10, page: null, value: null,
    choices: [{ id: 'com.example.editor', name: 'Example Editor' }] },
  { key: 'shortcut', kind: 'switch', title: 'New Conversation with ⌃⌥N', glyph: 'keys', group: 20, on: true,
    foot: '⌃⌥N opens the new conversation card from any app.' },
  { key: 'later', kind: 'switch', title: 'A setting on an earlier card', glyph: 'none', group: 5, on: false },
  { key: 'sampleTool', kind: 'page', title: 'Sample Tool', glyph: '', group: 20, app: 'sample-tool', said: 'On' },
  { key: 'nowhere', kind: 'page', title: 'A page row with no app', glyph: '', group: 20, said: 'On' },
];
show('the cards: a page’s choices on one row, the cards by their order', settingsCards(settings));
show('no settings', settingsCards(undefined));
show('a choice with nothing to pick from', settingValue({ kind: 'choice', choices: [], value: null }));
show('a choice not made yet', settingValue(settings[3]));
show('Appearance’s page', settingsPage(settings, 'Appearance').map((e) => e.key));
show('a choice with no page named: a page of its own', settingsPage(settings, 'A Choice of Its Own').map((e) => e.key));
show('a switch has no page', settingsPage(settings, 'New Conversation with ⌃⌥N'));
const set = (key, value) => afterSetting(settings, key, value)?.find((e) => e.key === key);
show('Black picked', set('look', 'black')?.value);
show('Glass, which can’t be picked now', set('look', 'glass'));
show('the one already picked', set('look', 'grey'));
show('a choice that isn’t one of its choices', set('look', 'purple'));
show('the switch turned off', set('shortcut', false)?.on);
show('the switch turned on again, though it’s on', set('shortcut', true));
show('a switch given a choice', set('shortcut', 'black'));
show('a setting that isn’t there', set('volume', true));
show('the settings it was given are left as they were', settings.map((e) => e.value ?? e.on));

section('A list (Sessions)');
const listed = (items, more) => ({ key: 'sessions', title: 'Sessions', count: items.length,
  tray: { hint: 'None ticked', action: 'Move to Trash', actionKey: 'trash',
          pick: { mark: 'ended', title: 'Tick All Ended ({n})', untitle: 'Untick Ended' },
          ask: { one: 'Move {name} to the Trash?', many: 'Move {n} conversations to the Trash?',
                 lead: { one: 'It goes to the Trash.', many: 'Each goes to the Trash on its own.' },
                 notes: [{ mark: 'open', alone: 'It’s still open, so it’s ended first.',
                           one: '1 still open is ended first.', many: '{n} still open are ended first.' },
                         { mark: 'unread', alone: 'It has a reply you haven’t read.',
                           one: '1 has a reply you haven’t read.', many: '{n} have replies you haven’t read.' }],
                 last: 'Your typed prompts stay in Claude Code’s history.' } },
  sections: [{ title: 'shop', tickable: true, items }, { title: 'In the Trash', tickable: false,
                                                          items: [{ id: 'gone', title: 'Gone', line: 'shop' }] }],
  ...more });
const conv = (id, marks, more) => ({ id, title: `Talk ${id}`, line: 'Ended 3 h ago', marks, ...more });
const sessions = listed([conv('a', ['ended']), conv('b', ['open', 'unread']), conv('c', ['ended', 'unread']),
                         conv('d', ['open'],
                              { why: 'Working: stop it first', way: { key: 'go', title: 'Take me there' } })]);
show('found on its app', listOf([{ id: 'app', lists: [sessions] }], 'app', 'sessions')?.title);
show('not on that app', listOf([{ id: 'app', lists: [sessions] }], 'other', 'sessions'));
show('what can be ticked', listItems(sessions).map((i) => `${i.id}${i.tickable ? '' : ' (no)'}`));
show('ticked, one of them working now', listTicks(sessions, new Set(['a', 'd', 'gone'])));
show('Tick All Ended, none ticked', listPick(sessions, new Set()));
show('Tick All Ended, all of them ticked', listPick(sessions, new Set(['a', 'c'])));
show('no item has the mark', listPick(listed([conv('b', ['open'])]), new Set()));
show('the question, one ended', listAsk(sessions, ['a']));
show('the question, one open with a reply unread', listAsk(sessions, ['b']));
show('the question, three', listAsk(sessions, ['a', 'b', 'c']));
show('the question, nothing ticked', listAsk(sessions, []));
show('what was done, just now', listSaidShows({ at: 1000 }, 0, 2000));
show('what was done, long ago', listSaidShows({ at: 1000 }, 0, 1000 + LIST_SAID_MS + 1));
show('what was done, long ago, but held by the pointer', listSaidShows({ at: 1000 }, 99999, 50000));
show('nothing done', listSaidShows(null, 0, 1));
show('what was done, just now, then something ticked', listSaidShows({ at: 1000 }, 0, 2000, 1000));
show('what was done after something was ticked', listSaidShows({ at: 3000 }, 0, 3500, 1000));

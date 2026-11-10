// The tickets module's part of the page, run outside the app by test.sh: the Ticket chip and its list on the new
// conversation card in every state, the line a start adds to your words, a link found in your words, a row's tag and
// the card pointing at it shows, each as a ticket is read, can't be read or is waited for, with its last move and a
// step marked as a person's, the card asking to use a ticket, the card asking to move it, and the card asking to create
// one, in each of its states (ticket-words.js). Made-up tickets on a made-up site; nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const jira = (signIn, more = {}) => ({ name: 'Jira', signInName: 'Atlassian', signIn, sites: signIn === 'in'
  ? ['acme.atlassian.net'] : [], why: '', ...more });
const ticket = {
  tracker: 'Jira', site: 'acme.atlassian.net', key: 'PAY-142', link: 'https://acme.atlassian.net/browse/PAY-142',
  title: 'Login button does nothing on Safari', type: 'Bug', priority: 'High',
  state: { name: 'In Progress', kind: 'doing' }, parent: { key: 'PAY-120', title: 'Checkout works in every browser' },
  groups: [{ id: 'PAY', kind: 'project', name: 'Payments', sprint: 'Sprint 14' },
           { id: '3', kind: 'board', name: 'Payments board', sprint: 'Sprint 14' }],
  steps: [{ id: '31', name: 'Send to review', to: { name: 'In Review', kind: 'doing' } },
          { id: '11', name: 'Back to To Do', to: { name: 'To Do', kind: 'todo' } }],
};
const shown = (more) => ({ q: '', items: [], sel: 0, asked: 1, answered: true, ...more });

section('The card: the Ticket chip');
show('no ticket yet', ticketChipHTML(null));
show('one picked', ticketChipHTML(ticket));
show('its words <escaped>', ticketChipHTML({ ...ticket, key: 'PAY-1', title: 'A <b>bold</b> "title"' }));
show('what the box says then', ticketPlaceholder(ticket));
show('the line a start adds', ticketStartLine(ticket));
show('…for one with no link', ticketStartLine({ tracker: 'Jira', key: 'PAY-142' }));
const create = { create: true, tracker: 'Jira', site: 'acme.atlassian.net' };
show('Create a ticket picked', ticketChipHTML(create));
show('…what the box says then', ticketPlaceholder(create));
show('…the line a start adds', ticketStartLine(create));
show('…signed in to two sites, so it names none', ticketStartLine({ ...create, site: '' }));

section('The card: a link in your words');
show('a ticket\'s link', ticketLinkIn('Fix https://acme.atlassian.net/browse/PAY-142, please'));
show('…in brackets', ticketLinkIn('(see https://acme.atlassian.net/browse/PAY-142)'));
show('…plain http is no link', ticketLinkIn('http://acme.atlassian.net/browse/PAY-142'));
show('…none', ticketLinkIn('Fix the login button'));

section('The card: the list');
show('closed', ticketListHTML(null, [jira('in')]));
show('signed out', ticketListHTML(shown(), [jira('out')]));
show('…a sign-in that wasn\'t finished', ticketListHTML(shown(), [jira('out', { why: 'Sign-in wasn’t finished' })]));
show('signing in', ticketListHTML(shown(), [jira('signing')]));
show('blocked by an admin', ticketListHTML(shown(), [jira('blocked', {
  why: 'acme’s Jira admin hasn’t let apps sign in from this Mac yet. They can allow it once, for everyone.' })]));
show('…what to ask, copied', ticketListHTML(shown(), [jira('blocked')], true));
show('run out', ticketListHTML(shown(), [jira('expired')]));
show('…kept where other apps can read it', ticketListHTML(shown(), [jira('expired', {
  why: 'The sign-in kept on this Mac could be read by other apps, so Whozmove won’t use it: sign in again.' })]));
show('a new build, which macOS asks about first', ticketListHTML(shown(), [jira('allow')]));
show('no tracker at all', ticketListHTML(shown(), []));
show('looking', ticketListHTML(shown({ q: 'login', answered: false }), [jira('in')]));
show('found', ticketListHTML(shown({ q: 'login', items: [ticket, { ...ticket, key: 'PAY-131', title: 'Login page is slow',
  state: { name: 'To Do', kind: 'todo' }, groups: [] }], sel: 1 }), [jira('in')]));
show('found, signed in to two sites', ticketListHTML(shown({ items: [{ ...ticket, site: 'beta.atlassian.net' }] }),
  [jira('in', { sites: ['acme.atlassian.net', 'beta.atlassian.net'] })]));
show('a long title, words to escape', ticketListHTML(shown({ items: [{ ...ticket, title: 'A very long title '.repeat(8)
  + '<script>x</script>' }] }), [jira('in')]));
show('none found', ticketListHTML(shown({ q: 'nothing like it' }), [jira('in')]));
show('…a long search, cut', ticketListHTML(shown({ q: 'a search far longer than the list has room to say' }), [jira('in')]));
show('nothing of yours open', ticketListHTML(shown(), [jira('in')]));
show('Create a ticket picked with the keys', ticketListHTML(shown({ q: 'login', items: [ticket], sel: 1 }), [jira('in')]));
show('can\'t reach it', ticketListHTML(shown({ q: 'login', end: 'failed' }), [jira('in')]));
show('asked to slow down', ticketListHTML(shown({ q: 'login', end: 'slow' }), [jira('in')]));
show('a link from a site you aren\'t signed in to', ticketListHTML(shown({ q: 'https://beta.atlassian.net/browse/X-1',
  picked: { key: 'X-1', end: 'elsewhere', site: 'beta.atlassian.net' } }), [jira('in')]));
show('a key, with two sites', ticketListHTML(shown({ q: 'X-1', picked: { key: 'X-1', end: 'site' } }), [jira('in')]));
show('a link that couldn\'t be read', ticketListHTML(shown({ q: 'https://acme.atlassian.net/browse/PAY-1',
  picked: { key: 'PAY-1', end: 'failed' } }), [jira('in')]));
show('…a sign-in that ran out as it was read', ticketListHTML(shown({ q: 'PAY-1', picked: { key: 'PAY-1', end: 'signIn' } }),
  [jira('in')]));
show('…macOS asks first', ticketListHTML(shown({ q: 'PAY-1', picked: { key: 'PAY-1', end: 'allow' } }), [jira('in')]));
show('a search with a sign-in that ran out', ticketListHTML(shown({ q: 'login', end: 'signIn' }), [jira('in')]));
show('…one kept where other apps can read it', ticketListHTML(shown({ q: 'login', end: 'signIn',
  why: 'The sign-in kept on this Mac could be read by other apps, so Whozmove won’t use it: sign in again.' }),
  [jira('in')]));
show('a search that reaches no site', ticketListHTML(shown({ q: 'login', end: 'notFound',
  why: 'Your Atlassian account reaches no Jira site' }), [jira('in')]));
show('a key there\'s no ticket for', ticketListHTML(shown({ q: 'PAY-999', picked: { key: 'PAY-999', end: 'notFound' } }),
  [jira('in')]));

section('The row: its tag');
show('none', ticketTagHTML('s1', undefined));
show('started from Create a ticket, none yet', ticketTagHTML('s1', undefined, 'Jira'));
show('…and once it has one', ticketTagHTML('s1', ticket, 'Jira'));
show('reading', ticketTagHTML('s1', { key: 'PAY-142', tracker: 'Jira', reading: true }));
show('read', ticketTagHTML('s1', ticket));
show('done', ticketTagHTML('s1', { ...ticket, state: { name: 'Done', kind: 'done' } }));
show('dropped', ticketTagHTML('s1', { ...ticket, state: { name: 'Won’t Do', kind: 'dropped' } }));
show('a kind it doesn\'t know counts as to do', ticketTagHTML('s1', { ...ticket, state: { name: 'Odd', kind: 'odd' } }));
show('couldn\'t read it', ticketTagHTML('s1', { key: 'PAY-142', problem: { kind: 'failed', why: 'Couldn’t reach it' } }));
show('…read before, so it says where it stood', ticketTagHTML('s1', { ...ticket, problem: { kind: 'failed' } }));
show('sign in again', ticketTagHTML('s1', { ...ticket, problem: { kind: 'signIn' } }));
show('allow its sign-in', ticketTagHTML('s1', { ...ticket, problem: { kind: 'allow' } }));
show('asked to slow down', ticketTagHTML('s1', { key: 'PAY-142', problem: { kind: 'slow', retryAt: NOW } }));

section('The row: its card');
show('read', ticketCardHTML(ticket, 'Atlassian'));
show('one project, no parent, no steps', ticketCardHTML({ ...ticket, parent: undefined, steps: [],
  groups: [{ name: 'Web', kind: 'project' }] }, 'Atlassian'));
show('several boards, a team', ticketCardHTML({ ...ticket, groups: [{ name: 'Payments board', kind: 'board' },
  { name: 'Checkout', kind: 'team' }, { name: 'Web board', kind: 'board', sprint: 'Sprint 2' }] }, 'Atlassian'));
show('a group of a kind it has no word for', ticketCardHTML({ ...ticket, groups: [{ name: 'Odd', kind: 'odd' }] },
  'Atlassian'));
show('no groups', ticketCardHTML({ ...ticket, groups: [] }, 'Atlassian'));
show('reading', ticketCardHTML({ key: 'PAY-142' }, 'Atlassian'));
show('couldn\'t read it', ticketCardHTML({ key: 'PAY-142', problem: { kind: 'failed', why: 'Couldn’t reach it' } }));
show('sign in again', ticketCardHTML({ ...ticket, problem: { kind: 'signIn' } }, 'Atlassian'));
show('allow its sign-in', ticketCardHTML({ key: 'PAY-142', problem: { kind: 'allow' } }, 'Atlassian'));
show('asked to slow down', ticketCardHTML({ ...ticket, problem: { kind: 'slow', retryAt: Date.UTC(2033, 4, 18, 10, 42) } },
  'Atlassian'));
show('moved by this conversation', ticketCardHTML({ ...ticket, moved: { to: 'In Review', by: 'itself', at: min(5) } },
  'Atlassian', NOW));
show('…when you pressed Move It, just now', ticketCardHTML({ ...ticket, moved: { to: 'In Review', by: 'you', at: NOW } },
  'Atlassian', NOW));
show('…nothing to move, the step gone', ticketCardHTML({ ...ticket, state: { name: 'In Review', kind: 'doing' },
  moved: { gone: 'PAY-142 is In Review already', at: min(1) } }, 'Atlassian', NOW));
show('…words to escape', ticketCardHTML({ ...ticket, moved: { to: '<b>Done</b>', by: 'itself', at: min(90) } },
  'Atlassian', NOW));
show('a step the session stopped at', ticketCardHTML({ ...ticket, steps: [...ticket.steps,
  { id: '41', name: 'QA sign-off', to: { name: 'Signed Off', kind: 'done' } }],
  stopped: { 41: 'Only QA signs off on payment changes, in the weekly release meeting with the whole team there' } },
  'Atlassian', NOW));
show('…its why with words to escape', ticketCardHTML({ ...ticket, stopped: { 31: 'Review is <the release lead>’s & no one else’s' } },
  'Atlassian', NOW));

section('The row: a new ticket\'s card');
show('pointed at', ticketNewCardHTML({ tracker: 'Jira' }));
show('none', ticketNewCardHTML(null));

section('A reason after a colon');
show('its first letter small', ticketReason('The sign-in has run out.'));
show('…a name kept', ticketReason('Atlassian turned Whozmove away', ['Jira', 'Atlassian']));
show('…Whozmove kept', ticketReason('Whozmove was updated'));
show('…a key kept', ticketReason('PAY-142 is In Review already'));
show('…macOS kept', ticketReason('macOS asks first'));
show('…one word', ticketReason('Failed'));

section('The row: Work on it here?');
show('asked', ticketUseHTML('s1', { key: 'PAY-148', site: 'acme.atlassian.net' }));
show('instead of its own', ticketUseHTML('s1', { key: 'PAY-150', instead: 'PAY-142' }));
show('its own before Whozmove started again', ticketUseHTML('s1', { key: 'PAY-142', again: true }));
show('asked, read', ticketUseHTML('s1', { key: 'PAY-148', site: 'acme.atlassian.net', title: 'Login button does nothing '
  + 'on <Safari>', type: 'Bug', state: { name: 'To Do', kind: 'todo' } }));
show('…with no title', ticketUseHTML('s1', { key: 'PAY-148', state: { name: 'To Do', kind: 'todo' } }));
show('…instead of its own, read', ticketUseHTML('s1', { key: 'PAY-150', site: 'acme.atlassian.net', instead: 'PAY-142',
  state: { name: 'Done', kind: 'done' }, title: 'Retire the old checkout' }));
show('…its own again, read', ticketUseHTML('s1', { key: 'PAY-142', again: true, site: 'acme.atlassian.net',
  state: { name: 'In Progress', kind: 'doing' }, title: 'Login button does nothing on Safari' }));
show('…couldn\'t be read', ticketUseHTML('s1', { key: 'PAY-148', site: 'acme.atlassian.net',
  problem: { kind: 'failed', why: 'Couldn’t reach Atlassian just now' } }));
show('…couldn\'t be read, no reason given', ticketUseHTML('s1', { key: 'PAY-148', problem: { kind: 'failed', why: '' } }));
show('…couldn\'t be read, its sign-in ran out', ticketUseHTML('s1', { key: 'PAY-148', again: true,
  problem: { kind: 'signIn', why: 'You aren\'t signed in with Atlassian' } }));
show('none', ticketUseHTML('s1', null));

section('The row: Move it?');
const move = { key: 'PAY-142', stepId: '31', name: 'Send to review', to: { name: 'In Review', kind: 'doing' },
  note: 'The fix is in pull request #57.\nIt checks the button on Safari 17 and 18.', fields: [], at: min(1) };
show('asked', ticketMoveHTML('s1', move));
show('with no note', ticketMoveHTML('s1', { ...move, note: undefined }));
show('with the fields it sets', ticketMoveHTML('s1', { ...move, to: { name: 'Done', kind: 'done' }, name: 'Finish',
  fields: [{ name: 'Resolution', value: 'Fixed' }, { name: 'Fix versions', value: '2.1, 2.2' }] }));
show('asked again, in place of another', ticketMoveHTML('s1', { ...move, instead: 'Done' }));
show('moving', ticketMoveHTML('s1', { ...move, moving: true }));
show('couldn\'t move it', ticketMoveHTML('s1', { ...move, problem: { kind: 'failed', why: 'Couldn’t reach Atlassian just now.' } }));
show('…no reason given', ticketMoveHTML('s1', { ...move, problem: { kind: 'failed', why: '' } }));
show('…turned away by Jira, saying why, its own page first', ticketMoveHTML('s1', { ...move,
  problem: { kind: 'refused', why: 'Jira turned it away', says: 'Fill in Blocked by first.' } }, 'Jira'));
show('…turned away, its words to escape, no tracker named', ticketMoveHTML('s1', { ...move,
  problem: { kind: 'refused', why: 'Turned away', says: 'Set <b>Blocked by</b> & "Reason" first.' } }));
show('…turned away, saying nothing', ticketMoveHTML('s1', { ...move,
  problem: { kind: 'refused', why: 'Jira turned it away' } }, 'Jira'));
show('…its sign-in ran out', ticketMoveHTML('s1', { ...move, problem: { kind: 'signIn', why: 'The sign-in has run out' } },
  'Jira'));
show('…its sign-in can only read', ticketMoveHTML('s1', { ...move, problem: { kind: 'signIn',
  why: 'This sign-in may only read tickets' } }, 'Jira'));
show('…macOS asks first', ticketMoveHTML('s1', { ...move, problem: { kind: 'allow' } }, 'Jira'));
show('long words, words to escape', ticketMoveHTML('s1', { ...move, to: { name: 'Ready for <b>release</b>', kind: 'doing' },
  note: 'A very long note '.repeat(20) + '<script>x</script> & https://example.com/a/very/long/path/that/goes/on/and/on',
  fields: [{ name: 'A field with a <long> name', value: 'A value '.repeat(12) + '& more' }],
  instead: 'Done & <dusted>' }));
show('no step named, nothing drawn', ticketMoveHTML('s1', { key: 'PAY-142' }));
show('none', ticketMoveHTML('s1', null));

section('The row: Create this ticket?');
const draft = { tracker: 'Jira', site: 'acme.atlassian.net', group: 'PAY', groupKind: 'project', type: 'Bug',
  title: 'Saved cards vanish after an update', priority: 'High', parent: 'PAY-120', checked: true,
  description: 'Since 3.2, every saved card is gone from the iOS app.\nThe website keeps them.', at: min(1) };
show('asked', ticketDraftHTML('s1', draft, 'Atlassian'));
show('with only what it needs', ticketDraftHTML('s1', { ...draft, priority: undefined, parent: undefined,
  description: undefined }, 'Atlassian'));
show('a group of a kind it has no word for', ticketDraftHTML('s1', { ...draft, groupKind: undefined }, 'Atlassian'));
show('signed in to two sites, so it names the one', ticketDraftHTML('s1', draft, 'Atlassian', 2));
show('drafted again, beside the ticket it has', ticketDraftHTML('s1', { ...draft, again: true, instead: 'PAY-142' },
  'Atlassian'));
show('being checked', ticketDraftHTML('s1', { ...draft, checked: undefined, checking: true }, 'Atlassian'));
show('couldn\'t be checked', ticketDraftHTML('s1', { ...draft, checked: undefined,
  problem: { kind: 'failed', why: 'Couldn’t reach Jira just now' } }, 'Atlassian'));
show('being created', ticketDraftHTML('s1', { ...draft, creating: true }, 'Atlassian'));
show('couldn\'t be created', ticketDraftHTML('s1', { ...draft, problem: { kind: 'failed', why: 'Priority is invalid.' } },
  'Atlassian'));
show('…no reason given', ticketDraftHTML('s1', { ...draft, problem: { kind: 'failed', why: '' } }, 'Atlassian'));
show('it may have been made all the same', ticketDraftHTML('s1', { ...draft, mayBeMade: true,
  problem: { kind: 'failed', why: 'Couldn’t reach Jira just now' } }, 'Atlassian'));
show('…signed in to two sites, so it names the one to look on', ticketDraftHTML('s1', { ...draft, mayBeMade: true,
  problem: { kind: 'failed', why: '' } }, 'Atlassian', 2));
show('…then the sign-in ran out, before it was asked again', ticketDraftHTML('s1', { ...draft, mayBeMade: true,
  problem: { kind: 'signIn', why: 'The sign-in has run out' } }, 'Atlassian'));
show('what each state is, for the wait to be seen', [draft, { ...draft, checked: undefined, checking: true },
  { ...draft, checked: undefined, problem: { kind: 'failed' } }, { ...draft, creating: true },
  { ...draft, problem: { kind: 'signIn' } }].map(ticketDraftState).join(', '));
show('…its sign-in ran out', ticketDraftHTML('s1', { ...draft, problem: { kind: 'signIn',
  why: 'The sign-in has run out' } }, 'Atlassian'));
show('…macOS asks first', ticketDraftHTML('s1', { ...draft, problem: { kind: 'allow' } }, 'Atlassian'));
show('long words, words to escape', ticketDraftHTML('s1', { ...draft, title: 'A very long title '.repeat(10) + '<b>x</b>',
  group: 'PAY & <co>', type: '<Bug>', description: 'A very long description '.repeat(30) + '<script>x</script>' },
  'Atlassian'));
show('no title, nothing drawn', ticketDraftHTML('s1', { ...draft, title: '' }));
show('none', ticketDraftHTML('s1', null));

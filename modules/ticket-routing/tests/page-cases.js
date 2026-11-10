// The ticket routing module's part of the page, run outside the app by test.sh: a ticket's worktree name (hostile keys
// too), where the card is told to start in each state, the guide, the line under the box, and the warning where another
// ticket's conversation works (routing-words.js), and the card part's hooks with a made-up answer (routing.js).
// Nothing is drawn. Every ticket, field and folder is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('A ticket’s worktree, by its key');
show('a key', ticketWorktreeName('PAY-142'));
for (const key of ['../x', '-x', 'a b;c', 'x.lock', '$(rm -rf ~)', 'PAY-142.lock.lock', '..', '', null, 'Z'.repeat(80)])
  show(`…${JSON.stringify(key)}`, ticketWorktreeName(key));

section('Where the card is told to start');
const rtBase = { asked: 1, key: 'PAY-142', git: true, project: '/code/acme-shop', name: 'acme-shop' };
const rtField = { id: 'customfield_10001', name: 'Team', value: 'checkout', path: '/code/acme-shop-checkout',
                  folder: '~/code/acme-shop-checkout', here: false };
const rtGuide = { ...rtBase, way: null, guide: { field: rtField } };
const rtOwn = { ...rtBase, way: { kind: 'own' }, place: { kind: 'own' } };
show('the guide, its own worktree lit', routeWhere(rtGuide, { lit: 'own' }));
show('…the Team field lit', routeWhere(rtGuide, { lit: 'field' }));
show('…the Team field, its folder the project’s own',
     routeWhere({ ...rtGuide, guide: { field: { ...rtField, here: true } } }, { lit: 'field' }));
show('…the project’s folder lit', routeWhere(rtGuide, { lit: 'folder' }));
show('…Not Now', routeWhere(rtGuide, { lit: 'own', notNow: true }));
show('its own worktree', routeWhere(rtOwn));
show('the project’s folder', routeWhere({ ...rtBase, way: { kind: 'folder' }, place: { kind: 'here' } }));
show('by a field: its option’s folder', routeWhere({ ...rtBase, way: { kind: 'field' },
                                                     place: { kind: 'folder', folder: '/code/acme-shop-checkout' } }));
show('outside git: nothing to say', routeWhere({ asked: 1, key: 'PAY-142', git: false }));
show('a conversation working it: nothing to say', routeWhere(rtOwn, { worked: { sessionId: 'w1' } }));

section('The guide');
print(routeGuideHTML({ ...rtGuide, guide: { reading: true } }, 'own', 'Ghostty'));
print('-- the Team field offered, and lit');
print(routeGuideHTML(rtGuide, 'field', 'Ghostty'));
print('-- a ticket with no Team, and no terminal');
print(routeGuideHTML({ ...rtGuide, guide: { field: { ...rtField, value: null, folder: null } } }, 'own', null));
print('-- a name to escape');
print(routeGuideHTML({ ...rtGuide, name: '<b>shop</b>', key: 'PAY-1' }, 'own', 'Ghostty'));
print('-- its own worktree lit while Claude Desktop is the card’s app: it says the terminal it starts in');
print(routeGuideHTML(rtGuide, 'own', 'Ghostty', 'desktop'));

section('The line under the box');
const rtTeam = { kind: 'field', field: { id: 'customfield_10001', name: 'Team' } };
const rtAt = (fields) => ({ kind: 'new', name: 'pay-142', where: '~/code/acme-shop-worktrees/pay-142', terminal: 'Ghostty',
                            git: true, followed: true, chosen: false, ...fields });
const rtLines = [
  ['a new worktree', rtOwn, rtAt()],
  ['its worktree is there', rtOwn, rtAt({ kind: 'open', path: '/code/acme-shop-worktrees/pay-142' })],
  ['its branch is there, with no folder', rtOwn, rtAt({ kind: 'branch' })],
  ['a new worktree, with Claude Desktop picked on the card', rtOwn, rtAt({ app: 'desktop' })],
  ['no terminal', rtOwn, rtAt({ kind: 'here', terminal: null })],
  ['the project’s folder', { ...rtBase, way: { kind: 'folder' }, place: { kind: 'here' } }, rtAt({ kind: 'here' })],
  ['by a field: reading it', { ...rtBase, way: rtTeam, place: { kind: 'own', reading: true } }, rtAt()],
  ['…its option’s folder', { ...rtBase, way: rtTeam, place: { kind: 'folder', folder: '/code/acme-shop-checkout',
    where: '~/code/acme-shop-checkout', value: { id: '10', name: 'checkout' } } },
   rtAt({ kind: 'open', path: '/code/acme-shop-checkout' })],
  ['…no option', { ...rtBase, way: rtTeam, place: { kind: 'own', why: 'noValue' } }, rtAt()],
  ['…an option with no folder', { ...rtBase, way: rtTeam, place: { kind: 'own', why: 'noFolder',
    value: { id: '12', name: 'web' } } }, rtAt()],
  ['…its folder gone', { ...rtBase, way: rtTeam, place: { kind: 'own', why: 'gone', where: '~/code/acme-shop-web',
    value: { id: '12', name: 'web' } } }, rtAt()],
  ['…not read', { ...rtBase, way: rtTeam, place: { kind: 'own', why: 'unread' },
    problem: { kind: 'signIn', why: 'Sign in with Atlassian first' } }, rtAt()],
];
for (const [name, answer, at] of rtLines) {
  print(`-- ${name}`);
  print(routeLineHTML(routeLine(answer, at, null)));
}
print('-- …its option’s folder, one the card can’t start in: the card’s own line');
show('', routeLine({ ...rtBase, way: rtTeam, place: { kind: 'folder', folder: '/code/acme-shop-web',
  where: '~/code/acme-shop-web', value: { id: '12', name: 'web' } } }, rtAt({ kind: 'here', path: '/code/acme-shop' }), null));
print('-- a conversation working it already');
const rtTicket = { tracker: 'Jira', site: 'acme.atlassian.net', key: 'PAY-142' };
const rtWorker = session({ sessionId: 'w1', git: { branch: 'pay-142', root: '/code/acme-shop-worktrees/pay-142',
  worktree: 'pay-142', mainRoot: '/code/acme-shop' }, ticket: { bound: { ...rtTicket } } });
print(routeLineHTML(routeLine(rtOwn, rtAt(), rtWorker)));

section('Another ticket’s conversation');
const rtOther = session({ sessionId: 'o1', git: { branch: 'main', root: '/code/acme-shop' },
  ticket: { bound: { ...rtTicket, key: 'PAY-139' } } });
show('the conversation working this ticket', ticketWorkedBy([rtOther, rtWorker], rtTicket)?.sessionId);
show('…none', ticketWorkedBy([rtOther], rtTicket));
show('…one only starting isn’t one yet', ticketWorkedBy([{ ...rtWorker, pending: true }], rtTicket));
show('…another site’s ticket of the same key isn’t this one',
     ticketWorkedBy([{ ...rtWorker, ticket: { bound: { ...rtTicket, site: 'beta.atlassian.net' } } }], rtTicket));
show('in the project’s folder: PAY-139', routeWarn(otherTicketIn([rtOther], '/code/acme-shop', 'PAY-142'), 'PAY-142'));
show('…in an existing worktree', routeWarn(otherTicketIn([{ ...rtOther, git: { root: '/code/acme-shop-checkout' } }],
  '/code/acme-shop-checkout', 'PAY-142'), 'PAY-142'));
show('…a closed one doesn’t count', otherTicketIn([{ ...rtOther, status: 'closed' }], '/code/acme-shop', 'PAY-142'));
show('…the same ticket doesn’t count', otherTicketIn([rtWorker], '/code/acme-shop-worktrees/pay-142', 'PAY-142'));
show('…a new worktree: nowhere to look', otherTicketIn([rtOther], null, 'PAY-142'));

section('The card part, with a made-up answer');
const rtSent = [];
const rtWebkit = window.webkit;
window.webkit = { messageHandlers: { panel: { postMessage: (m) => rtSent.push(m) } } };
core.cardTicket = () => rtTicket;
state.last.sessions = [rtOther];
const rtPart = core.startCardParts.find((p) => p.name === 'routing');
const rtApi = { refresh: () => {}, start: () => rtSent.push({ started: true }), useHere: () => rtSent.push({ here: true }),
                place: () => ({ kind: 'here', name: 'main', where: '~/code/acme-shop', path: '/code/acme-shop',
                                terminal: 'Ghostty', app: 'desktop', git: true }) };
const rtCard = { folder: '/code/acme-shop' };
// A press on what `selector` names: closest() finds it for any of the selectors asked that it holds.
const rtPress = (selector, dataset) => ({
  closest: (asked) => (asked.split(',').some((one) => selector.includes(one.trim().split('[')[0])) ? { dataset } : null),
});
show('asked once the card has a ticket', (rtPart.where(rtCard), rtSent.splice(0)));
show('…not again while it’s the same', (rtPart.where(rtCard), rtSent.splice(0)));
ticketRouted({ ...rtGuide, asked: state.routeAsk.asked });
show('the guide’s lit way', rtPart.where(rtCard));
show('…the guide takes the line’s place', /rt-guide/.test(rtPart.under(rtCard, rtApi)));
show('…a press just after it shows doesn’t count',
     (rtPart.press(rtPress('.rt-guide .rt-opt', { way: 'field' }), rtCard, rtApi), state.routeLit));
state.routeGuideAt = Date.now() - 1000;
show('a press on the Team field lights it',
     (rtPart.press(rtPress('.rt-guide .rt-opt', { way: 'field' }), rtCard, rtApi), state.routeLit));
show('…and the card is told to start in its folder', rtPart.where(rtCard));
show('the warning where it would start: PAY-139 in the project’s folder', rtPart.warn(rtCard, rtApi));
show('…said too while the card offers Go to It for this ticket, with no button: its own worktree is the busy one', (() => {
  state.last.sessions = [rtOther, { ...rtWorker, status: 'closed' }];
  const said = rtPart.warn(rtCard, rtApi);
  state.last.sessions = [rtOther];
  return said;
})());
// The tickets module lets the card's ticket go as the start is sent, before this part hears it was.
core.cardTicket = () => null;
show('Start keeps the lit way', (rtPart.sent(rtCard), rtSent.splice(0)));
core.cardTicket = () => rtTicket;
show('…and the next card asks afresh', state.routeAsk);
show('Esc on the guide only puts it away: nothing starts, the card shows the project’s folder, and Start keeps nothing', (() => {
  rtPart.where(rtCard);
  ticketRouted({ ...rtGuide, asked: state.routeAsk.asked });
  rtSent.splice(0);
  const taken = rtPart.boxKeys(rtCard, { key: 'Escape' }, rtApi);
  const where = rtPart.where(rtCard), guide = /rt-guide/.test(rtPart.under(rtCard, rtApi)), started = rtSent.splice(0);
  const again = rtPart.boxKeys(rtCard, { key: 'Escape' }, rtApi);
  rtPart.sent(rtCard);
  return { taken, where, guide, started, again, sent: rtSent.splice(0) };
})());
show('Not Now pressed: it starts here, keeping nothing', (() => {
  state.routeAsk = null;
  rtPart.where(rtCard);
  ticketRouted({ ...rtGuide, asked: state.routeAsk.asked });
  rtSent.splice(0);
  state.routeGuideAt = Date.now() - 1000;
  rtPart.press(rtPress('.rt-guide .rt-notnow', {}), rtCard, rtApi);
  const where = rtPart.where(rtCard);
  rtPart.sent(rtCard);
  return { where, sent: rtSent.splice(0) };
})());
show('Use acme-shop on the line', (() => {
  rtPart.where(rtCard);
  ticketRouted({ ...rtOwn, asked: state.routeAsk.asked });
  rtPart.press(rtPress('.rt-row .rt-act', { act: 'here' }), rtCard, rtApi);
  return rtSent.splice(0);
})());
show('an answer for a ticket since changed is let go', (() => {
  ticketRouted({ ...rtOwn, asked: -1, key: 'PAY-999' });
  return state.routeAsk.answer.key;
})());
// The guide's answer again, for a fresh card's ask.
const rtFresh = (answer) => {
  state.routeAsk = null;
  rtPart.where(rtCard);
  ticketRouted({ ...answer, asked: state.routeAsk.asked });
  rtSent.splice(0);
};
show('Not Now in a folder Claude hasn’t worked in: the guide only goes, nothing starts or is trusted', (() => {
  rtFresh(rtGuide);
  state.routeGuideAt = Date.now() - 1000;
  const trusting = { ...rtApi, place: () => ({ ...rtApi.place(), trust: true }) };
  rtPart.press(rtPress('.rt-guide .rt-notnow', {}), rtCard, trusting);
  return { guide: /rt-guide/.test(rtPart.under(rtCard, trusting)), sent: rtSent.splice(0) };
})());
show('…the same for Esc there', (() => {
  rtFresh(rtGuide);
  const trusting = { ...rtApi, place: () => ({ ...rtApi.place(), trust: true }) };
  const taken = rtPart.boxKeys(rtCard, { key: 'Escape' }, trusting);
  return { taken, guide: /rt-guide/.test(rtPart.under(rtCard, trusting)), sent: rtSent.splice(0) };
})());
show('Esc just after the guide shows: taken, and nothing more', (() => {
  rtFresh(rtGuide);
  rtPart.under(rtCard, rtApi);
  const taken = rtPart.boxKeys(rtCard, { key: 'Escape' }, rtApi);
  return { taken, notNow: state.routeNotNow, sent: rtSent.splice(0) };
})());
show('…and once the field comes in, it counts as just shown again', (() => {
  rtFresh({ ...rtGuide, guide: { reading: true } });
  state.routeGuideAt = Date.now() - 1000;
  ticketRouted({ ...rtGuide, asked: state.routeAsk.asked });
  return Date.now() - state.routeGuideAt < ROUTE_GUIDE_SETTLES;
})());
show('you picked where yourself: the guide is hidden, Esc closes the card, and Start keeps no way', (() => {
  rtFresh(rtGuide);
  const mine = { ...rtCard, chosen: true };
  const taken = rtPart.boxKeys(mine, { key: 'Escape' }, rtApi);
  rtPart.sent(mine);
  return { taken, sent: rtSent.splice(0) };
})());
show('a field way still being read: nothing proposed, and Start waits', (() => {
  rtFresh({ ...rtBase, way: rtTeam, place: { kind: 'own', reading: true } });
  return { where: rtPart.where(rtCard), waits: rtPart.waits(rtCard) };
})());
show('…once read: its folder, and Start goes', (() => {
  ticketRouted({ ...rtBase, asked: state.routeAsk.asked, way: rtTeam,
                 place: { kind: 'folder', folder: '/code/acme-shop-checkout', where: '~/code/acme-shop-checkout' } });
  return { where: rtPart.where(rtCard), waits: rtPart.waits(rtCard) };
})());
show('Set It: Settings ▸ Tickets on the project’s own page', (() => {
  rtFresh({ ...rtBase, way: rtTeam, place: { kind: 'own', why: 'noFolder', value: { id: '12', name: 'web' } } });
  rtPart.press(rtPress('.rt-row .rt-act', { act: 'setIt' }), rtCard, rtApi);
  return rtSent.splice(0);
})());
show('Sign In on a ticket not read for want of one', (() => {
  rtFresh({ ...rtBase, way: rtTeam, place: { kind: 'own', why: 'unread' }, problem: { kind: 'signIn', why: 'Sign in' } });
  rtPart.press(rtPress('.rt-row .rt-act', { act: 'signIn' }), rtCard, rtApi);
  return rtSent.splice(0);
})());
show('…and, signed in, it’s asked about afresh', (ticketRouteAgain(), rtPart.where(rtCard), rtSent.splice(0)));
core.cardTicket = () => null;
show('no ticket: nothing', { where: rtPart.where(rtCard), under: rtPart.under(rtCard, rtApi) });
window.webkit = rtWebkit;
state.last.sessions = [];

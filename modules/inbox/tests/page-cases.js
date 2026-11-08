// Messages' part of the page, run outside the app by test.sh: the messages put together from what the app sends, who
// each is from and to (two sessions of one name told apart), which answers which, where each stands in words, what
// each filter, one agent and a pair show, what the channel says with nothing to show, this week's counts, the inbox
// strip in the order the app gives, and the HTML of the head, the filters, the strip and a few messages.
// Every name here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const DAY = 24 * 60;
// Sessions as the app names them: their id, name, folder and whether they've ended. Two are called Wren.
const wren = { session: 's-wren', name: 'Wren', folder: 'shop', ended: false };
const wren2 = { session: 's-wren-2', name: 'Wren', folder: 'docs', ended: true };
const juniper = { session: 's-juniper', name: 'Juniper', folder: 'shop', ended: false };
const moss = { session: 's-moss', name: 'Moss', folder: 'docs', ended: false };
const fern = { session: 's-fern', name: 'Fern', folder: 'shop', ended: false };
const nobody = { session: null, name: 'Pip', folder: null, ended: true };
const plain = (id, from, to, at, delivery, text, more = {}) => ({ id, from, to, at: min(at), text, cut: false,
  delivery, deliveryAt: min(at), canAsk: false, kept: null, ...more });
const kept = (id, from, at, delivery, kept, text) => ({ id, from, to: wren, at: min(at), text, cut: false, delivery,
  deliveryAt: delivery === 'kept' ? null : min(at), canAsk: false, kept: { about: null, readAt: null, readBy: null,
    answeredAt: null, note: null, ...kept } });

const messages = [
  plain('y1', wren2, moss, DAY + 120, 'arrived', 'Yesterday’s note about the install guide.'),
  plain('p1', wren, juniper, 120, 'arrived', 'Take the coupon field: add it to the checkout page, with tests.'),
  kept('k1', juniper, 90, 'arrived', { id: 'm-1a2b3c', priority: 'report', about: 'Coupons', readAt: min(80),
                                       readBy: 's-wren', answeredAt: min(78) },
       'Done: the coupon field is in, and **14 tests** pass.\n\nOne thing left: the total is a cent off.'),
  plain('p2', wren, juniper, 78, 'arrived', 'Thanks. Take the cent next.'),
  plain('d1', juniper, fern, 40, 'denied', 'Can you look at the migration?'),
  plain('dr1', moss, fern, 41, 'dropped', 'Which address do the docs use?'),
  plain('f1', fern, nobody, 42, 'failed', 'Are you there?'),
  kept('k2', moss, 30, 'held', { id: 'm-2b3c4d', priority: 'question' },
       'The guide says Node 18, but package.json needs 20. Change the guide, or add a note?'),
  plain('e1', fern, moss, 25, 'expired', 'Which staging address do the docs use?'),
  kept('k4', juniper, 20, 'arrived', { id: 'm-4d5e6f', priority: 'note', readAt: min(15), readBy: 's-wren-old' },
       'For you to know: the rounding is in two files. I’m changing one.'),
  kept('k5', moss, 18, 'expired', { id: 'm-5e6f7a', priority: 'urgent', readAt: min(17), readBy: 's-wren',
                                    answeredAt: min(16), note: 'Moved to tomorrow' }, 'The build is red.'),
  plain('h2', fern, moss, 12, 'held', 'Does price.ts round before or after tax?'),
  plain('h1', moss, juniper, 10, 'held', 'Is the guide’s example yours?', { canAsk: true }),
  kept('m-3c4d5e', fern, 6, 'kept', { id: 'm-3c4d5e', priority: 'urgent' },
       'Stop: the migration drops the coupons table on staging. Should I go on?'),
  plain('s1', juniper, moss, 2, 'sent', 'One more thing about the guide.'),
  plain('long', moss, juniper, 1, 'arrived', 'A long one. '.repeat(30) + '\n\nWith a second part.', { cut: true }),
];
const inboxes = [{ project: '/work/shop', lead: { session: 's-wren', name: 'Wren' },
                   unread: ['m-3c4d5e', 'k2', 'not-in-the-messages'] }];
const counts = { held: 3, expired: 0, lost: 1 };
const channel = mxTake(null, messages, true);
const ctx = mxContext(channel, NOW);
const all = { filter: 'all', agent: null, pair: null };

section('Put together (mxTake)');
show('whole, oldest first', channel.map((m) => m.id));
const merged = mxTake(channel, [{ ...messages[14], delivery: 'arrived' },
                             plain('n1', fern, wren, 0, 'arrived', 'A new one.')], false);
show('new and changed laid over, by id', merged.map((m) => `${m.id}:${m.delivery}`).slice(-4));
show('a kept message sent again by its note’s id takes its inbox id’s place',
     mxTake(channel, [{ ...messages[13], id: 'bell-1' }], false).filter((m) => m.kept?.id === 'm-3c4d5e')
       .map((m) => m.id));
show('whole replaces everything', mxTake(channel, [messages[0]], true).map((m) => m.id));

section('Who each is (mxNames)');
for (const [session, n] of mxNames(channel)) show(session, n);
show('a receiver no session listens at', mxPartyName(nobody));
show('one with no name', mxPartyName({ session: 's-x', name: null }));

section('What answers what (mxAnswers)');
for (const [reply, to] of mxAnswers(channel)) show(`${reply} answers`, to);
show('a reply to one that never arrived answers nothing',
     [...mxAnswers([plain('a', fern, moss, 5, 'expired', 'x'), plain('b', moss, fern, 4, 'arrived', 'y')])]);
show('two in a row answer one each, newest first',
     [...mxAnswers([plain('q1', moss, wren, 9, 'arrived', 'x'), plain('q2', moss, wren, 8, 'arrived', 'y'),
                    plain('r1', wren, moss, 7, 'arrived', 'z'), plain('r2', wren, moss, 6, 'arrived', 'w')])]);

section('Where each stands (mxWhere), and whether it waits or was lost');
for (const m of channel)
  show(`${m.id} (${m.kept ? `kept ${m.kept.priority}` : 'plain'}, ${m.delivery})`,
       { ...mxWhere(m, ctx), waiting: mxWaiting(m, ctx), lost: mxLost(m), answered: mxAnswered(m, ctx) });

section('What each view shows (mxShown, mxCounts)');
const views = {
  all, waiting: { ...all, filter: 'waiting' }, lost: { ...all, filter: 'lost' },
  'Moss’s messages': { ...all, agent: 's-moss' }, 'Moss’s, waiting': { filter: 'waiting', agent: 's-moss', pair: null },
  'Moss and Fern': { ...all, agent: 's-moss', pair: ['s-moss', 's-fern'] },
  'the Wren that ended': { ...all, agent: 's-wren-2' },
};
for (const [name, view] of Object.entries(views))
  show(name, { shown: mxShown(view, ctx).map((m) => m.id), counts: mxCounts(view, ctx),
               narrowedTo: mxNarrowedTo(view, ctx) });

section('What it says with nothing to show (mxEmptyWords)');
const none = mxContext([], NOW);
show('nothing in two days', mxEmptyWords(all, none, { reading: false, agent: 'Claude Code' }));
show('nothing in two days, the agent not named', mxEmptyWords(all, none, {}));
show('the first read still going', mxEmptyWords(all, none, { reading: true, agent: 'Claude Code' }));
show('no agent records its messages', mxEmptyWords(all, none, { reading: false, agent: null }));
const quiet = mxContext([plain('ok', wren, juniper, 5, 'arrived', 'Fine.')], NOW);
show('nothing waits', mxEmptyWords({ ...all, filter: 'waiting' }, quiet, {}));
show('everything got there', mxEmptyWords({ ...all, filter: 'lost' }, quiet, {}));
show('nothing waits for one agent', mxEmptyWords({ filter: 'waiting', agent: 's-wren', pair: null }, quiet, {}));
show('nothing lost between a pair',
     mxEmptyWords({ filter: 'lost', agent: 's-wren', pair: ['s-wren', 's-juniper'] }, quiet, {}));
show('something to show', mxEmptyWords(all, ctx, {}));

section('This week (mxWeekWords)');
show('held and lost', mxWeekWords(counts));
show('every kind', mxWeekWords({ held: 1, expired: 2, denied: 1, dropped: 1, failed: 1, lost: 4 }));
show('none', mxWeekWords({ held: 0 }));
show('not sent yet', mxWeekWords(undefined));

section('The inbox strip (mxStrip), in the order the app gives');
show('everyone', mxStrip(inboxes, all, ctx).map((i) => ({ name: i.name, items: i.items.map((m) => m.id) })));
show('Fern’s messages', mxStrip(inboxes, { ...all, agent: 's-fern' }, ctx).map((i) => i.items.map((m) => m.id)));
show('Juniper’s messages (nothing unread)', mxStrip(inboxes, { ...all, agent: 's-juniper' }, ctx));

section('Times and words');
show('a clock time', mxClock(min(0)));
show('today', mxDayWord(min(10), NOW));
show('yesterday', mxDayWord(min(DAY + 60), NOW));
show('three days ago', mxDayWord(min(3 * DAY), NOW));
show('first words', mxFirstWords('One  thing\nleft: the total is a cent off.', 20));
show('short enough', mxFirstWords('Fine.', 20));
show('long', [mxLong('x'.repeat(221)), mxLong('a\nb\nc\nd'), mxLong('a\nb\nc'), mxLong('')]);
show('to read', mxToRead(2));

section('Drawn');
const page = { more: new Set(), lit: null, fresh: null };
show('the head', mxHeadHTML(ctx, { counts }));
show('the head before anything is sent', mxHeadHTML(mxContext([], NOW), null));
show('the filters', mxFiltersHTML(all, ctx));
show('the filters, one agent', mxFiltersHTML({ ...all, filter: 'waiting', agent: 's-moss' }, ctx));
show('the filters, a pair', mxFiltersHTML(views['Moss and Fern'], ctx));
show('the strip', mxStripHTML(mxStrip(inboxes, all, ctx)));
for (const id of ['k1', 'p2', 'e1', 'h1', 'h2', 'y1', 'long'])
  show(`message ${id}`, mxMessageHTML(ctx.byId.get(id), ctx, page));
show('long, shown whole', mxMessageHTML(ctx.byId.get('long'), ctx, { ...page, more: new Set(['long']) }));
show('lit and new', mxMessageHTML(ctx.byId.get('s1'), ctx, { ...page, lit: 's1', fresh: new Set(['s1']) }));
show('a message to no session', mxMessageHTML(ctx.byId.get('f1'), ctx, page));
show('the channel with no agent recording, but an inbox’s', mxChannelHTML(all, quiet, { agent: null }, page));
show('the channel with no agent recording, and nothing', mxChannelHTML(all, none, { agent: null }, page));
show('the channel with an agent', mxChannelHTML(all, quiet, { agent: 'Claude Code' }, page));
show('the channel, the days', mxChannelHTML(views['the Wren that ended'], ctx, {}, page));
show('the channel, nothing for one agent',
     mxChannelHTML({ filter: 'lost', agent: 's-wren', pair: null }, quiet, {}, page));
show('the channel, nothing at all', mxChannelHTML(all, none, { agent: 'Claude Code' }, page));

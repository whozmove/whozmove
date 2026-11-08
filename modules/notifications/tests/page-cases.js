// The notifications module's decider, run outside the app by test.sh: what the line under the header shows and what
// waits, where each place is in sight, and which sessions come out beside the folded panel and when (decide.js).
// Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('The line under the header');
const notice = (id, level, more = {}) => ({ id, level, ...more });
const lineOf = (notices, given) => {
  const r = noticeLine(notices, { shown: null, front: null, frontWith: [], typing: false, ...given });
  return { line: r.line?.id || null, more: r.more, ...(r.front ? { front: r.front } : {}) };
};
const update = notice('install/update', 'soon'), low = notice('storage/disk', 'soon');
const broken = notice('install/connect', 'urgent'), ready = notice('storage/map', 'know');
show('nothing listed: no line', lineOf([], {}));
show('an update, then the disk running low: the first to come shows, +1', lineOf([update, low], {}));
show('…the disk one showing: it stays, among equals', lineOf([update, low], { shown: 'storage/disk' }));
show('couldn\'t connect comes: urgent, in front at once, +2', lineOf([update, low, broken], { shown: 'install/update' }));
show('good to know waits behind soon', lineOf([ready, update], {}));
show('typing: what shows stays, though something soon came first', lineOf([update, low], { shown: 'storage/disk',
                                                                                         typing: true }));
show('typing: nothing new comes in where nothing showed', lineOf([update], { typing: true }));
show('typing: something urgent comes in all the same', lineOf([update, broken], { shown: 'install/update',
                                                                                  typing: true }));
show('typing: the one showing gone, something soon waits', lineOf([low], { shown: 'install/update', typing: true }));

section('+N, stepping round what waits');
const listed = [update, low, broken, ready];
let stepped = { shown: lineOf(listed, {}).line, front: null, frontWith: [] };
const steps = [stepped.shown];
for (let i = 0; i < 4; i++) {
  stepped = { ...stepped, ...noticeNext(listed, stepped) };
  stepped.shown = noticeLine(listed, stepped).line.id;
  steps.push(stepped.shown);
}
show('from the urgent one, each press: the next, urgent or not, then back to the first', steps);
stepped = { shown: 'install/update', ...noticeNext(listed, { shown: 'install/update' }) };
show('the one stepped to stays as the others change', lineOf([update, low, broken], stepped));
show('…until something urgent that wasn\'t there comes: the most urgent shows again', lineOf([...listed, notice('storage/severe', 'urgent')], stepped));
show('…or it goes', lineOf([update, broken, ready], stepped));
show('+N with nothing listed', noticeNext([], { shown: null }));
show('typing: a step you pressed with +N comes in all the same', (() => {
  const v = { shown: 'install/update', typing: true, ...noticeNext([update, low], { shown: 'install/update' }) };
  return lineOf([update, low], v).line;
})());

section('Quiet hours');
show('at night, only what\'s urgent is said, and the rest isn\'t counted', lineOf([update, low, broken],
                                                                                 { night: true }));
show('…with nothing urgent, nothing', lineOf([update, low], { night: true }));
show('…but the one showing as they began stays, with nothing counted behind it',
     lineOf([update, low], { shown: 'install/update', night: true }));
const severe = notice('storage/severe', 'urgent');
show('…and +N steps only to what\'s urgent',
     noticeNext([update, broken, low, severe], { shown: 'install/connect', night: true }).front);
show('…but what answers something you just did is said all the same',
     lineOf([update, notice('bring-forward/session-gone', 'soon', { answersYou: true })], { night: true }));
show('in the morning, all of it again', lineOf([update, low, broken], { night: false }));
// Whozmove beside the panel at its edge: by day it counts all that has something new; at night, only what's urgent.
show('the edge\'s count by day, and at night', [edgeCount(['urgent', 'urgent', 'soon'], false),
                                                 edgeCount(['urgent', 'urgent', 'soon'], true)]);

section('Where each place is in sight');
// What each place says of itself, the line's and the chats' from the panel's fold, and the app whether it's there.
const bodyContains = document.body.classList.contains;
const sight = (body, where = {}) => {
  document.body.classList.contains = (name) => body.split(' ').includes(name);
  state.turned = where.turned || false;
  const places = { line: core.places.line.inSight(), beside: core.places.besideFold.inSight(),
                   edge: core.places.besideEdge.inSight() };
  return noticeSight(places, { shown: true, parked: false, ...where });
};
show('open', sight(''));
show('turned over to its back', sight('', { turned: true }));
show('folded', sight('collapsed'));
show('folded, its list out on pointing', sight('collapsed peeking'));
show('folded, opening round the cat', sight('collapsed arriving'));
show('flicked off the screen\'s edge', sight('', { parked: true }));
show('hidden from the menu bar', sight('', { shown: false }));
document.body.classList.contains = bodyContains;
state.turned = false;

section('Sessions beside the folded panel');
// A notice naming a session, as the decider's row: a request ('ask:…') urgent and out even where you look, a reply
// soon, a wait urgent; out for 45 seconds.
const chatRow = (sid, news, on = false, level = news && (/^reply:/.test(news) ? 'soon' : 'urgent')) => ({ sid, news,
  level, on, evenSeen: /^ask:/.test(news || ''), outFor: 45 });
const chatsAt = (chats) => ({ out: chats.out.map((c) => `${c.sid} ${Math.round(c.left / 1000)}s${c.kept ? ' pinned' : ''}`),
                              queue: chats.queue.map((q) => q.sid), came: chats.came, went: chats.went });
const foldedRule = { loaded: true, open: false, quiet: false, holding: false, most: 3 };
// The list's order is newest first: d's request is the newest, then c's, b's reply and a's request.
const asking = [chatRow('d', 'ask:3'), chatRow('c', 'ask:2'), chatRow('b', 'reply:5'), chatRow('a', 'ask:1')];
let chats = besideStep({ out: [], queue: [], done: {}, seeded: false }, [chatRow('a', 'ask:1'), chatRow('b', null)],
                       foldedRule);
show('as the page loads, what\'s already waiting doesn\'t come out', chatsAt(chats));
// After a restart the page draws first with no rows (its settings, the build's name), then the app's rows come.
let restarted = besideStep({ out: [], queue: [], done: {}, seeded: false }, [], { ...foldedRule, loaded: false });
show('restarted: drawn before the app\'s rows have come, nothing is decided', [restarted.seeded, chatsAt(restarted)]);
restarted = besideStep(restarted, asking, foldedRule);
show('…then the rows come: what was waiting before the restart isn\'t brought out again', chatsAt(restarted));
restarted = besideStep(restarted, [chatRow('n', 'reply:20'), ...asking], foldedRule);
show('…and what comes after does', chatsAt(restarted));
// What's kept for a restart: what was seen, and what was out, as seen.
const keptForRestart = besideKept(restarted.done, restarted.out);
show('kept for a restart: what was seen, and what was out', keptForRestart);
// The app restarted: the page has what was kept (setBesideSeen), and the rows have a request that came while it was
// down beside the reply from before, and the four from before that.
const afterRestart = besideStep({ out: [], queue: [], done: keptForRestart, seeded: true },
                                [chatRow('m', 'ask:30'), chatRow('n', 'reply:20'), ...asking], foldedRule);
show('a request that came while Whozmove was down comes out; the reply from before it doesn\'t', chatsAt(afterRestart));
show('a first launch, with nothing kept: nothing already there comes out',
     chatsAt(besideStep({ out: [], queue: [], done: {}, seeded: false }, [chatRow('m', 'ask:30'), ...asking], foldedRule)));
chats = besideStep(chats, asking, foldedRule);
show('three more come to need you (a\'s request was there as the page loaded): in the order they came, b\'s reply '
     + 'first, requests and replies alike',
     chatsAt(chats));
const replying = [chatRow('r', 'reply:8'), chatRow('q', 'ask:6')];
show('a reply newer than a request: the request, there first, comes out first',
     chatsAt(besideStep(besideStep({ out: [], queue: [], done: {}, seeded: false }, [], foldedRule), replying,
                        foldedRule)));
const newest = [chatRow('e', 'ask:9'), ...asking];
show('…a fourth waits its turn, and none of the three goes back in for it',
     chatsAt(besideStep(chats, newest, foldedRule)));
show('…but while you hold one (pointing at it, typing in it, or in its tab), the newer one waits, and nothing moves',
     chatsAt(besideStep(chats, newest, { ...foldedRule, holding: true })));
const ran = chatsTick(chats.out, CHAT_MS, (c) => c.sid !== 'd');
show('…once one\'s time has run out, it goes back', ran.expired.map((c) => c.sid));
chats = besideStep(besideBack({ ...chats, out: [...ran.out, ...ran.expired] }, 'd'), asking, foldedRule);
show('…counted as seen, so it doesn\'t come out again for the same request',
     chatsAt(chats));
show('…but does for something new in its session, coming out again',
     chatsAt(besideStep(chats, [chatRow('d', 'ask:7'), chatRow('c', 'ask:2'), chatRow('b', 'reply:5'),
                                chatRow('a', 'ask:1')], foldedRule)));
const lower = { ...chats, out: chats.out.map((c) => (c.sid === 'c' ? { ...c, left: 10000 } : c)) };
show('one still out with 10 seconds left: something new in its session starts its time again',
     chatsAt(besideStep(lower, [chatRow('c', 'ask:8'), chatRow('b', 'reply:5'), chatRow('a', 'ask:1')], foldedRule)));
show('…and without, it keeps what it had', chatsAt(besideStep(lower, asking, foldedRule)));
const empty = besideStep({ out: [], queue: [], done: {}, seeded: false }, [], foldedRule);
const full = besideStep(empty, newest, foldedRule);
show('five come to need you at once: the first three to come out, in that order, the other two waiting in it',
     chatsAt(full));
show('…the first one\'s × pressed: the others move up, and the first waiting comes out after them',
     chatsAt(besideStep(besideBack(full, 'a'), newest, foldedRule)));
const timedOut = chatsTick(full.out, CHAT_MS, (c) => c.sid !== 'c');
show('…or another\'s time runs out: the same',
     chatsAt(besideStep(besideBack({ ...full, out: [...timedOut.out, ...timedOut.expired] }, 'c'), newest, foldedRule)));
const sixth = [chatRow('f', 'ask:13'), ...newest];
show('…a sixth comes: it joins the end of the line, and comes out only after those waiting before it',
     [chatsAt(besideStep(full, sixth, foldedRule)),
      chatsAt(besideStep(besideBack(besideStep(full, sixth, foldedRule), 'a'), sixth, foldedRule))]);
show('…with room for two only, the last out goes back in, to wait at the head of the line',
     chatsAt(besideStep(full, newest, { ...foldedRule, most: 2 })));
show('sent back in for now (the cat moved): still new, so it comes out again',
     chatsAt(besideStep({ ...chats, out: chats.out.filter((c) => c.sid !== 'c') }, asking, foldedRule)));
show('pressed, its tab in front: it stays, held, though its reply has been read there', chatsAt(besideStep(chats,
  [chatRow('d', 'ask:3'), chatRow('c', 'ask:2'), chatRow('b', null, true), chatRow('a', 'ask:1')], foldedRule)));
show('…and goes once you\'ve left the tab', chatsAt(besideStep(chats,
  [chatRow('d', 'ask:3'), chatRow('c', 'ask:2'), chatRow('b', null), chatRow('a', 'ask:1')], foldedRule)));
show('one answered elsewhere goes', chatsAt(besideStep(chats,
  [chatRow('d', 'ask:3'), chatRow('c', null), chatRow('b', 'reply:5'), chatRow('a', 'ask:1')], foldedRule)));
show('a reply that comes in the tab you\'re in is read there, and doesn\'t come out', chatsAt(besideStep(chats,
  [chatRow('f', 'reply:11', true), chatRow('d', 'ask:3'), chatRow('c', 'ask:2'), chatRow('b', 'reply:5')],
  foldedRule)));
// A request comes out even in the tab you're in, as its session waits on your answer: a question, a permission request
// or a plan alike, as the decider sees only that one waits.
const inTab = besideStep(empty, [chatRow('f', 'ask:11', true)], foldedRule);
show('a request that comes in the tab you\'re in comes out all the same', chatsAt(inTab));
show('…and stays out while it waits there', chatsAt(besideStep(inTab, [chatRow('f', 'ask:11', true)], foldedRule)));
const answeredInTab = besideStep(inTab, [chatRow('f', null, true)], foldedRule);
show('…answered, in its tab or on its card, it goes though you\'re still there', chatsAt(answeredInTab));
show('…and the reply after it, read there, doesn\'t bring it out again',
     chatsAt(besideStep(besideStep(inTab, [chatRow('f', 'reply:12', true)], foldedRule), [chatRow('f', 'reply:12')],
                        foldedRule)));
show('…but another request in its place keeps it out, its time starting again',
     chatsAt(besideStep({ ...inTab, out: inTab.out.map((c) => ({ ...c, left: 10000 })) },
                        [chatRow('f', 'ask:13', true)], foldedRule)));
show('a wait without a request that comes in the tab you\'re in doesn\'t come out either',
     chatsAt(besideStep(empty, [chatRow('w', 'wait:11', true)], foldedRule)));
const ranOut = chatsTick(inTab.out, CHAT_MS, () => false);
show('a request out in the tab you\'re in whose time runs out goes back, and doesn\'t come out again for it',
     chatsAt(besideStep(besideBack({ ...inTab, out: ranOut.expired }, 'f'), [chatRow('f', 'ask:11', true)], foldedRule)));
// Which chat your being in its tab holds: the one you pressed, or whose row you pressed, while it was out.
const outF = [{ sid: 'f', news: 'ask:11', left: CHAT_MS, kept: false, evenSeen: true }], inF = [chatRow('f', 'ask:11', true)];
const pressedF = besideHold(null, { sid: 'f', at: 1 }, outF, inF);
show('its chat pressed to go to its tab: it holds them all', pressedF);
show('…while you stay there', besideHold(pressedF, { sid: 'f', at: 1 }, outF, inF));
const leftF = besideHold(pressedF, { sid: 'f', at: 1 }, outF, [chatRow('f', 'ask:11', false)]);
show('…until you leave the tab', leftF);
show('…and coming back to it without the panel doesn\'t hold again', besideHold(leftF, { sid: 'f', at: 1 }, outF, inF));
show('…or until its chat goes', besideHold(pressedF, { sid: 'f', at: 1 }, [], inF));
const rowOnly = besideHold(null, { sid: 'f', at: 2 }, [], [chatRow('f', null, true)]);
show('a row pressed with no chat out for it holds nothing', rowOnly);
show('…nor a request that comes out later in that tab, while you work there',
     besideHold(rowOnly, { sid: 'f', at: 2 }, outF, inF));
show('nothing opened from the panel: nothing held', besideHold(null, null, outF, inF));
const pinned = { ...chats, out: chats.out.map((c) => (c.sid === 'b' ? { ...c, kept: true } : c)) };
show('pinned, the reply stays out; of two newer requests, the first to come takes the room left, and the other waits',
     chatsAt(besideStep(pinned, [chatRow('g', 'ask:12'), chatRow('e', 'ask:9'), ...asking], foldedRule)));
show('while the cat is moved, or its list is out, nothing more comes out', chatsAt(besideStep(chats, newest,
  { ...foldedRule, quiet: true })));
show('with the panel open, all of it counts as seen, and what was out goes', chatsAt(besideStep(chats, newest,
  { ...foldedRule, open: true })));
show('…folded again, nothing it showed comes out; only what\'s new since', chatsAt(besideStep(
  besideStep(chats, newest, { ...foldedRule, open: true }), [chatRow('h', 'reply:14'), ...newest], foldedRule)));

const night = { ...foldedRule, night: true };
const asleep = besideStep({ out: [], queue: [], done: {}, seeded: true },
                          [chatRow('w', 'wait:22'), chatRow('q', 'ask:21'), chatRow('r', 'reply:20')], night);
show('quiet hours, beside the folded panel: a request and a wait, both urgent, come out; a reply doesn\'t, and '
     + 'isn\'t seen', [chatsAt(asleep), asleep.done]);
show('…in the morning, it comes out, after those that came out in the night', chatsAt(besideStep(asleep,
  [chatRow('w', 'wait:22'), chatRow('q', 'ask:21'), chatRow('r', 'reply:20')], { ...night, night: false })));
const outBefore = besideStep({ out: [], queue: [], done: {}, seeded: true }, [chatRow('r', 'reply:20')],
                             { ...night, night: false });
show('…and a reply out as night began stays out',
     chatsAt(besideStep(outBefore, [chatRow('r', 'reply:20')], night)));
const lowOnTime = { ...outBefore, out: outBefore.out.map((c) => ({ ...c, left: 10000 })) };
show('…taking a newer reply without starting its time again',
     chatsAt(besideStep(lowOnTime, [chatRow('r', 'reply:30')], night)));
show('…but a request in its place starts it again', chatsAt(besideStep(lowOnTime, [chatRow('r', 'ask:31')], night)));


section('What a module says is new in a session');
const sideRow = (on = false) => chatRow('s', 'side:40', on, 'soon');
const sideOut = besideStep({ out: [], queue: [], done: {}, seeded: true }, [sideRow()], foldedRule);
show('a side chat\'s reply comes out beside the folded panel as a reply does', chatsAt(sideOut));
show('…read once you\'ve been in its session\'s tab', besideStep({ out: [], queue: [], done: {}, seeded: true },
                                                                  [sideRow(true)], foldedRule).done);
show('…and held at night, as a reply is',
     chatsAt(besideStep({ out: [], queue: [], done: {}, seeded: true }, [sideRow()], { ...foldedRule, night: true })));
show('what\'s been seen is kept by where each word came from, the part before its \':\', each replacing its own',
     [newsWithSeen('side:40', 'reply:9'), newsWithSeen(newsWithSeen('side:40', 'reply:9'), 'ask:q1'),
      newsWithSeen('reply:9 side:40', 'side:41'), newsSeen('reply:9 side:40', 'side:40'),
      newsSeen('reply:9 side:40', 'side:4')]);
// A side chat's reply came out and its time ran out; then a request came out, and was answered on its chat beside the
// folded panel, not in its tab: the reply already shown doesn't keep the chat out.
const sideSeen = { out: [{ sid: 's', news: 'ask:q', left: CHAT_MS, kept: false, evenSeen: true }], queue: [],
                   done: { s: 'side:40' }, seeded: true };
show('a request answered on its chat goes, though a side reply already shown stands behind it',
     chatsAt(besideStep(sideSeen, [sideRow()], foldedRule)));
const waitPassed = besideBack(besideStep({ ...sideSeen, out: [] }, [chatRow('s', 'wait:7')], foldedRule), 's');
show('…and a wait that came out and went doesn\'t make the reply new again', [waitPassed.done,
     chatsAt(besideStep(waitPassed, [sideRow()], foldedRule))]);
const lined = (line, at, on = false) => ({ ...chatRow('s', 'side:40', on, 'soon'), line, at });
const linedOut = besideStep({ out: [], queue: [], done: {}, seeded: true }, [lined('In your side chat: Yes.', 40)],
                            foldedRule);
show('a chat out for a module\'s word carries its line and time', linedOut.out.map(({ line, at }) => ({ line, at })));
show('…and drops them once the row\'s own news takes over',
     besideStep(linedOut, [chatRow('s', 'ask:q9')], foldedRule).out.map(({ news, line, at }) => ({ news, line, at })));
show('…and once its word has gone, kept out only by its tab, the row as it is',
     besideStep(linedOut, [chatRow('s', null, true)], foldedRule).out.map(({ sid, line, at }) => ({ sid, line, at })));

section('What the page\'s own senders say');
// A sender of the page's own, beside the app's notices: its notices get its name before their keys, a × puts one away
// with the app, as it was on the line, while what makes it new is the same (or folds it to its chip, if it says one),
// and its press is run here.
let pressedHere = 0, sayingHere = [], askedWith = null;
core.noticeSenders.push({ from: 'sample', notices: (...given) => { askedWith = given; return sayingHere; } });
const fromHere = (n) => ({ key: 'waits', level: 'urgent', text: 'A task from shop waits: Passkeys', button: 'Open',
                           press: () => { pressedHere++; }, since: 'a#1', ...n });
const hereNow = () => noticesHere().filter((n) => n.id.startsWith('sample/'))
  .map((n) => `${n.id} ${n.level}${n.closes ? ' ×' : ''}${n.folded ? ' folded' : ''}: ${n.text}`);
const told = [];
window.webkit = { messageHandlers: { panel: { postMessage: (m) => told.push(m.type === 'noticeAwayHere'
  ? `${m.type} ${m.id} ${m.since}${m.awayFor ? ` for ${m.awayFor}s` : ''}` : m.type) } } };
sayingHere = [fromHere()];
show('listed after the app\'s, with its sender\'s name and a ×', hereNow());
noticesDecide();
noticePressed('sample/waits');
show('its button runs its own press here, and tells the app nothing', { pressed: pressedHere, told });
sayingHere = [fromHere({ since: 'a#2' })];
noticeAway('sample/waits');
show('put away as it was on the line (a#1), told to the app: what changed since (a#2) still shows',
     { listed: hereNow(), told });
setNotices([], { shown: true }, { 'sample/waits': 'a#2' });
show('…the app keeping it away as it\'s said now: gone', hereNow());
sayingHere = [fromHere({ since: 'a#3', text: 'A task from shop waits: Passkeys, its next step' })];
show('…what makes it new changed: it\'s back', hereNow());
setNotices([], { shown: true }, { 'sample/waits': 'a#3' });
sayingHere = [fromHere({ since: 'a#3', chip: '3 waiting', chipTitle: 'Open One Task' })];
show('one that says what it folds to, put away: that alone, behind the rest, with no ×', hereNow());
show('…on the line, when nothing else is', noticeLine(noticesListed(), { shown: null, front: null, frontWith: [],
                                                                       typing: false }).line?.text);
sayingHere = [fromHere({ since: 'a#4', after: '3 waiting' })];
show('quiet words after its own are kept on the line', noticesHere().find((n) => n.id === 'sample/waits').after);
setNotices([], { shown: true }, { 'sample/waits': 'a#4' });
sayingHere = [fromHere({ since: 'a#4', after: '3 waiting', chip: '3 waiting' })];
show('…folded, the chip has none', noticesHere().find((n) => n.id === 'sample/waits').after ?? null);
sayingHere = [fromHere({ level: 'loud' }), { key: 'x', level: 'soon' }];
show('one with a level there isn\'t, or no words, is left out', hereNow());
sayingHere = [fromHere({ key: 'all-set', level: 'know', text: 'All set.', closes: false, done: true, tag: 'New' }),
              fromHere({ key: 'copy', level: 'soon', text: 'Copy it.', busy: true, pressedWord: 'Copied' })];
show('the fields the app\'s notices have: no ×, all went well, a tag; its button waiting, and its word after a press',
     noticesHere().filter((n) => n.id.startsWith('sample/'))
       .map(({ id, closes, done, busy, pressedWord, tag }) => ({ id, closes, done, busy, pressedWord, tag })));
pressedHere = 0;
noticePressed('sample/copy');
show('…a press while its button waits does nothing', pressedHere);
setNotices([], { shown: true }, { 'sample/copy': 'a#1' });
sayingHere = [fromHere({ key: 'copy', busy: true, chip: '1 to copy' })];
noticePressed('sample/copy');
show('…nor on its chip, once put away', pressedHere);
sayingHere = [fromHere({ since: 'f#1', awayFor: Infinity })];
show('a time away that isn\'t a number of seconds counts as none', noticesHere().find((n) => n.id === 'sample/waits')?.awayFor);
setNotices([], { shown: true }, {});
sayingHere = [fromHere({ level: 'soon', answersYou: true })];
show('one that answers something you just did says so', noticesHere().find((n) => n.id === 'sample/waits').answersYou);
sayingHere = [fromHere({ since: 'b#1', seenNow: true })];
show('one about what you\'re looking at now isn\'t said', hereNow());
sayingHere = [fromHere({ key: 'odd', session: '../s', outFor: -1 })];
show('a sender is asked with the time alone; one that says a session it can\'t take goes neither on the line nor '
     + 'beside the folded panel',
     { asked: askedWith.map((x) => typeof x), line: hereNow(),
       beside: besideNotices(NOW).filter((r) => r.id === 'sample/odd') });
told.length = 0;
sayingHere = [fromHere({ since: 'k#1', awayFor: 86400 })];
noticesDecide();
noticeAway('sample/waits');
show('one away for a day, put away: told to the app with its time', told);
const awayNow = state.noticeAwayHere['sample/waits'];
show('…away, as it\'s said the same way', hereNow());
state.noticeAwayHere['sample/waits'] = { ...awayNow, at: awayNow.at - 86401 * 1000 };
show('…back once the day has passed', hereNow());
show('away as the app keeps it: by what made it new, or that and a time',
     [noticeAwayStill('a#1', 'a#1', NOW), noticeAwayStill('a#1', 'a#2', NOW),
      noticeAwayStill({ since: 'a#1', at: NOW - 1000, awayFor: 60 }, 'a#1', NOW),
      noticeAwayStill({ since: 'a#1', at: NOW - 61000, awayFor: 60 }, 'a#1', NOW),
      noticeAwayStill(undefined, '', NOW)]);
sayingHere = [fromHere({ key: 'f1', session: 'f1', since: 'ask:9', text: '', seenNow: true, evenWhenSeen: true,
                         outFor: 45, at: 40, openedAt: 7 }),
              fromHere({ key: 'f2', session: 'local_f2', since: 'two words', text: 'A line.', outFor: 45 }),
              fromHere({ key: 'f1-again', session: 'f1', since: 'reply:1', outFor: 45 }),
              fromHere({ key: 'f3', session: 'f3', since: 'ask:1' }), fromHere({ key: 'plain' })];
show('one naming a session goes beside the folded panel, of two as urgent and as new the first, as its row (an id with \'_\' '
     + 'too, a since with a space being none), but not one that doesn\'t say how long it\'s out; the line has only the '
     + 'rest',
     { beside: besideRows(besideNotices(NOW), undefined, {}, NOW).filter((r) => r.id.startsWith('sample/')),
       line: noticesHere().filter((n) => n.id.startsWith('sample/')).map((n) => n.id) });
sayingHere = [fromHere({ key: 'k1', session: 'k', since: 'reply:1', level: 'soon', outFor: 45 }),
              fromHere({ key: 'k2', session: 'k', since: 'ask:2', level: 'urgent', outFor: 45 }),
              fromHere({ key: 'm1', session: 'm', since: 'a:1', level: 'soon', outFor: 45 }),
              fromHere({ key: 'z1', session: 'z', since: 'a:1', level: 'soon', outFor: 45 })];
const sampled = (rows) => rows.filter((r) => r.id.startsWith('sample/')).map((r) => r.id);
const rowsAt = (now, sessions, sinceAt = {}) => sampled(besideRows(besideNotices(now), sessions, sinceAt, now));
show('two naming one session: the more urgent says it, in the senders\' order while the place gives none',
     rowsAt(NOW));
show('…in the place\'s own order once it gives one, each session once, leaving out a session it can\'t show',
     rowsAt(NOW, ['m', 'k', 'm']));
sayingHere = [fromHere({ key: 'n1', session: 'n', since: 'a:1', level: 'soon', outFor: 45 }),
              fromHere({ key: 'n2', session: 'n', since: 'b:1', level: 'soon', outFor: 45 })];
let keptNow = { done: {}, listedAt: {}, sinceAt: {}, loadedAt: NOW };
keptNow = { ...keptNow, ...besideListed(keptNow, besideNotices(NOW), NOW) };
const firstSaid = rowsAt(NOW, undefined, keptNow.sinceAt);
sayingHere = [sayingHere[0], fromHere({ key: 'n2', session: 'n', since: 'b:2', level: 'soon', outFor: 45 })];
keptNow = { ...keptNow, ...besideListed(keptNow, besideNotices(NOW + 1000), NOW + 1000) };
show('…of two as urgent, the first listed while their sinces came together, then the one whose since came last',
     [firstSaid, rowsAt(NOW + 1000, undefined, keptNow.sinceAt)]);
sayingHere = [fromHere({ key: 'p1', session: 'p', since: '', level: 'soon', outFor: 45 }),
              fromHere({ key: 'p2', session: 'p', since: 'a:1', level: 'soon', outFor: 45 })];
show('…and of two as urgent, one with something new, though the other\'s since went empty after it came',
     rowsAt(NOW, undefined, { 'sample/p1': { since: null, at: NOW }, 'sample/p2': { since: 'a:1', at: NOW - 5000 } }));
// Two notices on one session, neither changing, for three minutes, decided every 30 seconds as besideDecide does, its
// chat sent back as soon as it comes out: both are listed each time, so what's been seen of each is kept, and the same
// one says the chat throughout.
sayingHere = [fromHere({ key: 'n1', session: 'n', since: 'a:1', level: 'soon', outFor: 45 }),
              fromHere({ key: 'n2', session: 'n', since: 'b:1', level: 'soon', outFor: 45 })];
let held = { done: {}, listedAt: {}, sinceAt: {}, loadedAt: NOW - 200000 };
let heldChats = { out: [], queue: [], done: {}, seeded: true };
const cameOut = [], saidBy = new Set();
for (let t = NOW - 180000; t <= NOW; t += 30000) {
  const listed = besideNotices(t);
  held = { ...held, ...besideListed({ ...held, done: heldChats.done }, listed, t) };
  const rows = besideRows(listed, undefined, held.sinceAt, t);
  rows.filter((r) => r.id.startsWith('sample/')).forEach((r) => saidBy.add(r.id));
  heldChats = besideStep({ ...heldChats, done: held.done }, rows, foldedRule);
  cameOut.push(...heldChats.out.filter((c) => heldChats.came.includes(c.sid)).map((c) => `${c.id} ${c.news}`));
  for (const c of [...heldChats.out]) heldChats = besideBack(heldChats, c.sid);
  held.done = heldChats.done;
}
show('two on one session for three minutes: it comes out once, said by the same one', { came: cameOut,
                                                                                          saidBy: [...saidBy] });
show('what\'s been seen of one is forgotten a minute after it was last listed, or after the page loaded',
     Object.keys(besideForgotten({ 'x/listed': 'a:1', 'x/gone': 'a:2', 'x/never': 'a:3' },
                                 { 'x/listed': NOW - 1000, 'x/gone': NOW - 61000 }, NOW - 30000, NOW)));
// How long a chat is out at most rides with it, from its row, for the place's ring.
const outForRow = (news, outFor, level = 'urgent') => ({ ...chatRow('o', news), outFor, level });
const timeOf = (chats) => chats.out.map(({ outFor, left }) => ({ outFor, left }));
const outO = besideStep({ out: [], queue: [], done: {}, seeded: true }, [outForRow('ask:1', 45)], foldedRule);
show('a chat that comes out carries how long it\'s out', timeOf(outO));
const lowO = { ...outO, out: outO.out.map((c) => ({ ...c, left: 10000 })) };
show('…something new in it by day takes its row\'s time again', timeOf(besideStep(lowO, [outForRow('ask:2', 30)],
                                                                                 foldedRule)));
show('…at night, something new that isn\'t urgent keeps what it had',
     timeOf(besideStep(lowO, [outForRow('reply:3', 30, 'soon')], { ...foldedRule, night: true })));
delete window.webkit;
setNotices([], { shown: true }, {});
core.noticeSenders.pop();

// The panel page's logic, run outside the app by tests/panel.sh: which section each sample session goes in, how rows
// sort, and the HTML of sample rows. Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('What each session is');
const reply = { lastPrompt: 'fix it', lastPromptAt: min(6), lastReply: 'Fixed.', lastReplyAt: min(5) };
const unread = { seen: {} };
const readHere = (sid, at = min(1)) => ({ seen: { [sid]: at } });
const repliedAt = (at, fields) => ({ lastPrompt: 'go on', lastPromptAt: at - 60000, lastReply: 'Done.',
                                    lastReplyAt: at, ...fields });
show('a request waiting', classify(session({ ask: { id: 'a', tool: 'Bash', input: {} } }), NOW, unread));
show('Claude waiting on you', classify(session({ status: 'waiting' }), NOW, unread));
show('working', classify(session({ status: 'busy' }), NOW, unread));
show('replied 5 min ago, not opened', classify(session({ ...reply, sessionId: 'r1' }), NOW, unread));
show('replied, opened here since', classify(session({ ...reply, sessionId: 'r2' }), NOW, readHere('r2')));
show('replied, open in Claude since',
  classify(session({ ...reply, sessionId: 'r3', lastFocusedAt: min(1) }), NOW, unread));
show('replied, looked at since in Claude or Ghostty, as the app saw',
  classify(session({ ...reply, seenAt: min(4) }), NOW, unread));
show('…only before it replied', classify(session({ ...reply, seenAt: min(6) }), NOW, unread));
show('replied, opened here only before it replied',
  classify(session({ ...reply, sessionId: 'r2' }), NOW, readHere('r2', min(10))));
show('a turn you stopped: you wrote to it after its reply',
  classify(session({ ...repliedAt(min(20)), lastPromptAt: min(2) }), NOW, unread));
show('replied 40 min ago, not opened', classify(session(repliedAt(min(40))), NOW, unread));
show('replied 40 min ago, opened', classify(session({ ...repliedAt(min(40)), sessionId: 'r2' }), NOW, readHere('r2')));
show('replied 2 h ago, not opened: still waiting for you', classify(session(repliedAt(min(120))), NOW, unread));
show('replied 61 min ago, opened then',
  classify(session({ ...repliedAt(min(61)), sessionId: 'r2' }), NOW, readHere('r2', min(61))));
show('replied 2 h ago, opened a minute ago: an hour from when you were last on it',
  classify(session({ ...repliedAt(min(120)), sessionId: 'r2' }), NOW, readHere('r2')));
show('replied 61 min ago, and you wrote to it 30 min ago',
  classify(session({ ...repliedAt(min(61)), lastPromptAt: min(30) }), NOW, unread));
show('a turn you stopped long after its reply, its transcript moving until 5 min ago',
  classify(session({ ...repliedAt(min(75)), lastPromptAt: min(70), messageAt: min(5) }), NOW, unread));
show('never replied', classify(session({}), NOW, unread));
show('a closed conversation that replied 5 min ago, not opened',
  classify(session({ ...reply, status: 'closed', entrypoint: 'claude-desktop', pid: 0 }), NOW, unread));
show('a terminal session that has ended, its reply 5 min ago not read', classify(session({ ...reply,
  status: 'closed', pid: 0, opensIn: 'Ghostty' }), NOW, unread));
show('…its reply 2 h ago read then', classify(session({ ...repliedAt(min(120)), sessionId: 'k1', status: 'closed',
  pid: 0, opensIn: 'Ghostty' }), NOW, readHere('k1', min(119))));
show('replied 3 h ago, before the page first kept the replies you had not read, not opened',
  classify(session(repliedAt(min(180))), NOW, { seen: {}, readBefore: min(120) }));
show('your turn since, a request', turnSince(session({ ask: { id: 'a', tool: 'Bash', input: {}, at: min(3) } }),
                                             'needs') === min(3));
show('…Claude waiting on you, from when its status changed',
  turnSince(session({ status: 'waiting', statusUpdatedAt: min(4) }), 'needs') === min(4));
show('…a reply', turnSince(session(reply), 'turn') === min(5));
show('a reply you read 9 min ago: still in Your turn',
  sectionOf(session({ ...reply, sessionId: 'r2' }), 'seen', NOW, readHere('r2', min(9))));
show('…10 min ago: in Seen', sectionOf(session({ ...reply, sessionId: 'r2' }), 'seen', NOW, readHere('r2', min(10))));

section('Where each row goes');
// The rows in the order they're shown, section by section: each row's id, with what it is when that isn't its
// section's own (a request in Your turn, or a row you've pressed that has changed).
function where(placed) {
  let out = '', at = null;
  for (const p of placed) {
    out += p.section === at ? ' ' : `${at ? ' · ' : ''}${p.section}: `;
    out += p.s.sessionId + (p.kind === p.section ? '' : `(${p.kind})`);
    at = p.section;
  }
  return out;
}
// One update after another, each placed as render places it at the app's time `now`: the rows you've pressed (`held`)
// where they were last shown, with when you were last on each session as `view` says.
const placedAt = {};
const placeAll = (sessions, held = [], now = NOW, view = unread) => {
  const placed = placeRows(sessions.map((s) => ({ s, kind: classify(s, now, view) })), placedAt,
                           (sid) => held.includes(sid), now, view);
  for (const { s, section, key, tie, latest } of placed) placedAt[s.sessionId] = { section, key, tie, latest };
  return where(placed);
};
const asked = (id, at) => ({ ask: { id, tool: 'Bash', input: {}, at } });
const lineup = [
  session({ sessionId: 'r1', ...repliedAt(min(5)) }),
  session({ sessionId: 'q2', status: 'waiting', statusUpdatedAt: min(3) }),
  session({ sessionId: 'w1', status: 'busy', lastPromptAt: min(20) }),
  session({ sessionId: 's1', ...repliedAt(min(30), { lastFocusedAt: min(29) }) }),
  session({ sessionId: 'q1', ...asked('q1', min(8)) }),
  session({ sessionId: 'i1', ...repliedAt(min(90), { lastFocusedAt: min(89) }) }),
  session({ sessionId: 'r2', ...repliedAt(min(12)) }),
  session({ sessionId: 'w2', status: 'busy', lastPromptAt: min(2) }),
  session({ sessionId: 's2', ...repliedAt(min(14), { lastFocusedAt: min(13) }) }),
  session({ sessionId: 'i2' }),
];
show('Your turn first come, first served; Working and Seen newest first; then Idle', placeAll(lineup));
const q3 = session({ sessionId: 'q3', ...asked('q3', min(1)) });
show('a new request joins the end of Your turn, and nothing above it moves', placeAll([...lineup, q3], [], NOW + 1000));
const others = [...lineup.filter((s) => s.sessionId !== 'r1'), q3];
const r1 = (fields) => session({ sessionId: 'r1', ...repliedAt(min(5)), ...fields });
show('a row you pressed, to read it: it stays where it was, with what it is now',
  placeAll([...others, r1({ lastFocusedAt: min(1) })], ['r1'], NOW + 2000));
show('…answered, and working again: still there',
  placeAll([...others, r1({ status: 'busy', lastPromptAt: min(1), lastFocusedAt: min(1) })], ['r1'], NOW + 3000));
show("…once you've moved on from the panel, it goes where it belongs now",
  placeAll([...others, r1({ status: 'busy', lastPromptAt: min(1), lastFocusedAt: min(1) })], [], NOW + 4000));
show("a row you pressed that wasn't shown yet goes where it belongs",
  placeAll([...others, session({ sessionId: 'n1', status: 'busy', lastPromptAt: min(1) })], ['n1'], NOW + 5000));
const backAtWork = session({ sessionId: 'i1', ...repliedAt(min(90), { lastFocusedAt: min(89) }), status: 'busy',
                             lastPromptAt: NOW - 1000 });
show('a row you pressed in Idle stays there as it starts work again',
  placeAll([...others.filter((s) => s.sessionId !== 'i1'), backAtWork], ['i1'], NOW + 6000));
const atWork = others.filter((s) => s.sessionId !== 'w1');
const w1Replied = session({ sessionId: 'w1', ...repliedAt(min(1)) });
show('a row you pressed that replies meanwhile stays where it was',
  placeAll([...atWork, w1Replied], ['w1'], NOW + 7000));
const q4 = session({ sessionId: 'q4', ...asked('q4', NOW - 500) });
show('…while a request that comes joins the end of Your turn',
  placeAll([...atWork, q4, w1Replied], ['w1'], NOW + 8000));
show("…and once you've moved on, it joins the end after that request, though its reply came first",
  placeAll([...atWork, q4, w1Replied], [], NOW + 9000));
const m1 = session({ sessionId: 'm1', ...repliedAt(min(5)) });
const m2 = session({ sessionId: 'm2', ...repliedAt(min(4)) });
const w3 = session({ sessionId: 'w3', status: 'busy', lastPromptAt: min(3) });
const later = (minutes) => NOW + 20000 + minutes * 60000;
const onM1 = { seen: { m1: later(0) } };
show('two replies waiting, one working', placeAll([m1, m2, w3], [], later(0)));
show('a reply you read stays in Your turn, where it was, while you are on it',
  placeAll([m1, m2, w3], [], later(0) + 1000, onM1));
show('…and for ten minutes after you were last on it', placeAll([m1, m2, w3], [], later(9.9), onM1));
show('…then it goes to Seen', placeAll([m1, m2, w3], [], later(10), onM1));
const w3Replied = session({ sessionId: 'w3', ...repliedAt(later(10) + 500) });
show('a reply that comes in while you are on it joins the end of Your turn',
  placeAll([m1, m2, w3Replied], [], later(10) + 1000, { seen: { m1: later(0), w3: later(10) + 1000 } }));
goTo('i1');
show("the session you're on isn't held: its row goes where it belongs", heldNow()('i1'));
goTo(null);
state.pointer = { x: 20, y: 40 };
keepInPlace('p1');
show('a row you pressed is held while your pointer is on the panel', heldNow()('p1'));
state.pointer = null;
state.keyboardWanted = true;
show('…and while you type in one of its boxes, wherever the pointer is', heldNow()('p1'));
state.keyboardWanted = false;
state.pointerStill = true;
show("…and while your pointer is off the panel but hasn't moved: the panel's edge went past it", heldNow()('p1'));
state.pointerStill = false;
show('…and let go once your pointer has left the panel', heldNow()('p1'));
// What the pointer was on is left alone here (hover.js, with its timers).
const settle = renderWhenSettled, gone = pointerGone;
let drawnAgain = 0;
renderWhenSettled = () => { drawnAgain += 1; };
pointerGone = () => { state.pointer = null; };
state.pointer = { x: 20, y: 40 };
keepInPlace('p1');
hoverEnd(true);
show('your pointer off the panel without moving, as a card folds away: the row you pressed is still held',
  [drawnAgain, heldNow()('p1')]);
hoverEnd();
show('…and once it moves, the list is drawn again to let the row go', drawnAgain);
state.pressedRows.clear();
state.pointer = { x: 20, y: 40 };
hoverEnd();
show('…but not with no row pressed', drawnAgain);
keepInPlace('p1');
state.keyboardWanted = true;
keyboardGone();
show('another app taking the keyboard: the panel no longer has it, and the list is drawn again for the rows pressed',
  [state.keyboardWanted, drawnAgain]);
state.pressedRows.clear();
renderWhenSettled = settle;
pointerGone = gone;

section('What you have read');
// One update after another, each with the session the app marks as the one you're on (followClaude runs on them, as
// render does), at the app's time `now`.
const lastBefore = state.last;
const markOn = (sid, sessions, now) => {
  state.last = { sessions: sessions.map((s) => ({ ...s, focused: s.sessionId === sid })), now };
  followClaude();
};
const kindOn = (sid) => classify(state.last.sessions.find((s) => s.sessionId === sid), NOW, view());
const tabs = [session({ sessionId: 'ta', ...repliedAt(min(10)) }), session({ sessionId: 'tb', ...repliedAt(min(9)) })];
markOn('ta', tabs, min(7));
markOn('tb', tabs, min(6));
show('the session you are on follows the mark, which alone reads nothing', [state.current, kindOn('tb')]);
markOn('tb', [tabs[0], { ...tabs[1], seenAt: min(5) }], min(5));
keepSeen(state.last.sessions, min(5));
show('…the app saw you looking at it after it replied: read', kindOn('tb'));
markOn('tb', tabs, min(4));
show('…and still read once the app has restarted, as the page keeps it', kindOn('tb'));
markOn('tb', [tabs[0], session({ sessionId: 'tb', ...repliedAt(min(3)), seenAt: min(4) })], min(3));
show('…a reply that came after you last looked is not read', kindOn('tb'));
const sectionOn = (sid, now) => {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  return sectionOf(s, classify(s, now, view()), now, view());
};
markOn('tb', tabs, min(4));
show('a reply you have read is in Your turn while you are on it', sectionOn('tb', min(4)));
markOn('tb', [tabs[0], { ...tabs[1], seenAt: min(1) }], min(1));
keepSeen(state.last.sessions, min(1));
show('…what the page keeps follows you while you stay on it', state.seen.tb === min(1));
markOn('ta', tabs, NOW);
show('…and once you are on another, it stays in Your turn for ten minutes after you were last on it, then in Seen',
  [sectionOn('tb', NOW + 8.9 * 60000), sectionOn('tb', NOW + 9 * 60000)]);
markOn('tb', [tabs[0], { ...tabs[1], seenAt: NOW + 12 * 60000 }], NOW + 12 * 60000);
keepSeen(state.last.sessions, NOW + 12 * 60000);
show('once you have moved on, being on it again leaves it in Seen',
  [state.seen.tb === min(1), sectionOn('tb', NOW + 12 * 60000)]);
markOn('tb', [tabs[0], session({ sessionId: 'tb', ...repliedAt(NOW + 13 * 60000), seenAt: NOW + 14 * 60000 })],
       NOW + 14 * 60000);
keepSeen(state.last.sessions, NOW + 14 * 60000);
show('…until something new comes: a reply it sends while you are on it is read, and in Your turn',
  [kindOn('tb'), sectionOn('tb', NOW + 14 * 60000)]);
state.opening = { sessionId: 'ta', at: Date.now() };
markOn('tb', tabs, min(2));
show('a conversation just opened in Claude is the one you are on at once, before Claude says so', state.current);
state.opening = null;
state.last = lastBefore;
state.seen = {};
state.claudeShowed = null;
goTo(null);

section('The list');
// What the list shows, in order: each header with its count (› when it's folded), each project by its folder, where a
// group's rows are (folded away or not) and the copies pinned below a folded one, and each row's id with its classes.
function outline(html) {
  const parts = new RegExp([/<div class="group[^"]*?( collapsed)?" data-key="[^"]*">([^<]*)<span class="n">(\d+)/,
                             /<div class="project( collapsed)?" data-key="([^"]*)"/,
                             /<div class="(prows(?: closed)?|pinned)">/, /<div class="row ([^"]*)" data-id="([^"]*)"/]
    .map((part) => part.source).join('|'), 'g');
  return [...html.matchAll(parts)].map(([, folded, name, n, projectFolded, project, body, cls, id]) =>
    name ? `[${name} ${n}${folded ? ' ›' : ''}]`
      : project ? `[${project}${projectFolded ? ' ›' : ''}]`
      : body ? `(${body === 'pinned' ? 'pinned' : body === 'prows' ? 'rows' : 'folded'})`
      : `${id}.${cls.trim().split(' ').join('.')}`).join(' ');
}
// The rows placed once, those in `held` where it says they were last shown.
const placeOnce = (sessions, held = {}) =>
  placeRows(sessions.map((s) => ({ s, kind: classify(s, NOW, unread) })), held, (sid) => sid in held, NOW, unread);
show('the sections in order, Idle folded', outline(sectionsHTML(placeOnce(lineup), NOW)));
const inIdle = { i1: { section: 'idle', key: 0, tie: 0, latest: 0 } };
show('a row you pressed, held in folded Idle with a request: pinned below it', outline(sectionsHTML(placeOnce([
  session({ sessionId: 'w1', status: 'busy', lastPromptAt: min(2) }),
  session({ sessionId: 'i1', ...asked('i1', min(1)) }),
  session({ sessionId: 'i2' }),
], inIdle), NOW)));
show('…or at work again: pinned too, while you are with it', outline(sectionsHTML(placeOnce([
  session({ sessionId: 'w1', status: 'busy', lastPromptAt: min(2) }),
  session({ sessionId: 'i1', status: 'busy', lastPromptAt: min(1) }),
  session({ sessionId: 'i2' }),
], inIdle), NOW)));
state.groupBy = 'project';
const inRepo = (sessionId, root, fields) => session({ sessionId, cwd: root, git: { branch: 'main', root }, ...fields });
state.closedProjects['/work/other'] = true;
show('a folded project: a reply waiting in it pinned below it', outline(projectsHTML(placeOnce([
  inRepo('g1', '/work/app', reply),
  inRepo('g3', '/work/other', repliedAt(min(30))),
  inRepo('g4', '/work/other', {}),
]), NOW)));
delete state.closedProjects['/work/other'];
const one = inRepo('a1', '/work/one', repliedAt(min(2)));
const two = (fields) => inRepo('b1', '/work/two', { ...repliedAt(min(20), { lastFocusedAt: min(19) }), ...fields });
const twoWas = Object.fromEntries(placeOnce([one, two({})]).map(({ s, section, key, tie, latest }) =>
  [s.sessionId, { section, key, tie, latest }]));
const twoAtWork = two({ status: 'busy', lastPromptAt: NOW - 1000 });
show('projects by their newest row', outline(projectsHTML(placeOnce([one, two({})]), NOW)));
show('…but a row you pressed keeps its project where it was, as it starts work',
  outline(projectsHTML(placeOnce([one, twoAtWork], { b1: twoWas.b1 }), NOW)));
show("…until you've moved on", outline(projectsHTML(placeOnce([one, twoAtWork]), NOW)));
state.groupBy = 'status';

section("The row you're on, held at the edge");
show('in view', stickyEdge(10, 150, 500));
show('just past the top: under the header', stickyEdge(-1, 150, 500));
show('just past the bottom: above the bottom edge', stickyEdge(360, 150, 500));
show('wholly above, and wholly below', [stickyEdge(-400, 150, 500), stickyEdge(900, 150, 500)]);
show('right at either edge: still in view', [stickyEdge(0, 150, 500), stickyEdge(350, 150, 500)]);
// A row of seven lines with its padding (9 and 9): its title, your message, Claude's line, where it runs, the island,
// the setup line and a pull request. The title, Claude's line and where it runs stay.
const rowLines = [['title', 17, true], ['you', 18, false], ['claude', 18, true], ['where', 19, true],
                  ['island', 23, false], ['setup', 19, false], ['pr', 19, false]]
  .map(([name, extent, keep]) => ({ name, extent, keep }));
const rowFull = 18 + rowLines.reduce((sum, l) => sum + l.extent, 0);
// The copy `past` points past the edge: its height, what has folded off which line, how attached it is, and how far
// rows are under it.
const foldAt = (past, edge) => {
  const f = stickyFold(rowLines, rowFull, rowFull - past, edge);
  const folded = rowLines.map((l, i) => (f.folds[i] ? `${l.name} −${f.folds[i]}` : '')).filter(Boolean);
  return `${f.height} tall | ${folded.join(', ') || 'nothing folded'} | attached ${+f.attach.toFixed(2)}, `
    + `under ${+f.under.toFixed(2)}`;
};
for (const past of [0, 12, 30, 52, 74, 96, 130]) show(`at the top edge, ${past} points past it`, foldAt(past, 'top'));
for (const past of [12, 30, 52, 74, 96]) show(`at the bottom edge, ${past} points past it`, foldAt(past, 'bottom'));
show('as tall as what of its place is in view, so the row next to it stays touching it',
  [0, 12, 30, 52, 74].every((past) => stickyFold(rowLines, rowFull, rowFull - past, 'top').height === rowFull - past));
show('…what has gone all folded off the lines that go',
  [12, 30, 52, 74].every((past) => stickyFold(rowLines, rowFull, rowFull - past, 'bottom').folds
    .reduce((sum, f) => sum + f, 0) === past));
show('…and never less than the lines that stay', stickyFold(rowLines, rowFull, 10, 'top').height);
show('a place still taller than the copy (a line it lost folding away there): as tall as the place, nothing folded',
  foldAt(-14, 'top'));
// A line of the copy 19 tall under a margin of 3, folding by f.
const lineAt = (f, edge) => {
  const fold = stickyLineFold({ h: 19, m: 3 }, f, edge);
  return `margins ${fold.marginTop}/${fold.marginBottom}, cut ${fold.clip.join('/')}, `
    + `faded to ${+fold.opacity.toFixed(2)}`;
};
for (const f of [0, 2, 8, 22])
  show(`a line folding ${f} points at the top edge: its foot goes under`, lineAt(f, 'top'));
for (const f of [2, 8, 22]) show(`…and at the bottom edge: its margin, then its head`, lineAt(f, 'bottom'));
// Whether it holds on: the row 150 tall in a list showing 500, with how it was till now and whether its top has moved
// toward the edge it's past.
const holdAt = (t, how) => JSON.stringify(stickyHold(t, 150, 500, { was: null, inView: true, away: true,
                                                                     typing: false, ...how }));
show('taken just past the top (scrolled, or moved by the list): holds on in place, no fade', holdAt(-2));
show('…past the bottom (moved to a section further down as it starts working)', holdAt(352));
show('only grown past the bottom, its top where it was (a card opening on it): stays as it is, in view',
  holdAt(352, { away: false }));
show('…until something takes it further: then it fades in', holdAt(360, { inView: false }));
show('…but not when it\'s brought back toward view', holdAt(356, { inView: false, away: false }));
show('one of its boxes typed in: never', holdAt(-2, { typing: true }));
show('taller than the list: never', JSON.stringify(stickyHold(-2, 520, 500, { away: true, inView: true })));
show('holding on, the list moving it further or back: still holds on', holdAt(-40, { was: 'top', away: false }));
show('back in view: hands back at once, however far it came in one frame',
  [0.5, 30, 120].map((t) => holdAt(t, { was: 'top' })).join(' '));
show('…and from the bottom edge', [349.6, 200].map((t) => holdAt(t, { was: 'bottom' })).join(' '));
show('still past the edge but now typed in, or too tall: fades out',
  [holdAt(-20, { was: 'top', typing: true }), JSON.stringify(stickyHold(-20, 520, 500, { was: 'top' }))].join(' '));
show('from one edge to the other at once: fades in there', holdAt(400, { was: 'top' }));
// Where a row goes to be shown whole, and how far the list scrolls for that.
show('a row 150 tall, shown from the top and from the bottom', [showAt(150, 500, 'top'), showAt(150, 500, 'bottom')]);
show('…about as tall as the list: no gap that would push it out at the other edge',
  [showAt(498, 500, 'top'), showAt(498, 500, 'bottom')]);
show('…clear of the copy held at the top (72) or the bottom (80)',
  [showAt(150, 500, 'top', 72, 0), showAt(150, 500, 'bottom', 0, 80)]);
show('what the copy would cover once the list has scrolled: still past the top, at least its lines that stay',
  stickyCovers(-100, 150, 500, 72, 20));
show('…past the top, more of its place in view than that', stickyCovers(-30, 150, 500, 72, -10));
show('…back in view, nothing', stickyCovers(-30, 150, 500, 72, -40));
show('…past the bottom', stickyCovers(420, 150, 500, 72, 0));
show('…taller than the list, nothing', stickyCovers(-100, 520, 500, 72, 0));
// Back in view, what came on the row while it was away counts as only just shown.
state.shownAt = { 'compact:s': NOW - 5000, 'island:other': NOW - 5000, ask1: NOW - 5000 };
const realNow = Date.now;
Date.now = () => NOW;
showAgain(session({ sessionId: 's', ask: { id: 'ask1' } }));
Date.now = realNow;
show('the row back in view: its cards and its request count as just shown, another row\'s don\'t',
  Object.entries(state.shownAt).map(([key, at]) => `${key} ${at === NOW ? 'now' : 'before'}`).join(', '));
state.shownAt = {};

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
show('your message has just come in, though the status changed long ago: working',
  steady(session({ status: 'idle', statusUpdatedAt: NOW - 5000, lastPromptAt: NOW - 500 }), NOW).status);
show('changed over 3 s ago, and your message too: as it is',
  steady(session({ status: 'idle', statusUpdatedAt: NOW - 5000, lastPromptAt: NOW - 4000 }), NOW).status);

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
const pr = (fields) => Object.assign({ url: 'https://github.com/e/app/pull/1', number: 1, state: 'OPEN',
                                       isDraft: false, review: '', checks: 'passing' }, fields);
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
  ['your turn, with PRs and a worktree', session({ sessionId: 't1', ...reply, outcome: 'Tested',
    checkout: { changes: 1 },
    git: { branch: 'feature', root: '/work/app-f', worktree: 'app-f', worktreeOf: 'app', mainRoot: '/work/app' },
    prs: [pr({ title: 'Fix the tests', repo: 'e/app' }),
          pr({ url: 'https://github.com/e/app/pull/2', number: 2, isDraft: true, title: 'Draft' })],
    agent: { model: 'claude-sonnet-5-5', effort: 'medium', mode: 'bypassPermissions', tokens: 150000 } })],
  ['a reply you have read', session({ sessionId: 'v1', ...reply, outcome: 'Answered', lastFocusedAt: min(1) })],
  ['a turn you stopped: only your message, not the reply before it', session({ sessionId: 'v2',
    ...repliedAt(min(20)), lastPrompt: 'now rename it', lastPromptAt: min(2) })],
  ['a closed Claude Desktop conversation, open in Claude', session({ sessionId: 'd1', status: 'closed',
    entrypoint: 'claude-desktop', focused: true, name: 'Desk chat', pid: 0, lastReply: 'Done.', lastReplyAt: min(300),
    lastPromptAt: min(301), lastFocusedAt: min(299), outcome: 'Answered', git: null, cwd: '/work/notes' })],
  ['a terminal session that has ended, which a press opens again in Ghostty', session({ sessionId: 'k1',
    status: 'closed', pid: 0, opensIn: 'Ghostty', name: 'Fix the page', lastReply: 'Done.', lastReplyAt: min(120),
    lastPromptAt: min(121), git: null, cwd: '/work/site' })],
];
for (const [name, s] of rows) print(`-- ${name}\n${rowHTML(s, classify(s, NOW, view()), NOW)}`);
state.compactOpen.c1 = true;
const compacting = session({ sessionId: 'c1', agent: { model: 'claude-opus-5-5', tokens: 900000 } });
print(`-- the Compact card open\n${rowHTML(compacting, classify(compacting, NOW, view()), NOW)}`);
delete state.compactOpen.c1;
show("a terminal session that's the one you're on says where it's open",
     /title="Open in your terminal now"/.test(rowHTML(session({ sessionId: 'f1', focused: true }), 'idle', NOW)));
const tipOf = (fields) => /title="([^"]*)"/.exec(rowHTML(session({ sessionId: 'k2', status: 'closed', pid: 0,
  ...fields }), 'idle', NOW))?.[1];
show('a terminal session that has ended says where a press opens it again', tipOf({ opensIn: 'iTerm2' }));
show('…with no terminal to name', tipOf({}));
show('…its terminal\'s name escaped', tipOf({ opensIn: 'My "Term" <1>' }));
show('a closed Claude Desktop conversation says a press opens it in Claude', tipOf({ entrypoint: 'claude-desktop' }));
state.opening = { sessionId: 'd2', at: NOW };
show('a Claude Desktop conversation just clicked is the only one marked, not the terminal session you were on',
     [session({ sessionId: 'd2', entrypoint: 'claude-desktop' }), session({ sessionId: 'f1', focused: true })]
       .map((s) => openedNow(s).focused));
state.opening = { sessionId: 't2', at: NOW };
show('…and so is a terminal session just clicked, before the app has read its tab',
     [session({ sessionId: 't2' }), session({ sessionId: 'f1', focused: true })].map((s) => openedNow(s).focused));
state.opening = null;

section('Open twice');
// A conversation running in more than one process: its details line says so, and pointed at, where else it's open and
// what that means: another copy in a terminal holds up everything the panel types, one in Claude Desktop only the mode.
// A copy paused in its terminal takes nothing from the panel, so its card says only what bringing it back would do.
const twice = session({ sessionId: 'o1', alsoOpen: [{ entrypoint: 'cli', paused: false }] });
show('its details line', /<div class="where"[^]*?<\/div>/.exec(rowHTML(twice, 'idle', NOW))?.[0]);
show('in another terminal tab', twiceCardHTML(twice));
show('in Claude Desktop', twiceCardHTML(session({ alsoOpen: [{ entrypoint: 'claude-desktop', paused: false }] })));
show('in Claude Desktop, and paused in a terminal', twiceCardHTML(session({
  alsoOpen: [{ entrypoint: 'claude-desktop', paused: false }, { entrypoint: 'cli', paused: true }] })));
show('a Claude Desktop conversation in a terminal tab too', twiceCardHTML(session({ entrypoint: 'claude-desktop',
  alsoOpen: [{ entrypoint: 'cli', paused: false }] })));
show('its other copy at work', twiceCardHTML(session({
  alsoOpen: [{ entrypoint: 'cli', paused: false, busy: true }] })));
show('in two other terminal tabs', twiceCardHTML(session({
  alsoOpen: [{ entrypoint: 'cli', paused: false }, { entrypoint: 'cli', paused: false }] })));
show('only a paused copy', twiceCardHTML(session({ alsoOpen: [{ entrypoint: 'cli', paused: true }] })));

section('HTML of projects');
state.groupBy = 'project';
state.closedProjects['/work/other'] = true;
print(projectsHTML(placeRows([
  session({ sessionId: 'g1', ...reply }),
  session({ sessionId: 'g2', status: 'busy', lastPromptAt: min(1) }),
  session({ sessionId: 'g3', cwd: '/work/other', git: { branch: 'main', root: '/work/other' }, outcome: 'Answered',
    lastReplyAt: min(500), seenAt: min(499) }),
].map((s) => ({ s, kind: classify(s, NOW, unread) })), {}, () => false, NOW, unread), NOW));
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
  seen: { listed: earlier(7200000), endedLongAgo: earlier(7200000), endedJustNow: earlier(7200000),
          readRecently: earlier(60000), readWithinTheHour: earlier(40 * 60000) },
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
show('confirmed, a reply waiting or read: ready',
  [offer(built, 'turn', dep({})).look, offer(built, 'seen', dep({})).look]);
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
  Object.fromEntries(sessions.map((s) => [s.sessionId, classify(s, NOW, unread)])));
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

print('-- a row with changed files it didn\'t change itself: the island under the details line');
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
print('-- Show Next Steps off: no island');
state.switches = { ...state.switches, nextSteps: false };
print(rowHTML(withSteps('w6', { changes: 3 }), 'idle', NOW));
state.switches = { ...state.switches, nextSteps: true };
state.deploys = { projects: {}, folders: {} };
Date.now = pageClock;
state.owners = new Set();

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
print('-- its numbers end the details line, as a button');
print(metaHTML({ s: chRow, kind: 'idle' }));
state.reading = { sessionId: 'me', mode: 'changes' };
show('pressed while its changes are open', countsHTML(chRow).includes('counts on'));
state.reading = { sessionId: 'me', mode: 'writings' };
show('…not while what it wrote is', countsHTML(chRow).includes('counts on'));
state.reading = null;
show('nothing changed: no numbers', countsHTML(session({ changes: { added: 0, removed: 0, files: [] } })));
show('the branch, from its side: itself, the others biggest first, then outside these sessions', branchParts(chRow, chSessions));
show('…from the other session\'s', branchParts({ ...chRow, sessionId: 'tests' }, chSessions).parts.map((p) => p.name));
state.last = { sessions: chSessions, now: NOW };
print(changesCardHTML(chRow));
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
print(countsHTML(chUnknown));
print(changesCardHTML(chUnknown));
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

section('The folded cat (cat.js)');
const catCounts = (needs, working, idle) => ({ needs, working, idle });
show('nothing running', catPose(catCounts(0, 0, 3)));
show('no sessions at all', catPose(catCounts(0, 0, 0)));
show('two working', catPose(catCounts(0, 2, 1)));
show('one needs your input while two work', catPose(catCounts(1, 2, 1)));
const inSections = (...sections) => sections.map((section) => ({ section }));
show('its labels: two waiting by name beside it, the other five as dots in a row under them',
     catLabels(inSections('turn', 'turn', 'busy', 'busy', 'seen', 'idle', 'idle')));
show('…nothing waiting: the dots alone, level with the cat', catLabels(inSections('busy', 'idle', 'idle')));
show('…seven waiting: five by name, the other two first among the dots',
     catLabels(inSections('turn', 'turn', 'turn', 'turn', 'turn', 'turn', 'turn', 'busy')));
show('…twenty: the dots go on in a second row after twelve',
     catLabels(inSections('turn', ...Array(19).fill('idle'))));
show('a tag\'s place, from the corner of the cat\'s square: on its left, and on its right on the screen\'s left half',
     [false, true].map((right) => catLabelStyle(CAT_TAG_END, CAT_TAG_STEP, CAT_TAG_TALL, right)));
show('…and a dot\'s', [false, true].map((right) => catLabelStyle(CAT_DOT_FIRST - CAT_DOT_WIDE / 2, CAT_DOTS_BELOW,
                                                                  CAT_DOT_TALL, right)));
show('its eyes, toward a pointer up and to its right while it looks at you', catGaze(30, -30, 0));
show('…toward one below it while it watches', catGaze(0, 40, 50));
show('…and only a little toward one on its face, close to its eyes', catGaze(4, 6, 0));
const eyesAfter = (frames, rate = 60) => {
  let eyes = { x: -CAT_GLANCE, y: 0, vx: 0, vy: 0 };
  for (let i = 0; i < frames; i++) eyes = catSpring(eyes, { x: CAT_GLANCE, y: 0 }, 1 / rate);
  return Math.round(eyes.x * 10) / 10;
};
show('…after a quick sweep from its left to its right, catching up over a moment, never past it: where its eyes are '
     + 'after 2, 5, 10, 15 and 30 frames at 60 a second', [2, 5, 10, 15, 30].map((n) => eyesAfter(n)));
show('…and at 30 frames a second, each frame further on than the last, without shaking',
     [1, 2, 3, 4, 5, 6, 8].map((n) => eyesAfter(n, 30)));

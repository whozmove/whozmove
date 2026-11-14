// The panel page's logic, run outside the app by tests/panel.sh: which section each sample session goes in, how rows
// sort, and the HTML of sample rows. Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

// Every row in the list is shown briefly; a chat beside the folded panel is the row whole. Most cases below check the
// parts a whole row has (Claude's line, the work line, the bottom line), so they draw rows whole, as that chat does;
// a case about the list's own rows draws them short (drawWhole false, then back).
let drawWhole = true;
core.rowLooks.unshift((row) => { if (drawWhole) row.brief = false; });

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
const agentJob = { what: 'Review the native side', startedAt: min(5), holds: true, step: 'Reading Storage.m' };
const shellJob = { what: 'Start the dev server', command: 'npm run dev', startedAt: min(5), holds: false };
show('replied, with an agent of its own still at work in the background: not your move yet',
  classify(session({ ...reply, background: [agentJob] }), NOW, unread));
show('…a request for your OK among it: that waits on you',
  classify(session({ ...reply, background: [agentJob], ask: { id: 'b', tool: 'Bash', input: {} } }), NOW, unread));
show('…its next turn under way: working', classify(session({ status: 'busy', background: [agentJob] }), NOW, unread));
show('replied, with only a shell command left running (a dev server): your move as before',
  classify(session({ ...reply, background: [shellJob] }), NOW, unread));
show('how many jobs run in the background, of every kind, and how many of them hold its work',
  [[], [shellJob], [agentJob, shellJob], [agentJob, { ...agentJob, what: 'Write the docs' }, shellJob, shellJob,
                                          shellJob]].map(
    (background) => [backgroundRunning(session({ background })), backgroundAtWork(session({ background }))]));
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
show('replied 2 days ago, not opened: still waiting for you', classify(session(repliedAt(min(48 * 60))), NOW, unread));
show('replied a day ago, opened then',
  classify(session({ ...repliedAt(min(24 * 60 + 1)), sessionId: 'r2' }), NOW, readHere('r2', min(24 * 60 + 1))));
show('replied 2 days ago, opened a minute ago: a day from when you were last on it',
  classify(session({ ...repliedAt(min(48 * 60)), sessionId: 'r2' }), NOW, readHere('r2')));
show('replied a day ago, and you wrote to it 30 min ago',
  classify(session({ ...repliedAt(min(24 * 60 + 1)), lastPromptAt: min(30) }), NOW, unread));
show('a turn you stopped long after its reply, its transcript moving until 5 min ago',
  classify(session({ ...repliedAt(min(75)), lastPromptAt: min(70), messageAt: min(5) }), NOW, unread));
show('never replied', classify(session({}), NOW, unread));
show('a closed conversation that replied 5 min ago, not opened',
  classify(session({ ...reply, status: 'closed', entrypoint: 'claude-desktop', pid: 0 }), NOW, unread));
show('a terminal session that has ended, its reply 5 min ago not read', classify(session({ ...reply,
  status: 'closed', pid: 0, opensIn: 'Ghostty' }), NOW, unread));
show('…its reply 2 days ago read then', classify(session({ ...repliedAt(min(48 * 60)), sessionId: 'k1',
  status: 'closed', pid: 0, opensIn: 'Ghostty' }), NOW, readHere('k1', min(48 * 60 - 1))));
show('replied 3 days ago, before the page first kept the replies you had not read, not opened',
  classify(session(repliedAt(min(72 * 60))), NOW, { seen: {}, readBefore: min(48 * 60) }));
show('your turn since, a request', turnSince(session({ ask: { id: 'a', tool: 'Bash', input: {}, at: min(3) } }),
                                             'needs') === min(3));
show('…Claude waiting on you, from when its status changed',
  turnSince(session({ status: 'waiting', statusUpdatedAt: min(4) }), 'needs') === min(4));
show('…a reply', turnSince(session(reply), 'turn') === min(5));

section('Where each row goes');
// The rows in the order they're shown, newest message first: each row's id and what it is.
const where = (placed) => placed.map((p) => `${p.s.sessionId}(${p.kind})`).join(' ');
// One update after another, each placed as render places it at the app's time `now`: the rows you've pressed (`held`)
// where they were last shown, with when you were last on each session as `view` says.
const placedAt = {};
const placeAll = (sessions, held = [], now = NOW, view = unread) => {
  const placed = placeRows(sessions.map((s) => ({ s, kind: classify(s, now, view) })), placedAt,
                           (sid) => held.includes(sid));
  for (const { s, latest, quiet } of placed) placedAt[s.sessionId] = { latest, quiet };
  return where(placed);
};
const asked = (id, at) => ({ ask: { id, tool: 'Bash', input: {}, at } });
const lineup = [
  session({ sessionId: 'r1', ...repliedAt(min(5)) }),
  session({ sessionId: 'q2', status: 'waiting', statusUpdatedAt: min(3) }),
  session({ sessionId: 'w1', status: 'busy', lastPromptAt: min(20) }),
  session({ sessionId: 's1', ...repliedAt(min(30), { lastFocusedAt: min(29) }) }),
  session({ sessionId: 'q1', ...repliedAt(min(40)), ...asked('q1', min(8)) }),
  session({ sessionId: 'i1', ...repliedAt(min(90), { lastFocusedAt: min(89) }) }),
  session({ sessionId: 'r2', ...repliedAt(min(12)) }),
  session({ sessionId: 'w2', status: 'busy', lastPromptAt: min(2) }),
  session({ sessionId: 's2', ...repliedAt(min(14), { lastFocusedAt: min(13) }) }),
  session({ sessionId: 'i2' }),
];
show('one list, newest message first, whatever each is: a request by when it came, a working one by your message',
  placeAll(lineup));
const q3 = session({ sessionId: 'q3', ...repliedAt(min(50)), ...asked('q3', NOW - 500) });
show('a request that comes goes to the top', placeAll([...lineup, q3], [], NOW + 1000));
const i1Replied = session({ sessionId: 'i1', ...repliedAt(NOW + 1500, { lastFocusedAt: min(89) }) });
const withI1 = (s) => [...lineup.filter((x) => x.sessionId !== 'i1'), q3, s];
show('…and so does a reply, an idle one\'s too', placeAll(withI1(i1Replied), [], NOW + 2000));
const w1Steps = session({ sessionId: 'w1', status: 'busy', lastPromptAt: min(20), activityAt: NOW + 2500,
                          messageAt: NOW + 2500 });
show("a working one's steps don't move it",
  placeAll([...withI1(i1Replied).filter((x) => x.sessionId !== 'w1'), w1Steps], [], NOW + 3000));
const others = withI1(i1Replied).filter((s) => s.sessionId !== 's1');
const s1 = (fields) => session({ sessionId: 's1', ...repliedAt(min(30), { lastFocusedAt: min(29) }), ...fields });
show('a row you pressed, to write to it: it stays where it was as it starts work',
  placeAll([...others, s1({ status: 'busy', lastPromptAt: NOW + 3500 })], ['s1'], NOW + 4000));
show('…and as it replies',
  placeAll([...others, s1({ ...repliedAt(NOW + 4500), lastPromptAt: NOW + 3500 })], ['s1'], NOW + 5000));
show("…once you've moved on from the panel, it goes to the top",
  placeAll([...others, s1({ ...repliedAt(NOW + 4500), lastPromptAt: NOW + 3500 })], [], NOW + 6000));
show("a row you pressed that wasn't shown yet goes where it belongs",
  placeAll([...others, session({ sessionId: 'n1', status: 'busy', lastPromptAt: min(1) })], ['n1'], NOW + 7000));
show('a read reply above an unread one', placeAll([
  session({ sessionId: 'u1', ...repliedAt(min(50)) }),
  session({ sessionId: 'd1', ...repliedAt(min(40), { lastFocusedAt: min(39) }) }),
], [], NOW));
show('…a day on, idle: it goes below it', placeAll([
  session({ sessionId: 'u1', ...repliedAt(min(50)) }),
  session({ sessionId: 'd1', ...repliedAt(min(40), { lastFocusedAt: min(39) }) }),
], [], NOW + 24 * 60 * 60000));
show('your message from Claude or a terminal takes its row to the top too', placeAll([
  session({ sessionId: 'm1', ...repliedAt(min(5)) }),
  session({ sessionId: 'm2', ...repliedAt(min(30), { lastFocusedAt: min(29) }), status: 'busy',
            lastPromptAt: NOW + 7500 }),
], [], NOW + 8000));
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
show("the list scrolls to show the row of the session you're on: one you switched to in Claude Desktop; one you "
     + 'pressed here; going back for a moment, under that press, to the one its app still says; one you pressed in the '
     + 'reader with none of its row in view, and with some of it in view; the same one as before; none',
     [revealsOpen('b', 'a', new Set(), false), revealsOpen('b', 'a', new Set(['b']), true),
      revealsOpen('a', 'b', new Set(['b']), true), revealsOpen('b', 'a', new Set(['b']), false),
      revealsOpen('b', 'a', new Set(['b']), true), revealsOpen('a', 'a', new Set(), false),
      revealsOpen(null, 'a', new Set(), false)]);

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
markOn('tb', [tabs[0], asSent({ ...tabs[1], seenAt: min(5) })], min(5));
keepSeen(state.last.sessions, min(5));
show('…the app saw you looking at it after it replied: read', kindOn('tb'));
markOn('tb', tabs, min(4));
show('…and still read once the app has restarted, as the page keeps it', kindOn('tb'));
markOn('tb', [tabs[0], session({ sessionId: 'tb', ...repliedAt(min(3)), seenAt: min(4) })], min(3));
show('…a reply that came after you last looked is not read', kindOn('tb'));
markOn('tb', [tabs[0], asSent({ ...tabs[1], seenAt: min(1) })], min(1));
keepSeen(state.last.sessions, min(1));
show('what the page keeps follows you while you stay on it', state.seen.tb === min(1));
markOn('ta', tabs, NOW);
markOn('tb', [tabs[0], asSent({ ...tabs[1], seenAt: NOW + 12 * 60000 })], NOW + 12 * 60000);
keepSeen(state.last.sessions, NOW + 12 * 60000);
show('…and once you have moved on, being on it again leaves it as it was', state.seen.tb === min(1));
markOn('tb', [tabs[0], session({ sessionId: 'tb', ...repliedAt(NOW + 13 * 60000), seenAt: NOW + 14 * 60000 })],
       NOW + 14 * 60000);
keepSeen(state.last.sessions, NOW + 14 * 60000);
show('…until something new comes: a reply it sends while you are on it is read', kindOn('tb'));
state.opening = { sessionId: 'ta', at: Date.now() };
markOn('tb', tabs, min(2));
show('a conversation just opened in Claude is the one you are on at once, before Claude says so', state.current);
state.opening = null;
state.last = lastBefore;
state.seen = {};
state.claudeShowed = null;
goTo(null);

section('The list');
drawWhole = false;
// What the list shows, in order: each project by its folder (› when it's folded), where a project's rows are (folded
// away or not) and the copies pinned below a folded one, and each row's id with its classes.
function outline(html) {
  const parts = new RegExp([/<div class="project( collapsed)?" data-key="([^"]*)"/,
                             /<div class="(prows(?: closed)?|pinned)">/, /<div class="row ([^"]*)" data-id="([^"]*)"/]
    .map((part) => part.source).join('|'), 'g');
  return [...html.matchAll(parts)].map(([, projectFolded, project, body, cls, id]) =>
    project ? `[${project}${projectFolded ? ' ›' : ''}]`
      : body ? `(${body === 'pinned' ? 'pinned' : body === 'prows' ? 'rows' : 'folded'})`
      : `${id}.${cls.trim().split(' ').join('.')}`).join(' ');
}
// The list as drawn: its groups (listGroups), each project with its rows.
const projectsOf = (placed, now) => groupsHTML(listGroups(placed), now);
// The rows placed once, those in `held` where it says they were last shown.
const placeOnce = (sessions, held = {}) =>
  placeRows(sessions.map((s) => ({ s, kind: classify(s, NOW, unread) })), held, (sid) => sid in held);
show('the rows as placed: newest message first, the idle ones last',
     placeOnce(lineup).map((p) => `${p.s.sessionId}.${p.kind}`).join(' '));
show('…each under its project, in that order', outline(groupsHTML(listGroups(placeOnce(lineup)), NOW)));
const inRepo = (sessionId, root, fields) => session({ sessionId, cwd: root, git: { branch: 'main', root }, ...fields });
state.closedProjects['/work/other'] = true;
{
  const folded = projectsOf(placeOnce([
    inRepo('g1', '/work/app', reply),
    inRepo('g3', '/work/other', repliedAt(min(30))),
    inRepo('g4', '/work/other', {}),
  ]), NOW);
  show('a folded project hides all its rows, a reply waiting in it too: nothing below it', outline(folded));
  show('…its header says how many wait on you', folded.match(/<span class="pneeds[^"]*">([^<]*)</)?.[1]);
  show('…and VoiceOver says it as for any group, its folder kept as the tip',
       [...folded.matchAll(/<div class="project[^"]*" data-key="[^"]*" title="([^"]*)" aria-label="([^"]*)"/g)]
         .map(([, tip, said]) => `${said} | ${tip}`));
}
{
  // A conversation you've just started opens its folded project, once: folded again, it stays folded.
  const groupsWith = (pending) => [{ key: '/work/other', rows: [{ s: { sessionId: 'st1', pending } }] }];
  openForStarts(groupsWith(true));
  const opened = !state.closedProjects['/work/other'];
  state.closedProjects['/work/other'] = true;
  openForStarts(groupsWith(true));
  show('a start in a folded project opens it; folded again while it starts, it stays folded',
       [opened, !!state.closedProjects['/work/other']]);
}
delete state.closedProjects['/work/other'];
const one = inRepo('a1', '/work/one', repliedAt(min(20), { lastFocusedAt: min(19) }));
const two = inRepo('b1', '/work/two', repliedAt(min(2)));
show('projects A to Z, whichever had the newest message', outline(projectsOf(placeOnce([two, one]), NOW)));
show('…by name whatever its case, numbers in number order', outline(projectsOf(placeOnce([
  inRepo('c1', '/work/Zebra', {}), inRepo('c2', '/work/app10', {}), inRepo('c3', '/work/app9', {}),
  inRepo('c4', '/work/beta', {})]), NOW)));
const rest = [inRepo('a2', '/work/one', repliedAt(min(10))), two];
const a1Was = Object.fromEntries(placeOnce([one, ...rest]).map(({ s, latest, quiet }) => [s.sessionId, { latest, quiet }]));
const a1AtWork = inRepo('a1', '/work/one', { ...repliedAt(min(20), { lastFocusedAt: min(19) }), status: 'busy',
                                              lastPromptAt: NOW - 1000 });
show('inside a project, newest message first', outline(projectsOf(placeOnce([one, ...rest]), NOW)));
show('…a row you pressed stays where it was there as it starts work',
  outline(projectsOf(placeOnce([a1AtWork, ...rest], { a1: a1Was.a1 }), NOW)));
show("…until you've moved on: then it goes to its project's top, and the projects stay as they are",
  outline(projectsOf(placeOnce([a1AtWork, ...rest]), NOW)));

drawWhole = true;

section('What cross-fades on a row (core.swaps)');
// A bit that cross-fades as it changes is told by its text and what it says to VoiceOver, so a track, which says
// where it stands only in words for VoiceOver, cross-fades as its job moves on.
const bitSaying = (text, label) => ({ textContent: text, getAttribute: (k) => (k === 'aria-label' ? label : null) });
show('a track from step 2 to step 3 of 6: changed, so it cross-fades',
     swapText(bitSaying('', 'Step 2 of 6, Build')) !== swapText(bitSaying('', 'Step 3 of 6, Review')));
show('…the same step drawn again: unchanged', swapText(bitSaying('', 'Step 2 of 6')) === swapText(bitSaying('', 'Step 2 of 6')));
show('…a bit of words alone, changed or not', [swapText(bitSaying('Opus', null)) !== swapText(bitSaying('Sonnet', null)),
  swapText(bitSaying('Opus', null)) === swapText(bitSaying('Opus', null))]);

section('Your message and Claude\'s line, written in and erased');
show('what the next text keeps of the one before, by whole words: the same verb, nothing, all of it, a word that goes '
     + 'on, a shared start within a word', [sharedStart('Reading checkout.tsx', 'Reading cart.tsx'),
       sharedStart('Thinking', 'Reading app.ts'), sharedStart('Editing a.ts', 'Editing a.ts'),
       sharedStart('Reading', 'Reading cart.tsx'), sharedStart('Run tests', 'Running npm test')]);
// When a change ends, from the start of the rebuild's motion, for lengths along the text (points) as the panel has them:
// "Thinking" about 70, a step about 110, a full line about 280, a reply on two lines about 560.
const chatEnds = (...args) => Math.round(Object.values(chatTimes(...args)).reduce((sum, ms) => sum + ms, 0));
show(`how long each change takes, all within the rebuild's motion (${MORPH_MS} ms): a turn starting, Claude's line `
     + 'after yours; the next step, its verb kept; a step to a two-line reply; a new turn after one; a long reply after '
     + 'a long one, after yours', [chatEnds(CHAT_STAGGER + CHAT_LEAD, 0, 70, false), chatEnds(0, 60, 40, true),
       chatEnds(0, 110, 560, false), chatEnds(CHAT_STAGGER, 560, 70, false), chatEnds(CHAT_STAGGER, 560, 560, false)]);
show('…erasing a little quicker than writing the same text', [chatTimes(0, 280, 0, false).erase,
                                                             chatTimes(0, 0, 280, false).write]);
// Where a rewrite has got to, along the way (points), for a chat line or any other line of text taking new words.
const rewriteSays = (t, from, to, tm) => {
  const at = rewriteAt(t, from, to, tm);
  return `${at.erasing ? 'erasing' : 'writing'} ${Math.round(at.pos)}`;
};
const kept = { from: { length: 110, keepPos: 60 }, to: { length: 100, keepPos: 60 } };
const keptTimes = chatTimes(0, 50, 40, true), keptSwap = keptTimes.erase + keptTimes.gap;
show('a rewrite keeping a verb (60 points of 110, then 100): the old erasing down to the verb, the new writing on from '
     + 'it with no pause between, at its start, halfway through erasing, as it turns to writing, halfway through, and '
     + 'at its end', [0, keptTimes.erase / 2, keptSwap, keptSwap + keptTimes.write / 2, keptSwap + keptTimes.write]
  .map((ms) => rewriteSays(ms, kept.from, kept.to, keptTimes)));
const apart = { from: { length: 110, keepPos: 0 }, to: { length: 70, keepPos: 0 } };
const apartTimes = chatTimes(0, 110, 70, false), apartSwap = apartTimes.erase + apartTimes.gap;
show('…sharing nothing: all of the old erased, a moment with nothing there, then the new written from the start',
     [apartTimes.erase, apartTimes.erase + apartTimes.gap / 2, apartSwap, apartSwap + apartTimes.write]
       .map((ms) => rewriteSays(ms, apart.from, apart.to, apartTimes)));
const frames = listFrames(200, 185, [{ delta: -15, start: 400, ms: 600 }]);
show('the list\'s height while a line gives up its room only once its text has gone (15 points, from 400 ms): where it '
     + 'starts, at 400 ms, and where it ends', [frames[0].height, frames[12].height, frames[30].height]);
// How much taller than where it ends a box still gets on the rest of its way (overshootAhead), as morphOvershoot reads
// it from the box's easing: what it has passed no longer counts.
const ahead = (list) => {
  const keys = list.map((k) => ({ offset: k.offset, height: parseFloat(k.height) }));
  return (ms) => {
    const done = ms / MORPH_MS, i = Math.floor(done * (keys.length - 1));
    return Math.round(overshootAhead(keys, done, keys[i].height) * 10) / 10;
  };
};
const shrinking = ahead(listFrames(140, 100, []));
show('a row shrinking 40 points: taller only by what it has still to lose, within a point of its end by 640 ms of '
     + 'its 1000, and none at its end', [0, 200, 400, 640, 1000].map(shrinking));
const past = ahead(listFrames(100, 100, [{ delta: -20, start: 400, ms: 600 }]));
show('one whose lines grow at once while another folds late, ending as tall as it began: taller by the most it gets '
     + 'still to come, from the start, past its tallest, and at its end', [0, 400, 800, 1000].map(past));

section("The row you're on, held at the edge");
show('in view', stickyEdge(10, 150, 500));
show('just past the top: under the header', stickyEdge(-1, 150, 500));
show('just past the bottom: above the bottom edge', stickyEdge(360, 150, 500));
show('wholly above, and wholly below', [stickyEdge(-400, 150, 500), stickyEdge(900, 150, 500)]);
show('right at either edge: still in view', [stickyEdge(0, 150, 500), stickyEdge(350, 150, 500)]);
// A row of six lines with its padding (9 and 9): its title, your message, Claude's line, the work line, a step's note
// and the bottom line. The title, Claude's line and the bottom line stay.
const rowLines = [['title', 17, true], ['you', 18, false], ['claude', 18, true], ['work', 24, false],
                  ['note', 18, false], ['where', 21, true]]
  .map(([name, extent, keep]) => ({ name, extent, keep }));
const rowFull = 18 + rowLines.reduce((sum, l) => sum + l.extent, 0);
// The copy `past` points past the edge: its height, what has folded off which line, and how attached it is.
const foldAt = (past, edge) => {
  const f = stickyFold(rowLines, rowFull, rowFull - past, edge);
  const folded = rowLines.map((l, i) => (f.folds[i] ? `${l.name} −${f.folds[i]}` : '')).filter(Boolean);
  return `${f.height} tall | ${folded.join(', ') || 'nothing folded'} | attached ${+f.attach.toFixed(2)}`;
};
for (const past of [0, 12, 30, 52, 60, 74, 130]) show(`at the top edge, ${past} points past it`, foldAt(past, 'top'));
for (const past of [12, 30, 52, 60, 74]) show(`at the bottom edge, ${past} points past it`, foldAt(past, 'bottom'));
show('as tall as what of its place is in view, so the row next to it stays touching it',
  [0, 12, 30, 52, 60].every((past) => stickyFold(rowLines, rowFull, rowFull - past, 'top').height === rowFull - past));
show('…what has gone all folded off the lines that go',
  [12, 30, 52, 60].every((past) => stickyFold(rowLines, rowFull, rowFull - past, 'bottom').folds
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
// The copy catching up with the row's place, a frame (16.7 ms) at a time, as the place's top goes from one point to
// the next: where the copy's top is in each frame.
const easeAlong = (places) => {
  let at = places[0], speed = 0;
  return places.slice(1).map((to, i) => {
    ({ at, speed } = stickyEase(at, speed, places[i], to, 16.7));
    return +at.toFixed(1);
  }).join(' ');
};
const still = (place, frames) => Array(frames).fill(place);
show('a slow scroll, 3 points a frame: it keeps up exactly', easeAlong([0, -3, -6, -9, -12, -15]));
show('the row taken 150 points past the edge in one frame: its lines fold one after another, there in about 0.25 s',
  easeAlong([0, ...still(-150, 17)]));
show('a quick scroll, 30 points a frame, then still: it catches up once the scroll stops',
  easeAlong([0, -30, -60, -90, -120, ...still(-120, 14)]));
show('…and brought back before it has caught up: it turns, and never goes past the row\'s place',
  easeAlong([0, -60, -120, -60, 0, 40, ...still(40, 14)]));
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
show('back in view, its copy caught up with its place: hands back, however far it came in one frame',
  [0.5, 30, 120].map((t) => holdAt(t, { was: 'top' })).join(' '));
show('…and from the bottom edge', [349.6, 200].map((t) => holdAt(t, { was: 'bottom' })).join(' '));
show('…its copy still on its way there: holds on, gliding there, until it has caught up',
  [30, 200].map((t) => holdAt(t, { was: 'top', behind: true })).join(' '));
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
// How far the list scrolls on by itself as your scroll ends, the row you're on 150 tall in a visible part 500 tall,
// with room to scroll 300 each way, your scroll going on down the list (1) or back up (-1).
show('the row left 35 short of the top, coming to it: the list scrolls on 35',
  stickySnapBy(35, 150, 500, 300, 300, 1));
show('…60 short: nothing', stickySnapBy(60, 150, 500, 300, 300, 1));
show('…scrolled back away from it: nothing', stickySnapBy(35, 150, 500, 300, 300, -1));
show('…its foot 35 short of the bottom, coming to it: the list scrolls back 35',
  stickySnapBy(315, 150, 500, 300, 300, -1));
show('…scrolled away from it: nothing', stickySnapBy(315, 150, 500, 300, 300, 1));
show('…on the edge already: nothing',
  [stickySnapBy(0, 150, 500, 300, 300, 1), stickySnapBy(350, 150, 500, 300, 300, -1)]);
show('…where the list can\'t scroll that far: nothing', [stickySnapBy(35, 150, 500, 300, 20, 1),
  stickySnapBy(315, 150, 500, 20, 300, -1)]);
show('…taller than the list: nothing', stickySnapBy(30, 520, 500, 300, 300, 1));
// How far the list moves as a box opens to type in, the list's visible part from 77 to 560 and the box's card at 382:
// already in view, nothing; opened past the foot, the least that shows it, at that edge; the card's top kept in view.
show('a box opened in view: nothing', leastToShow(500, 530, 382, 77, 560));
show('…opened past the list\'s foot, 2 pt above it: the least that shows it', leastToShow(563, 591, 382, 77, 560));
show('…so far past it that showing it whole would take its card\'s top out of view: only as far as the card\'s top',
  leastToShow(700, 740, 120, 77, 560));
show('…past the top: the least that shows it, back up', leastToShow(60, 90, 40, 77, 560));
show('a row\'s details opened at the list\'s foot (480 to 576, the row\'s own foot at 584): down to the row\'s foot, its '
     + 'room under them kept, not only to the details\' own', [leastToShow(480, 584, 382, 77, 560),
                                                                leastToShow(480, 576, 382, 77, 560)]);
// Back in view, what came on the row while it was away counts as only just shown.
state.shownAt = { 'compact:s': NOW - 5000, 'steps:other': NOW - 5000, ask1: NOW - 5000 };
const realNow = Date.now;
Date.now = () => NOW;
showAgain(session({ sessionId: 's', ask: { id: 'ask1' } }));
Date.now = realNow;
show('the row back in view: its cards and its request count as just shown, another row\'s don\'t',
  Object.entries(state.shownAt).map(([key, at]) => `${key} ${at === NOW ? 'now' : 'before'}`).join(', '));
state.shownAt = {};

section('The line under the heads');
// Which of the things that stay put over what scrolls has the thin line under it (top first, those showing), by how far
// the view under them is scrolled: the lowest, only while something scrolls under it.
const headLine = (fixed, scrolled) => lineUnder(fixed, scrolled) || 'none';
show('the list at its top, under the header: none', headLine(['header'], 0));
show('…scrolled: under the header', headLine(['header'], 40));
show('…a part of a point down, as the list settles: still none', headLine(['header'], 0.4));
show('the setup line and notifications\' line under the header, scrolled: under the lowest, notifications\'',
     headLine(['header', 'install', 'notices'], 40));
show('…at its top: none', headLine(['header', 'install', 'notices'], 0));
show('a new conversation\'s card under the header, scrolled: under the card', headLine(['header', 'dock'], 12));
show('the folded panel\'s head in the header\'s place, its list scrolled: under it', headLine(['peekHead'], 30));
show('the panel\'s back, its page scrolled: under its head; at its top: none',
     [headLine(['back head'], 80), headLine(['back head'], 0)]);
show('the reader, its body scrolled: under its head; at its top: none',
     [headLine(['reader head'], 120), headLine(['reader head'], 0)]);
show('One Task\'s strip under the reader\'s head, the task scrolled: under the strip, not the head',
     headLine(['reader head', 'ot-strip'], 120));
show('nothing that stays put: none', headLine([], 50));

section('Requests waiting on you');
// Each { id, fresh, inView, edge, gone, y }, the one waiting longest first; what's brought into view, what the strip at
// each of the list's edges names, and what counts as seen. Past an edge, a row is wholly out of sight unless said.
const ask = (id, fresh, edge = null, y = 0, gone = edge) => ({ id, fresh, inView: !edge, edge, gone, y });
const stripsSaid = (s) => ['top', 'bottom'].filter((e) => s[e]).map((e) => `${s[e].id} at the ${e}${s[e].more ? ` +${s[e].more}` : ''}`)
  .join(' and ') || '-';
const next = (waiting, how) => {
  const n = waitingNext(waiting, { busy: false, pointer: false, answered: false, ...how });
  return `bring ${n.bring?.id || '-'}, strip ${stripsSaid(n.strips)}, seen [${n.seen.join(' ')}]`;
};
show('a new one out of view, nothing else going on: brought into view', next([ask('a', true, 'top')]));
show('…already in view: only seen', next([ask('a', true)]));
show('two new at once: the newer is brought, the older counts as seen', next([ask('a', true, 'bottom'), ask('b', true, 'top')]));
show('a new one while you answer another: the strip, after this', next([ask('a', true, 'top')], { busy: true }));
show('…with the pointer on the panel instead: the strip too', next([ask('a', true, 'top')], { pointer: true }));
show('…one seen before, out of view, pointer on the panel: not brought, but the strip names it', next([ask('a', false, 'top')], { pointer: true }));
show('…while you answer: a strip at each edge with one past it',
  next([ask('a', false, 'bottom'), ask('b', true, 'top'), ask('c', true)], { busy: true }));
show('you answered one: the one waiting longest out of view is brought, pointer or not',
  next([ask('a', false, 'bottom'), ask('b', true, 'top')], { answered: true, pointer: true }));
show('…nothing out of view: nothing moves', next([ask('a', false)], { answered: true }));
show('…answered, then straight on to another card: nothing moves', next([ask('a', false, 'top')],
  { answered: true, busy: true }));
show('one being brought into view isn\'t named in the strip on its way',
  next([ask('a', true, 'top')], { pointer: true, bringing: 'a' }));
show('…stopped by your scrolling before it showed: still named', next([ask('a', true, 'top')], { pointer: true }));
show('…three new at once: the newest is brought, the others count as seen, and the strip names them',
  next([ask('a', true, 'top'), ask('b', true, 'bottom'), ask('c', true, 'top')]));

// Looks in a row, as the list is drawn: what each brings or names, and whether an answer is still to be gone on from.
const looks = (steps) => {
  const ws = { answerAt: 0, answered: false, bringing: null };
  return steps.map(([waiting, how]) => {
    const n = waitingLook(ws, waiting, { lastAnswer: 0, card: false, keys: false, settled: true, pointer: true, ...how });
    return `bring ${n.bring?.id || '-'}, strip ${stripsSaid(n.strips)}${ws.answered ? ', answer kept' : ''}`;
  }).join(' → ');
};
show('a second asks while you answer the first, then you answer with the panel still holding the keys: it\'s brought',
  looks([[[ask('b', true, 'top')], { card: true, keys: true }],
         [[ask('b', false, 'top')], { lastAnswer: 5, keys: true }]]));
show('…a draw while the answered card is still going: the answer is kept, and the next look brings it',
  looks([[[ask('b', true, 'top')], { card: true }],
         [[ask('b', false)], { lastAnswer: 5, settled: false }],
         [[ask('b', false, 'top')], { lastAnswer: 5 }]]));
show('…the answer looked at once only: a look after that doesn\'t bring it again',
  looks([[[ask('b', false, 'top')], { lastAnswer: 5 }], [[ask('b', false, 'top')], { lastAnswer: 5 }]]));
show('…straight on to another card before the rows stop: nothing moves, and the strip names it',
  looks([[[ask('b', false, 'top')], { lastAnswer: 5, settled: false, card: true }],
         [[ask('b', false, 'top')], { lastAnswer: 5, card: true }]]));
show('one brought into view, then scrolled away from by hand, the pointer off the panel: never brought again, the strip held at its edge',
  looks([[[ask('a', true, 'bottom')], { pointer: false }], [[ask('a', false, 'bottom')], { pointer: false }],
         [[ask('a', false, 'top')], { pointer: false }]]));
show('…back in view: the strip goes', next([ask('a', false)]));
show('two seen before, one below and one above: a strip at each edge, top and bottom at once',
  next([ask('a', false, 'bottom'), ask('b', false, 'top')], { pointer: true }));
show('two above: the top strip names the one nearest the edge, the lower of them, with how many more',
  next([ask('a', false, 'top', 10), ask('b', false, 'top', 50)], { pointer: true }));
show('two below: the bottom strip names the one nearest the edge, the higher of them',
  next([ask('a', false, 'bottom', 500), ask('b', false, 'bottom', 400)], { pointer: true }));
show('one partly in view past the bottom: no strip, so it never shows twice',
  next([ask('a', false, 'bottom', 400, null)], { pointer: true }));
show('…brought into view all the same, after an answer, as it doesn\'t show whole',
  next([ask('a', false, 'bottom', 400, null)], { answered: true }));
show('two below, the nearer still partly in view: the strip names the one wholly out of sight, and no more',
  next([ask('a', false, 'bottom', 400, null), ask('b', false, 'bottom', 500)], { pointer: true }));
show('typing in a box elsewhere, no answer given: nothing moves', looks([[[ask('b', true, 'top')], { keys: true, pointer: false }]]));

section('Sorting');
const since = (t) => `now-${Math.round((NOW - t) / 60000)}m`;
show('working, your message newer than its reply',
  since(movedAt(session({ lastPromptAt: min(3), lastReplyAt: min(9), statusUpdatedAt: min(1) }), 'busy')));
show('working, no message of yours since its reply: by its reply',
  since(movedAt(session({ lastPromptAt: min(9), lastReplyAt: min(8), statusUpdatedAt: min(2) }), 'busy')));
show('idle, by its newest message',
  since(movedAt(session({ lastPromptAt: min(30), lastReplyAt: min(20), messageAt: min(15) }), 'idle')));
show('compacting, with no message of yours since its reply: by its reply, not when it started',
  since(movedAt(session({ lastPromptAt: min(30), lastReplyAt: min(20), statusUpdatedAt: min(1) }), 'busy')));
show('…with no messages recorded at all: by when it started working',
  since(movedAt(session({ statusUpdatedAt: min(1) }), 'busy')));
show('a request, by when it came, though its reply was long before',
  since(movedAt(session({ lastReplyAt: min(40), ask: { id: 'a', tool: 'Bash', input: {}, at: min(4) } }), 'needs')));

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
show('context window, as the app gives it', contextWindow({ model: 'claude-opus-5-5', tokens: 1000, window: 1000000 }));
show('context window, none given', contextWindow({ model: 'claude-opus-5-5', tokens: 1000 }));
show('auto-compact at, 1M window', compactLimit({ model: 'claude-opus-5-5', tokens: 1000, window: 1000000 }));
show('auto-compact at, your own setting',
  compactLimit({ model: 'claude-sonnet-5-5', tokens: 1000, window: 200000, compactWindow: 150000 }));
show('auto-compact at, 200k window', compactLimit({ model: 'claude-sonnet-5-5', tokens: 1000, window: 200000 }));
for (const n of [427000, 1000000, 1500000]) show(`tokens ${n}`, kTokens(n));
for (const s of [5, 45, 300, 3 * 3600, 2 * 86400]) show(`ago ${s}s`, ago(s * 1000));
for (const s of [12, 76, 3780]) show(`elapsed ${s}s`, elapsed(s * 1000));
const ringColour = (agent) => (/color:([^;]+);/.exec(contextRing(session({ agent })) || '') || [])[1];
show('ring colour, 10% used', ringColour({ model: 'claude-opus-5-5', tokens: 100000, window: 1000000 }));
show('ring colour, 70% used', ringColour({ model: 'claude-sonnet-5-5', tokens: 140000, window: 200000 }));
show('ring colour, 90% used', ringColour({ model: 'claude-sonnet-5-5', tokens: 180000, window: 200000 }));
const opus = (tokens) => ({ model: 'claude-opus-5-5', tokens, window: 1000000 });
state.last.now = NOW;
// Whether now is a good time to compact is the app's (CompactTime, --print-compact-time in tests/rows.sh): the ring
// goes by the row's compactTime.
const full = { why: "it's nearly full, and would soon compact by itself", kind: 'full' };
const nowRing = contextRing(session({ ...reply, sessionId: 'n1', agent: opus(980000), compactTime: full }));
show('a ring that says compact now', /class="ctx open now"/.test(nowRing) && /% · Compact now</.test(nowRing));
show('…and why, in its tip', /title="([^"·]*)/.exec(nowRing)?.[1]);
show("a ring with no compactTime doesn't, however full",
  /Compact now/.test(contextRing(session({ ...reply, sessionId: 'n2', agent: opus(980000) }))));
const cantRing = contextRing(session({ ...reply, sessionId: 'n3', agent: opus(450000), compactTime: full,
  compactNote: { text: "Compact at Breaks can't: Its window has other tabs, which the terminal could type into" } }));
show("…and a module's note on why a compaction can't go in, in its tip", /title="[^"]*· (Compact at Breaks[^"]*)"/
  .exec(cantRing)?.[1]);
calm.matches = false;  // the settling is motion, which the stand-in otherwise turns off
const ringOf = (fields) => contextRing(session({ ...reply, sessionId: 'k1', agent: opus(640000), ...fields }));
state.hoverCtx = 'k1';
const turningRing = ringOf({ status: 'busy', compacting: min(1) });
show('compacting: the ring turns, and stays a ring while pointed at', /class="ctx compacting"/.test(turningRing)
  && /ctxTurn|animation-delay/.test(turningRing) && !/ctx-fill/.test(turningRing));
show('…and says so in its tip', /title="([^"]*)/.exec(turningRing)?.[1]);
state.hoverCtx = null;
const settledRing = contextRing(session({ ...reply, sessionId: 'k1', agent: opus(80000) }));
show('compacted: the arc fades where it was as the ring fills to its new size', /class="ctx settling"/.test(settledRing)
  && /class="ctx-arc" transform="rotate\(\d+ 6 6\)"/.test(settledRing) && /class="ctx-fill"/.test(settledRing));
show("…which one that wasn't compacting doesn't",
  /settling/.test(contextRing(session({ ...reply, sessionId: 'k2', agent: opus(80000) }))));
calm.matches = true;
const k3 = (fields) => contextRing(session({ ...reply, sessionId: 'k3', agent: opus(980000), compactTime: full,
  ...fields }));
k3({ compacting: min(1) });
show("compacted, its new size not read yet: it doesn't say compact now", !/Compact now/.test(k3({})));
show('…nor 29s on with the same size; 31s on (stopped with Esc), it does again',
  [29000, 31000].map((t) => { state.last.now = NOW + t; return /Compact now/.test(k3({})); }));
state.last.now = NOW;
const k4 = (tokens, fields) => contextRing(session({ ...reply, sessionId: 'k4', agent: opus(tokens), ...fields }));
k4(980000, { compacting: min(1) });
k4(980000, {});
k4(80000, {});
show('once its new size is in, a size that grows big again says compact now',
  /Compact now/.test(k4(980000, { compactTime: full })));

{
  // Beside the folded panel, out for what a module says is new in the session (a reply in its side chat): its line in
  // Claude's place, as a reply you haven't read, and its time on the title line, working or not; in the list, the row
  // as it is.
  const said = { line: 'In your side chat: Yes, <it> is search-v2 now.', at: NOW - 120000 };
  const parts = (s, kind, opts) => {
    const html = rowHTML(s, kind, NOW, opts);
    return [/<div class="claude[^>]*>.*?<\/div>/s.exec(html)?.[0] ?? null, /<div class="you">/.test(html),
            /class="time"[^>]*>([^<]*)</.exec(html)?.[1] ?? null];
  };
  const idle = session({ sessionId: 'q1', lastReply: 'Done with Quill.', lastReplyAt: NOW - 3600000,
                         lastPrompt: 'Ship it', lastPromptAt: NOW - 3700000 });
  show('a chat out for a side chat\'s reply: its line, nothing of yours, its time',
       parts(idle, 'seen', { chat: true, said }));
  const busy = session({ sessionId: 'q2', status: 'busy', lastPrompt: 'Tidy the docs', lastPromptAt: NOW - 60000,
                         activity: 'Reading index.md' });
  show('…while the session works', parts(busy, 'busy', { chat: true, said }));
  show('…without a line, the row as it is', parts(idle, 'seen', { chat: true, said: { at: said.at } }));
  show('…in the list, the row as it is', parts(idle, 'seen', { said }));
}
{
  // Settings' Show Conversation Text off (state.conversationShown, setConversationShown): no one's words on a row, yours
  // or another session's, and Claude's line only where conversationLine keeps it: what the panel knows, not what anyone
  // wrote. The time goes on the title line, the dot says the row's state in words, and the rest of the row stays: a
  // request's card, what runs in the background, and a module's note, a task's ask line among them.
  const keeps = (fields, kind, answered = null) => conversationLine(session(fields), kind, answered);
  show('Claude\'s line kept with the conversation hidden: [asks you, answered beside the folded panel, compacting, '
       + 'starting from the panel, a reply, working, idle]',
       [keeps({}, 'needs'), keeps({}, 'needs', { text: '✓ Answered' }), keeps({ compacting: min(1) }, 'busy'),
        keeps({ pending: true }, 'busy'), keeps({}, 'turn'), keeps({}, 'busy'), keeps({}, 'idle')]);
  const askNote = (row) => (row.s.sessionId === 'h9'
    ? { text: 'Do: Answer the question in Fern\'s new tab', tone: 'turn', cls: 'ask-note',
        html: askLineHTML('Do: Answer the question in Fern\'s new tab') } : null);
  // Rows whose id starts with hb are shown briefly, as every row in the list is; the others whole, as a chat beside the
  // folded panel is.
  const brief = (row) => {
    if (!row.s.sessionId.startsWith('hb')) row.brief = false;
  };
  core.rowNotes.push(askNote); core.rowLooks.push(brief); drawWhole = false;
  const text = (html) => html?.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() ?? null;
  const seen = (s, kind = classify(s, NOW, view()), opts = {}) => {
    const html = rowHTML(s, kind, NOW, opts);
    return { you: /<div class="you">/.test(html), claude: text(/<div class="claude[^>]*>(.*?)<\/div>/s.exec(html)?.[1]),
             time: /class="time"/.test(html), dot: /class="dot"[^>]*aria-label="([^"]*)"/.exec(html)?.[1] ?? null,
             card: /<div class="perm [^"]*" data-ask=/.test(html), running: /background-work/.test(html),
             note: text(/<div class="step-note[^>]*>(.*?)<\/div>/s.exec(html)?.[1]) };
  };
  const command = { id: 'h4a', tool: 'Bash', input: { command: 'npm test', description: 'Run the tests' },
                    truncated: false };
  const question = { id: 'h5a', tool: 'AskUserQuestion', truncated: false, input: { questions: [
    { question: 'Which database?', header: 'Database', options: [{ label: 'Postgres' }, { label: 'SQLite' }] }] } };
  const cases = [
    ['a reply you haven\'t read', session({ sessionId: 'h1', ...reply })],
    ['working, its step and timer', session({ sessionId: 'h2', status: 'busy', statusUpdatedAt: min(2),
      lastPrompt: 'run the suite', lastPromptAt: min(2), activity: 'Reading cart.test.ts' })],
    ['a message another session sent, under its name', session({ sessionId: 'h3', ...reply,
      lastPrompt: 'Take the cent next.', promptFrom: 'Wren', lastFocusedAt: min(1) })],
    ['a command waiting for your OK: what for, and its card', session({ sessionId: 'h4', status: 'waiting',
      lastPrompt: 'add the coupons table', lastPromptAt: min(3), ask: command })],
    ['a question: what about, and its card', session({ sessionId: 'h5', status: 'waiting', ask: question })],
    ['compacting', session({ sessionId: 'h6', ...reply, compacting: min(1) })],
    ['replied, a dev server running in the background', session({ sessionId: 'h7', ...reply, background: [shellJob] })],
    ['a conversation starting from the panel, your words in it', session({ sessionId: 'h8', pending: true,
      status: 'busy', name: 'New conversation', lastPrompt: 'Tidy the docs', lastPromptAt: min(0),
      activity: 'Starting in Ghostty' })],
    ['a task waiting on you, its ask line in the row\'s note', session({ sessionId: 'h9', ...reply })],
    ['a row shown briefly (as the list\'s are), replied', session({ sessionId: 'hb1', ...reply })],
    ['…asking you', session({ sessionId: 'hb2', status: 'waiting', ask: { ...command, id: 'hb2a' } })],
    ['stopped', session({ sessionId: 'h10', ...reply, status: 'closed', pid: 0, opensIn: 'Ghostty' })],
  ];
  state.conversationShown = false;
  for (const [name, s] of cases) show(name, seen(s));
  const chatAsk = session({ sessionId: 'h11', status: 'waiting', ask: { ...command, id: 'h11a' } });
  answered('h11a', 'once');
  show('a chat beside the folded panel, just answered there: what you answered stays', seen(chatAsk, 'needs',
                                                                                             { chat: true }));
  delete state.answering.h11a; delete state.answeredAt.h11a;
  const listAsk = session({ sessionId: 'hb13', status: 'waiting', ask: { ...command, id: 'hb13a' } });
  answered('hb13a', 'once');
  const receipt = rowHTML(listAsk, 'needs', NOW);
  show('a list row whose request you just answered: no line over it, and the line saying what you answered in the '
       + 'card\'s place', [seen(listAsk).claude, text(/<div class="perm ask-receipt[^>]*>(.*?)<\/div>/s.exec(receipt)?.[1])]);
  delete state.answering.hb13a; delete state.answeredAt.hb13a;
  show('the dot\'s words: stopped, its reply read; and a request answered beside the folded panel',
       [dotWords(session({ status: 'closed', pid: 0 }), 'seen'), dotWords(session({}), 'needs', { text: '✓' })]);
  show('a chat out for a side chat\'s reply: its name and time, without the reply', seen(session({ sessionId: 'h12',
    ...reply }), 'seen', { chat: true, said: { line: 'In your side chat: Yes, it is.', at: min(1) } }));
  state.conversationShown = true;
  show('…and with it on again, the reply and your message are back', seen(session({ sessionId: 'h1', ...reply })));
  core.rowNotes.splice(core.rowNotes.indexOf(askNote), 1);
  core.rowLooks.splice(core.rowLooks.indexOf(brief), 1); drawWhole = true;
}
{
  // A row in the list, shown briefly as every row there is, says one thing under its name, each thing once: an ask's
  // bubble, else a request's card, else Claude's line where nothing else says it (what it asks with no card, or its
  // finished line on a reply you haven't read), else nothing, its time on the title line. What it has no room for but
  // you may need says so as its note: a stopped session's way on, and Reload for one started before Whozmove's update.
  // The ticket it works on keeps its tag after the name. A chat beside the folded panel and a start from the panel stay
  // whole.
  drawWhole = false;
  const parts = (html) => [...html.matchAll(/<(?:div|span) class="(claude[^"]*|perm [^"]*|step-note[^"]*|time|you|work(?: noted)?|where|tag tk-row[^"]*)"/g)]
    .map(([, cls]) => cls.split(' ')[0]).join(' | ');
  const words = (html) => /<div class="step-note[^>]*>([\s\S]*?)<\/div>/.exec(html)?.[1].replace(/<[^>]+>/g, '').trim();
  const asking = (row) => (row.s.sessionId === 'ob-ask' ? { html: askLineHTML('Try the search box'), cls: 'ask-note',
                                                            line: true, quiet: false, tone: 'turn' } : null);
  core.rowNotes.push(asking);
  const row = (fields) => { const s = session(fields); return rowHTML(s, classify(s, NOW, view()), NOW); };
  const command = { id: 'ob-c', tool: 'Bash', input: { command: 'npm test', description: 'Run the tests' },
                    truncated: false };
  show('working: no line, its time on the title line', parts(row({ sessionId: 'ob-busy', status: 'busy',
    statusUpdatedAt: min(2), lastPrompt: 'run it', lastPromptAt: min(2), activity: 'Reading cart.ts' })));
  show('a reply you haven\'t read, nothing asked: Claude\'s finished line', parts(row({ sessionId: 'ob-turn', ...reply })));
  show('…once read: nothing under its name', parts(row({ sessionId: 'ob-read', ...reply, seenAt: min(1) })));
  show('a request: its card, no line over it', parts(row({ sessionId: 'ob-req', status: 'waiting',
    lastPrompt: 'add the table', lastPromptAt: min(3), ask: command })));
  show('asking with no card: Claude\'s line says what', parts(row({ sessionId: 'ob-wait', status: 'waiting',
    lastReply: 'Which colour should the button be?', lastReplyAt: min(2), statusUpdatedAt: min(2) })));
  show('an ask\'s bubble over an unread reply: the bubble alone', parts(row({ sessionId: 'ob-ask', ...reply })));
  const stopped = row({ sessionId: 'ob-stop', ...reply, seenAt: min(1), status: 'closed', pid: 0, opensIn: 'Ghostty' });
  show('stopped: its way on as its note', [parts(stopped), words(stopped)]);
  const old = row({ sessionId: 'ob-old', ...reply, seenAt: min(1), reload: { state: 'needed' } });
  show('started before Whozmove\'s update: Reload as its note, pressable',
       [parts(old), words(old), /class="nopr reload" data-reload="ob-old"/.test(old)]);
  show('…a bubble stays in front of it', parts(row({ sessionId: 'ob-ask', ...reply, reload: { state: 'needed' } })));
  const ticketed = row({ sessionId: 'ob-tk', ...reply, seenAt: min(1), ticket: { bound: { tracker: 'Jira',
    site: 'acme.atlassian.net', key: 'PAY-142', link: 'https://acme.atlassian.net/browse/PAY-142', title: 'Refunds',
    state: { name: 'In Progress', kind: 'doing' }, readAt: min(1) } } });
  show('working on a ticket: its tag after the name', [parts(ticketed), /data-tk="ob-tk"/.test(ticketed)]);
  show('a start from the panel: the row whole', parts(row({ sessionId: 'ob-new', pending: true, status: 'busy',
    name: 'New conversation', lastPrompt: 'Tidy the docs', lastPromptAt: min(0), activity: 'Starting in Ghostty' })));
  const s = session({ sessionId: 'ob-chat', ...reply });
  show('a chat beside the folded panel: the row whole', parts(rowHTML(s, classify(s, NOW, view()), NOW, { chat: true })));
  show('whether a short row has Claude\'s line (briefLine): asking, a request\'s card, asking with none, an unread '
       + 'reply, read, working', [briefLine({ asking: true, kind: 'turn' }), briefLine({ kind: 'needs' }, '<card>'),
    briefLine({ kind: 'needs' }), briefLine({ kind: 'turn' }), briefLine({ kind: 'seen' }), briefLine({ kind: 'busy' })]);
  // The row you're on (the session in front in its app) keeps its tools: its work line and its bottom line, with what
  // ends the bottom line there (Deploy, a stand-in here), not at its note's end; another row with a note has that end
  // at the note's, and one without has neither.
  const work = (row) => (row.s.sessionId.startsWith('ob-on') || row.s.sessionId.startsWith('ob-off') ? '[PR #12]' : '');
  const ender = () => '[End]';
  const quiet = (row) => (row.s.sessionId.endsWith('-noted') ? { text: 'Up next: after the search box', quiet: true }
    : null);
  core.slots.workStart.push(work); core.slots.placeEnd.push(ender); core.rowNotesLast.push(quiet);
  const ends = (html) => ({ parts: parts(html), atNote: /\[End\]<\/div>/.test(html.split('class="where"')[0]),
                            onBottomLine: /class="where"[\s\S]*\[End\]/.test(html) });
  show('the row you\'re on: its work line and bottom line under its short lines, its end on the bottom line',
       ends(row({ sessionId: 'ob-on', ...reply, seenAt: min(1), onItAt: min(1), focused: true })));
  show('…with a note too: the note in its work line\'s place, as on a whole row, the end still on the bottom line',
       ends(row({ sessionId: 'ob-on-noted', ...reply, seenAt: min(1), onItAt: min(1), focused: true })));
  show('a row you\'re not on: neither line, nothing at its end',
       ends(row({ sessionId: 'ob-off', ...reply, seenAt: min(1), onItAt: min(1) })));
  show('…with a note: its end at the note\'s', ends(row({ sessionId: 'ob-off-noted', ...reply, seenAt: min(1),
                                                         onItAt: min(1) })));
  show('a stopped row and one to reload: nothing at their notes\' end, so their words read whole', [
    ends(row({ sessionId: 'ob-stop-end', ...reply, seenAt: min(1), status: 'closed', pid: 0, opensIn: 'Ghostty' })).atNote,
    ends(row({ sessionId: 'ob-old-end', ...reply, seenAt: min(1), reload: { state: 'needed' } })).atNote]);
  const moving = session({ sessionId: 'ob-on-moved', ...reply, seenAt: min(1), onItAt: min(1) });
  rowHTML(moving, 'seen', NOW);
  state.shownAt['compact:ob-on-moved'] = 1;  // long ago, by the page's own clock
  rowHTML({ ...moving, focused: true }, 'seen', NOW);
  show('…becoming the row you\'re on: what comes on it counts as just shown', justShown('compact:ob-on-moved'));
  // An asking row (a bubble ending in Deploy) becoming the row you're on: its end stays the ask's, but the steps that
  // come onto it with its work line (Push, Commit) count as only just shown, so a press meant for the row that was
  // below it can't land on them.
  const tryAsk = (row) => (row.s.sessionId === 'ob-on-asks' ? { html: askLineHTML('Try the search box'), cls: 'ask-note',
                                                                 line: true, quiet: false, tone: 'turn',
                                                                 act: { want: 'try', html: '' } } : null);
  core.rowNotes.unshift(tryAsk);
  // It speaks for its checkout, which has changes, so it has next steps (Commit), and the git module keeps when they
  // were first shown (steps:<session>), short or not; a key of the row's own (compact:<session>) beside it.
  const switchesBefore = state.switches, ownersBefore = state.owners;
  state.switches = { ...state.switches, nextSteps: true };
  state.owners = new Set(['ob-on-asks']);
  const asksRow = session({ sessionId: 'ob-on-asks', ...reply, seenAt: min(1), onItAt: min(1),
                            checkout: { changes: 2, remotes: 1, upstream: 'origin/main' } });
  rowHTML(asksRow, 'seen', NOW);
  state.shownAt['steps:ob-on-asks'] = 1;  // shown long ago, by the page's own clock
  state.shownAt['compact:ob-on-asks'] = 1;
  rowHTML(asksRow, 'seen', NOW);
  const notYet = [justShown('steps:ob-on-asks'), justShown('compact:ob-on-asks')];
  const opened = rowHTML({ ...asksRow, focused: true }, 'seen', NOW);
  show('an asking row becoming the row you\'re on: its steps there, and [steps, its own key] just shown before, after',
       [/data-step="commit"/.test(opened), notYet, [justShown('steps:ob-on-asks'), justShown('compact:ob-on-asks')]]);
  state.switches = switchesBefore; state.owners = ownersBefore;
  core.rowNotes.shift();
  core.slots.workStart.pop(); core.slots.placeEnd.pop(); core.rowNotesLast.pop();
  core.rowNotes.splice(core.rowNotes.indexOf(asking), 1);
  drawWhole = true;
}
{
  // An ask line has one action, at its end: another module's for what it wants (`act.want`, askAct: 'try' is Deploy's),
  // else the note's own (`act.html`), else none; and while it asks, nothing else on the row offers one: what ends the
  // bottom line (Deploy's button, core.slots.placeEnd) is drawn nowhere, on a row shown briefly, a full row or the chat
  // beside the folded panel. Any other note leaves it where it was: on a full row's bottom line, at a brief row's note.
  // Rows whose id starts with deb are shown briefly; one ending in try asks you to try (Deploy), plan to approve a plan
  // (its own button), ask has no action, quiet a quiet note, and said an ask said in the work line's place.
  // A chat beside the folded panel is the row whole, as the row part draws it.
  const look = (row) => {
    if (!row.s.sessionId.startsWith('deb')) row.brief = false;
  };
  const asked = (act) => ({ html: askLineHTML('Do: Try the search box'), cls: 'ask-note', line: true, quiet: false,
                            tone: 'turn', act });
  const askNote = (row) => {
    const id = row.s.sessionId;
    if (id.endsWith('try')) return asked({ want: 'try', html: '<span class="play">[There]</span>' });
    if (id.endsWith('plan')) return asked({ html: '<span class="play">[Plan]</span>' });
    if (id.endsWith('ask')) return asked();
    if (id.endsWith('quiet')) return { text: 'Up next: after the search box', quiet: true, line: true };
    if (id.endsWith('said')) return { text: 'Do: Try the search box', cls: 'ask-note', quiet: false, tone: 'turn' };
    return null;
  };
  const deploy = () => '<button class="play">[Deploy]</button>';
  const tryAct = (row) => (row.askWant === 'try' ? '<button class="play">[Deploy]</button>' : '');
  core.rowLooks.push(look); core.rowNotes.push(askNote); core.slots.placeEnd.push(deploy); drawWhole = false;
  core.slots.askAct.push(tryAct);
  const where = (id, opts) => {
    const html = rowHTML(session({ sessionId: id, ...reply }), 'turn', NOW, opts);
    const note = /<div class="step-note[^>]*>(?:(?!<\/div>).)*<\/div>/s.exec(html)?.[0] || '';
    return { atNote: (note.match(/\[(\w+)\]/g) || []).join(' '),
             onBottomLine: /<div class="where">(?:(?!<\/div>).)*\[Deploy\]/s.test(html),
             times: (html.match(/\[Deploy\]/g) || []).length };
  };
  show('an ask to try has Deploy alone at its end: on a row shown briefly', where('deb-try'));
  show('…on a full row, which leaves the bottom line without it', where('de-try'));
  show('…and on the chat beside the folded panel', where('de-try', { chat: true }));
  show('an ask to approve a plan has its own button alone, and no Deploy anywhere: on a row shown briefly',
       where('deb-plan'));
  show('…on a full row', where('de-plan'));
  show('…and on the chat beside the folded panel', where('de-plan', { chat: true }));
  show('an ask with no action of its own: nothing at its end, and no Deploy anywhere', where('de-ask'));
  show('a quiet note on a full row leaves Deploy on the bottom line', where('de-quiet'));
  show('…and so does a note said in the work line\'s place', where('de-said'));
  show('…and a full row with no note', where('de-none'));
  show('…while a quiet note on a row shown briefly has it at its end', where('deb-quiet'));
  // The list's row and its chat drawn in turn, as each update draws both: the chat isn't the row, so its Deploy in
  // another place doesn't count as the row's moving, and its buttons stay as long shown as they were.
  // (A button of the case's own, as the modules' forget theirs on a row without them.)
  core.forgotten.prefixes.push('end-test');
  where('deb-quiet');
  state.shownAt['end-test:deb-quiet'] = Date.now() - 60000;
  where('deb-quiet', { chat: true }); where('deb-quiet'); where('deb-quiet', { chat: true });
  show('…the row and its chat drawn in turn: its buttons aren\'t taken as just shown again',
       !justShown('end-test:deb-quiet'));
  delete state.shownAt['end-test:deb-quiet'];
  // A member's chat, drawn whole beside the folded panel, keeps where its own Deploy was apart from its brief row's:
  // with the panel folded only the chat is drawn, and when an ask to try arrives the chat's Deploy moves to the ask
  // line; open, each update draws the row and then the chat, and when the ask goes the chat's Deploy moves back to the
  // bottom line. Each move waits to be seen, once.
  let asking = false;
  const memberAsk = (row) => (asking && row.s.sessionId === 'deb-member' ? asked({ want: 'try' }) : null);
  core.rowNotes.unshift(memberAsk);
  const chatAt = () => !!where('deb-member', { chat: true }).atNote;
  const update = () => [!!where('deb-member').atNote, chatAt()];
  const seenAgo = () => { state.shownAt['end-test:deb-member'] = Date.now() - 60000; };
  const fresh = () => justShown('end-test:deb-member');
  update(); seenAgo(); update();
  const still = !fresh();
  asking = true;
  const arrived = [chatAt(), fresh()];
  seenAgo(); chatAt();
  const once = !fresh();
  update(); seenAgo(); update();
  asking = false;
  const gone = [update(), fresh()];
  show('a member\'s chat: [its row and chat drawn in turn: not just shown, folded, the ask arriving: its Deploy at the '
       + 'ask line and just shown, drawn again: not just shown, open, the ask going: [row, chat] at the ask line and '
       + 'just shown]', [still, arrived, once, gone]);
  core.rowNotes.splice(core.rowNotes.indexOf(memberAsk), 1);
  // An ask's own button giving way to Deploy at the same place (a Run's Copy, then a Try): Deploy waits to be seen,
  // as a press meant for Copy may land on it.
  let swap = 'plan';
  const swapAsk = (row) => (row.s.sessionId === 'de-swap'
    ? asked(swap === 'plan' ? { html: '<span class="play">[Plan]</span>' } : { want: 'try' }) : null);
  core.rowNotes.unshift(swapAsk);
  where('de-swap');
  state.shownAt['end-test:de-swap'] = Date.now() - 60000;
  where('de-swap');
  const before = justShown('end-test:de-swap');
  swap = 'try';
  const swapped = where('de-swap').atNote;
  show('an ask\'s own button giving way to Deploy: [just shown before, Deploy now there, just shown]',
       [before, swapped, justShown('end-test:de-swap')]);
  core.rowNotes.splice(core.rowNotes.indexOf(swapAsk), 1);
  delete state.shownAt['end-test:de-swap'];
  delete state.shownAt['end-test:deb-member'];
  core.forgotten.prefixes.pop();
  core.rowLooks.splice(core.rowLooks.indexOf(look), 1); drawWhole = true;
  core.rowNotes.splice(core.rowNotes.indexOf(askNote), 1);
  core.slots.placeEnd.splice(core.slots.placeEnd.indexOf(deploy), 1);
  core.slots.askAct.splice(core.slots.askAct.indexOf(tryAct), 1);
}
{
  // The context ring is the commands module's: on a full row's bottom line, but not while the row asks something of
  // you, so the ask has one action.
  let want = null;
  const askNote = (row) => (row.s.sessionId === 'ring' && want !== null
    ? { html: askLineHTML('Compact: its context is nearly full'), cls: 'ask-note', line: true, quiet: false,
        tone: 'turn', act: want ? { want } : undefined } : null);
  core.rowNotes.unshift(askNote);
  const rings = () => {
    const html = rowHTML(session({ sessionId: 'ring', ...reply, agent: { model: 'claude-opus-5-5', tokens: 150000,
                                                                          compactWindow: 200000 } }), 'turn', NOW);
    const note = /<div class="step-note[^>]*>(?:(?!<\/div>).)*/s.exec(html)?.[0] ?? '';
    const bottom = /<div class="where">(?:(?!<\/div>).)*/s.exec(html)?.[0] ?? '';
    return [/class="ctx/.test(note), /class="ctx/.test(bottom)];
  };
  show('the context ring [at the ask, on the bottom line]: no ask', rings());
  want = '';
  show('…an ask with no action of its own', rings());
  want = 'try';
  show('…an ask to try', rings());
  core.rowNotes.splice(core.rowNotes.indexOf(askNote), 1);
}
{
  // An ask line's bubble, in the colour of how pressing it is (`look`; normal when it doesn't say), its priority's name
  // first in bold in place of the mark, and its one action's button (askActHTML), its words in its tip, made safe.
  const bubble = (look, priority) => noteHTML({ html: askLineHTML('Try the search box', 0, '', '', '', priority),
                                                cls: 'ask-note task', line: true, look, quiet: false, tone: 'turn' })
    .replace(/<svg[^]*?<\/svg>/, '[mark]');
  show('an ask\'s bubble: urgent, named', bubble('urgent', 'Critical'));
  show('…quiet, named', bubble('low', 'P2'));
  show('…with no look or name: your move\'s colour, and the mark', bubble(undefined, ''));
  show('an ask\'s action', askActHTML('[icon]', 'Read the plan, in <Wren>’s session', ' data-x="1"'));
}
// The line saying what a session is doing while it works, as the row gives it to others to draw (workLineHTML): the
// same as the row's Claude's line, under the label it's given, made safe.
show('the working line under its own label', workLineHTML(session({ status: 'busy', activity: 'Reading cart.ts',
  lastPromptAt: min(2) }), NOW, { label: 'Wren <cart>' }));
show('…the same as the row\'s Claude\'s line, under Claude\'s', (() => {
  const s = session({ status: 'busy', activity: 'Reading cart.ts', lastPromptAt: min(2) });
  return chatHTML(s, 'busy', NOW, { yours: false }) === workLineHTML(s, NOW);
})());
{
  // A module's end after Claude's words (core.slots.chatEnd), on every Claude line and only there; whether the row has
  // that line, as the bottom line's slots see it (row.claudeLine).
  let saw;
  core.slots.chatEnd.push((row) => `[Talk ${row.s.sessionId}]`);
  core.slots.placeEnd.push((row) => { saw = row.claudeLine; return ''; });
  const claudeLine = (s, kind) => {
    const html = rowHTML(s, kind, NOW);
    return [/<div class="claude[^>]*>.*?<\/div>/s.exec(html)?.[0] ?? null, (html.match(/chat-end/g) || []).length, saw];
  };
  const working = session({ sessionId: 'e1', status: 'busy', lastPrompt: 'Tidy the docs', lastPromptAt: NOW - 60000,
                            activity: 'Reading index.md' });
  show('working: after the time', claudeLine(working, 'busy'));
  show('a reply: after its words', claudeLine(session({ sessionId: 'e2', ...reply }), 'turn'));
  show('asking: after what for', claudeLine(session({ sessionId: 'e3', status: 'waiting', notice: 'Pick one' }), 'needs'));
  show('only your message (a turn you stopped): none, and no Claude line',
       claudeLine(session({ sessionId: 'e4', lastPrompt: 'go on', lastPromptAt: min(2), lastReply: 'Done.',
                           lastReplyAt: min(3) }), 'turn'));
  show('idle: none, and no Claude line', claudeLine(session({ sessionId: 'e5' }), 'idle'));
  core.slots.chatEnd.pop();
  core.slots.placeEnd.pop();
  show('with no module there: no end', claudeLine(working, 'busy').slice(0, 2));
}
{
  // The title line's places: after its words (titleEnd), then what lines up at its end before the time (titleTrail);
  // and what a module sees as they're asked, so one thing goes in one place: whether the row has Claude's line
  // (row.claudeLine) and whether the bottom line's end is drawn (row.placeEnd). Rows whose id starts with b are
  // shown briefly, and those with bn have a note, as a team's are.
  const saw = [];
  const look = (row) => { if (row.s.sessionId.startsWith('b')) row.brief = true; };
  const note = (row) => (row.s.sessionId.startsWith('bn') ? { text: 'Planning: 2 of 5' } : null);
  const words = (row) => (row.brief ? '<span class="tpart">design system</span>' : '');
  const end = (row) => { saw.push([row.s.sessionId, row.claudeLine, row.placeEnd]); return '[Talk]'; };
  const trail = (row) => (row.brief ? '[track]' : '');
  core.rowLooks.push(look); core.rowNotes.push(note); core.slots.brief.push(words);
  core.slots.titleEnd.push(end); core.slots.titleTrail.push(trail);
  const titleLine = (s, kind) => /<div class="line1">[^]*?<\/div>/.exec(rowHTML(s, kind, NOW))[0]
    .replace(/\s+/g, ' ').replace(/<span class="time"[^>]*>[^<]*<\/span>/, '[time]');
  show('a brief row, idle, no note: the words, then the end, then the trail, then the time',
       titleLine(session({ sessionId: 'b1' }), 'idle'));
  show('a brief row with a reply', titleLine(session({ sessionId: 'b2', ...reply }), 'turn'));
  show('a brief row with a note', titleLine(session({ sessionId: 'bn3' }), 'idle'));
  show('a full row: the same places, after the name', titleLine(session({ sessionId: 'f4' }), 'idle'));
  show('what each saw: [row, Claude\'s line, the bottom line\'s end drawn]', saw);
  for (const [list, part] of [[core.rowLooks, look], [core.rowNotes, note], [core.slots.brief, words],
                              [core.slots.titleEnd, end], [core.slots.titleTrail, trail]])
    list.splice(list.indexOf(part), 1);
}

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
    agent: { model: 'claude-opus-5-5', effort: 'high', mode: 'acceptEdits', tokens: 120000, window: 1000000 } })],
  ['your turn, with PRs and a worktree', session({ sessionId: 't1', ...reply, outcome: 'Tested',
    checkout: { changes: 1 },
    git: { branch: 'feature', root: '/work/app-f', worktree: 'app-f', worktreeOf: 'app', mainRoot: '/work/app' },
    prs: [pr({ title: 'Fix the tests', repo: 'e/app' }),
          pr({ url: 'https://github.com/e/app/pull/2', number: 2, isDraft: true, title: 'Draft' })],
    agent: { model: 'claude-sonnet-5-5', effort: 'medium', mode: 'bypassPermissions', tokens: 150000 } })],
  ['a reply you have read', session({ sessionId: 'v1', ...reply, outcome: 'Answered', lastFocusedAt: min(1) })],
  ['replied, its agent and a dev server running in the background: a mark for each, and what they are',
   session({ sessionId: 'g1', ...reply, background: [agentJob, shellJob] })],
  ['a command waiting for your OK, a dev server running in the background: its mark goes round the waiting dot, and '
   + 'what runs comes under the card',
   session({ sessionId: 'g2', status: 'waiting', background: [shellJob],
             ask: { id: 'g2a', tool: 'Bash', input: { command: 'npm test', description: 'Run the tests' },
                    truncated: false } })],
  ['five jobs in the background: three marks, and how many first',
   session({ sessionId: 'g3', ...reply, background: [agentJob, shellJob, { ...shellJob, command: 'vitest --watch' },
                                                    { ...agentJob, what: 'Write the docs' },
                                                    { ...shellJob, command: 'tsc --watch' }] })],
  ['stopped, its hook last listing a job: nothing goes round it',
   session({ sessionId: 'g4', ...reply, status: 'closed', pid: 0, background: [shellJob] })],
  ['a turn you stopped: only your message, not the reply before it', session({ sessionId: 'v2',
    ...repliedAt(min(20)), lastPrompt: 'now rename it', lastPromptAt: min(2) })],
  ['a message another session sent, under its name, escaped', session({ sessionId: 'v3', ...reply,
    lastPrompt: 'Tidy <the> notes', promptFrom: 'Lead & co', lastFocusedAt: min(1) })],
  ['a closed Claude Desktop conversation, open in Claude', session({ sessionId: 'd1', status: 'closed',
    entrypoint: 'claude-desktop', focused: true, name: 'Desk chat', pid: 0, lastReply: 'Done.', lastReplyAt: min(300),
    lastPromptAt: min(301), lastFocusedAt: min(299), outcome: 'Answered', git: null, cwd: '/work/notes' })],
  ['a terminal session that has ended, which a press opens again in Ghostty', session({ sessionId: 'k1',
    status: 'closed', pid: 0, opensIn: 'Ghostty', name: 'Fix the page', lastReply: 'Done.', lastReplyAt: min(120),
    lastPromptAt: min(121), git: null, cwd: '/work/site' })],
  ['…with a pull request on its work line', session({ sessionId: 'k3', status: 'closed', pid: 0, opensIn: 'Terminal',
    lastReply: 'Done.', lastReplyAt: min(120), lastPromptAt: min(121), prs: [pr({ title: 'Fix the tests' })] })],
];
for (const [name, s] of rows) print(`-- ${name}\n${rowHTML(s, classify(s, NOW, view()), NOW)}`);
// "Stopped · press to carry on", at the work line's start, on the row of a session that has stopped, whichever app it
// was in, and on no running one's; a step's note says its piece over the work line, the words with it.
{
  const html = (s) => rowHTML(s, classify(s, NOW, view()), NOW);
  const line = (s) => /class="nopr ended"><span class="pt">([^<]*)</.exec(html(s))?.[1] ?? 'no line';
  const ended = session({ sessionId: 'k4', status: 'closed', pid: 0, git: null });
  show('a terminal session that has ended', line(ended));
  show('…a Claude Desktop conversation Claude isn\u2019t running', line({ ...ended, entrypoint: 'claude-desktop' }));
  show('…a running session', line({ ...ended, status: 'idle', pid: 100 }));
  state.stepNotes.k4 = { text: 'Couldn’t open it in iTerm2', at: Date.now() };
  show('…a step note said over its work line',
       /class="work noted">.*class="work-note[^"]*"[^>]*>([^<]*)</.exec(html(ended).replace(/\n/g, ''))?.[1]);
  delete state.stepNotes.k4;
}
state.compactOpen.c1 = true;
const compacting = session({ sessionId: 'c1', agent: { model: 'claude-opus-5-5', tokens: 900000, window: 1000000 },
  compactTime: full });
print(`-- the Compact card open\n${rowHTML(compacting, classify(compacting, NOW, view()), NOW)}`);
delete state.compactOpen.c1;
// A pick going into a terminal session, then Claude Code asking about it in the terminal: a model by its name, anything
// else by its value.
for (const inTerminal of [false, true])
  for (const [field, value] of [['effort', 'low'], ['model', 'claude-sonnet-5-5']]) {
    const going = session({ sessionId: 'a1', goingIn: { field, value, inTerminal } });
    const html = rowHTML(going, classify(going, NOW, view()), NOW);
    const words = /class="card-title">([^<]*)</.exec(html)?.[1];
    show(`the ${field} picked, going in${inTerminal ? ', Claude asking in the terminal' : ''}`,
         `${words}${/perm-go/.test(html) ? ' [Take me there]' : ''}`);
  }
// "Switch model?" on its row (switchAsk), in the place of the pick going in: how much the conversation holds, and Don't
// ask again only where it's offered.
for (const never of [false, true]) {
  const asked = session({ sessionId: 'a1', goingIn: { field: 'model', value: 'claude-opus-5-5', inTerminal: false },
    switchAsk: { from: 'claude-sonnet-5-5', to: 'claude-opus-5-5', tokens: 152000, never } });
  const html = rowHTML(asked, classify(asked, NOW, view()), NOW);
  show(`"Switch model?" on its row${never ? ", with Don't ask again" : ''}`,
       [/class="card-title">([^<]*)</, /class="perm-why">([^<]*)</].map((r) => r.exec(html)?.[1]).join(' / ')
       + (/class="never/.test(html) ? " / Don't ask again" : '') + (/going-line/.test(html) ? ' / and going in' : ''));
}
// The whole card, with Don't ask again ticked.
const neverAsked = session({ sessionId: 'a1', goingIn: { field: 'model', value: 'claude-opus-5-5', inTerminal: false },
  switchAsk: { from: 'claude-sonnet-5-5', to: 'claude-opus-5-5', tokens: 152000, never: true } });
state.switchNever.a1 = true;
show('"Switch model?" with Don\'t ask again ticked', /<div class="perm switch-ask[^]*?<div class="perm-actions">[^]*?<\/div><\/div>/.exec(
  rowHTML(neverAsked, classify(neverAsked, NOW, view()), NOW))?.[0]);
delete state.switchNever.a1;
// A step that couldn't go in, with the button past its reason in its note.
state.stepNotes.n1 = { text: 'It shares its iTerm2 window, and iTerm2\'s Python API is off: ask there', quiet: false,
                       way: "Turn On iTerm2's Python API…", at: Date.now() };
show("a step's note with the button past its reason",
     /<div class="step-note[^"]*">[^]*?<\/div>/.exec(rowHTML(session({ sessionId: 'n1' }), 'idle', NOW))?.[0]);
delete state.stepNotes.n1;
{
  // A note whose reason has no way past it in the terminal: its button does something on the page instead (`go`).
  state.stepNotes.n2 = { text: 'It\'s open elsewhere too: change its mode in the terminal', quiet: false,
                         way: 'Take Me There', go: 'open', at: Date.now() };
  show("a step's note with Take Me There",
       /<div class="step-note[^"]*">[^]*?<\/div>/.exec(rowHTML(session({ sessionId: 'n2' }), 'idle', NOW))?.[0]);
  const sent = [], last = state.last, draw = render, rows = list.querySelectorAll;
  render = () => {};
  window.webkit = { messageHandlers: { panel: { postMessage: (msg) => sent.push(msg) } } };
  state.last = { sessions: [session({ sessionId: 'n2' }), session({ sessionId: 'n3' }), session({ sessionId: 'n4' })],
                 now: NOW };
  const pressWay = (sid) => pressNoteWay({ dataset: { way: sid } }, { preventDefault() {} });
  // Whether a row's note button has the mark for what takes you out of the panel.
  const markedOut = (sid) => /<button class="button small note-way"[^]*?<\/button>/
    .exec(rowHTML(session({ sessionId: sid }), 'idle', NOW))?.[0].includes('class="out-icon"');
  pressWay('n2');
  show('…pressed as it comes: nothing yet, as it has only just shown', { sent: sent.map((m) => m.type) });
  state.stepNotes.n2.at -= 5000;
  pressWay('n2');
  show('…pressed once it has been seen: the app is asked to open the session, and the note goes',
       { sent: sent.map((m) => `${m.type} ${m.sessionId}`), note: !!state.stepNotes.n2 });
  // The commands module's own: a switch's note opens the mode menu again, under the row's mode.
  sent.length = 0;
  list.querySelectorAll = () => [{ dataset: { pick: 'mode' }, closest: () => ({ dataset: { id: 'n3' } }),
                                   getBoundingClientRect: () => ({ left: 120, bottom: 60 }) }];
  state.stepNotes.n3 = { text: 'Let It Deploy couldn\'t be changed: try again', way: 'Open the Menu', go: 'modeMenu',
                         at: Date.now() - 5000 };
  const menuOut = markedOut('n3');
  pressWay('n3');
  show("a switch's note pressed: the app is asked for the row's mode menu, under its label",
       sent.map((m) => `${m.type} ${m.field} ${m.sessionId} at ${m.x},${m.y}`));
  // A pick into Claude Desktop that needs Whozmove allowed in Accessibility: its note opens that pane.
  sent.length = 0;
  state.stepNotes.n3 = { text: 'Allow Whozmove in Accessibility, then try again', way: 'Open Accessibility Settings',
                         go: 'accessibility', at: Date.now() - 5000 };
  show("a pick's note needing Accessibility: its button has the mark for leaving the panel, and Open the Menu's hasn't",
       { accessibility: markedOut('n3'), menu: menuOut });
  pressWay('n3');
  show("a pick's note needing Accessibility pressed: the app is asked to open its pane, and the note goes",
       { sent: sent.map((m) => m.type), note: !!state.stepNotes.n3 });
  // And the terminal's way past, as before.
  sent.length = 0;
  state.stepNotes.n4 = { text: 'It shares its iTerm2 window', way: "Turn On iTerm2's Python API…",
                         at: Date.now() - 5000 };
  pressWay('n4');
  show("a terminal's way past pressed: the app takes it, and the note stays for how it went",
       { sent: sent.map((m) => `${m.type} ${m.sessionId}`), way: state.stepNotes.n4.way });
  delete window.webkit;
  list.querySelectorAll = rows;
  state.last = last;
  render = draw;
  state.stepNotes = {};
}
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
show('its title line: the icon after the time',
  /<div class="line1"[^]*?<\/div>/.exec(rowHTML(twice, 'idle', NOW))?.[0]);
show('…open three times: the icon, and how many times in words', twiceHTML(session({ sessionId: 'o3', alsoOpen: [{ entrypoint: 'cli' },
                                                                                        { entrypoint: 'cli' }] })));
show('…and its bottom line says nothing of it', /twice/.test(/<div class="where"[^]*?$/.exec(rowHTML(twice, 'idle',
                                                                                                    NOW))[0]));
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
state.closedProjects['/work/other'] = true;
print(projectsOf(placeRows([
  session({ sessionId: 'g1', ...reply }),
  session({ sessionId: 'g2', status: 'busy', lastPromptAt: min(1) }),
  session({ sessionId: 'g3', cwd: '/work/other', git: { branch: 'main', root: '/work/other' }, outcome: 'Answered',
    lastReplyAt: min(500), seenAt: min(499) }),
].map((s) => ({ s, kind: classify(s, NOW, unread) })), {}, () => false), NOW));

section('What the page forgets');
// forgetGone works from the page's own clock.
const earlier = (ms) => Date.now() - ms;
Object.assign(state, {
  loadedAt: earlier(5 * 60000),
  seen: { listed: earlier(7200000), endedLongAgo: earlier(2 * 86400000), endedJustNow: earlier(7200000),
          readRecently: earlier(60000), readWithinTheHour: earlier(40 * 60000) },
  listedAt: { endedJustNow: earlier(10000), askJustAnswered: earlier(10000) },
  quiz: { askWaiting: {}, askJustAnswered: {}, askAnsweredLongAgo: {} },
  compactOpen: { listed: true, endedLongAgo: true },
  shownAt: { askWaiting: earlier(1000), 'compact:endedLongAgo': earlier(600000), 'steps:listed': earlier(1000),
             'steps:listed': earlier(500), 'steps:endedLongAgo': earlier(600000) },
});
forgetGone([session({ sessionId: 'listed', ask: { id: 'askWaiting', tool: 'Bash', input: {} } })]);
show('what you read, kept', Object.keys(state.seen).sort());
show('question state, kept', Object.keys(state.quiz).sort());
show('Compact cards, kept', Object.keys(state.compactOpen).sort());
show('when cards first showed, kept', Object.keys(state.shownAt).sort());

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
const waitWords = 'until “Review the native side” is done in the background (type /tasks in the session to stop it sooner)';
show('the row\'s own agents in the background: dimmed, saying what the app says it waits for',
  offer({ ...built, background: [agentJob, shellJob], backgroundWait: waitWords }, 'background', dep({ at: min(30) })));
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
    session({ sessionId: 'agents-in-the-background', ...reply, background: [agentJob] }),
    session({ sessionId: 'dev-server-left-running', ...reply, background: [shellJob] }),
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
print('-- the row\'s own agent in the background: its tip names it');
print(look({ ...built, background: [agentJob], backgroundWait: waitWords }, 'background', dep({ at: min(30) })));
print('-- agents in two other sessions working in the folder');
print(look(built, 'idle', dep({ at: min(30), waitsFor: ['codegen', 'formatter'] })));
print('-- only suggested, the agent working: no press to keep, as there\'s no command yet');
print(look(built, 'busy', suggested({ at: min(30) })));
print('-- your press kept, for the agent in another session: the menu, with Don\'t Deploy');
print(look(built, 'idle', dep({ folder: '/work/app-cart', waitsFor: ['cart total'], kept: { sessionId: 'd1' } })));
print('-- …for the row\'s own agent');
print(look(built, 'busy', dep({ kept: { sessionId: 'd1' } })));
show('a press kept: the offer', deployOffer(session(built), 'idle', true,
  dep({ waitsFor: ['cart total'], kept: { sessionId: 'd1' } }), NOW));
show('…the row\'s note, for one other session', keptNote({ waitsFor: ['cart total'] }, 'app-cart'));
show('…for two', keptNote({ waitsFor: ['cart total', 'codegen'] }, 'app-cart'));
show('…for the row\'s own agent', keptNote({}, 'app-cart'));
print('-- 300ms after the press');
print(look({}, 'idle', dep({ pressed: NOW - 300 })));
print('-- running for 2s');
print(look({}, 'idle', dep({ run: { running: true, startedAt: NOW - 2000 } })));
// A server, up: the stop square in a steady ring, its arc closing from where it had got to as the page first saw it up,
// and its address after the folder.
const upRun = (fields) => ({ running: true, startedAt: min(10) - 2500, up: { port: 3001, at: min(10), every: false,
                                                                           also: [], ...fields } });
show('a server, up: the button\'s look', deployOffer(session({}), 'idle', true, dep({ run: upRun({}) }), NOW).look);
print('-- up for 10 minutes, as the page loaded');
print(look({}, 'idle', dep({ run: upRun({}) })));
print('-- seen up just now: its arc closes into the ring from where it was, a turn every 1.2s from the run\'s start');
print(deployHTML(session({ sessionId: 'd1' }), dep({ run: { running: true, startedAt: NOW - 3100,
  up: { port: 3001, at: NOW - 400, every: false, also: [] } } }),
  deployOffer(session({}), 'idle', true, dep({ run: { running: true, startedAt: NOW - 3100,
    up: { port: 3001, at: NOW - 400 } } }), NOW), NOW, NOW - 400));
print('-- up on every address, on another port too, with files changed since it started: the tip says each');
print(look(built, 'idle', dep({ at: min(30), run: upRun({ every: true, also: [9229] }) })));
show('its tip, started just now', upTip(dep({ run: upRun({ at: NOW - 20000 }) }), { due: false }, NOW));
show('…up for 2 hours', upTip(dep({ run: upRun({ at: NOW - 125 * 60000 }) }), { due: false }, NOW));
print('-- its address, after the folder');
print(deployAddressHTML(session({ sessionId: 'd1' }), dep({ run: upRun({}) }), NOW));
print('-- …seen up just now: its room opens and it fades in after the ring has closed');
print(deployAddressHTML(session({ sessionId: 'd1' }), dep({ run: upRun({}) }), NOW, NOW - 200));
{
  // A full row with an ask to try and a build up: Deploy's button, its one action, at the ask line's end (askAct), and
  // its address left on the bottom line, where it can still be pressed (core.slots.placeStays).
  const up = (row) => {
    if (row.s.sessionId !== 'dup') return;
    row.deploy = dep({ run: upRun({}) });
    row.offer = deployOffer(row.s, row.kind, true, row.deploy, NOW);
  };
  const ask = (row) => (row.s.sessionId === 'dup' ? { html: askLineHTML('Do: Try the search box'), cls: 'ask-note',
                                                       line: true, quiet: false, tone: 'turn', act: { want: 'try' } }
    : null);
  core.rowLooks.push(up); core.rowNotes.push(ask);
  const html = rowHTML(session({ sessionId: 'dup', ...reply }), 'turn', NOW);
  const note = /<div class="step-note[^>]*>(?:(?!<\/div>).)*/s.exec(html)?.[0] ?? '';
  const bottom = /<div class="where">(?:(?!<\/div>).)*/s.exec(html)?.[0] ?? '';
  show('a full row with an ask to try and a build up: [Deploy at the ask line, its address there, Deploy on the bottom '
       + 'line, its address there]', [/class="play/.test(note), /d-addr/.test(note), /class="play/.test(bottom),
                                     /d-addr/.test(bottom)]);
  core.rowLooks.splice(core.rowLooks.indexOf(up), 1);
  core.rowNotes.splice(core.rowNotes.indexOf(ask), 1);
}
print('-- Deploy\'s card: another of Deploy\'s builds on the port, whose server takes $PORT: the next port leads');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'clash', port: 3001, other: 'app', next: 3003 },
                     dep({ folder: '/work/app-cart' })));
print('-- …a server that picks its own port: only replacing it');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'clash', port: 5173, other: 'app', fixed: true },
                     dep({ folder: '/work/app-cart' })));
print('-- …the same, met by a session\'s ask: it says who asked, its title escaped');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'clash', port: 5173, other: 'app', fixed: true,
                                                     asked: 'tidy <b>up</b>' },
                     dep({ folder: '/work/app-cart' })));
print('-- …a command confirmed before ports: giving each a port leads');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'clash', port: 3000, other: 'app', old: true },
                     dep({ folder: '/work/app-cart' })));
print('-- the port held by a server an agent started, for 20 minutes');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'held', port: 3001, name: 'node', minutes: 20, next: 3003,
                                                     session: 's9', sessionName: 'cart total' },
                     dep({ folder: '/work/app-cart' })));
print('-- …by a program no listed session started, just now, with no port to offer (a command confirmed before ports)');
print(deployCardHTML(session({ sessionId: 'd1' }), { kind: 'held', port: 3000, name: 'Python', minutes: 0 },
                     dep({ folder: '/work/app-cart' })));
// The run's own cards (deployRunCard), and their words.
const runCard = (d, seen = 0, shut) => deployRunCard(d, NOW, seen, shut);
const cart = (fields) => dep({ folder: '/work/app-cart', command: 'npm run dev', ...fields });
show('a run\'s card: a server seen up just now: Deployed', runCard(cart({ run: upRun({ at: NOW - 400 }) }), NOW - 400));
show('…up as the page loaded: none', runCard(cart({ run: upRun({}) })));
show('…seen up 11 minutes ago: none', runCard(cart({ run: upRun({ at: min(11) }) }), min(11)));
show('…put away: none', runCard(cart({ run: upRun({ at: NOW - 400 }) }), NOW - 400, `up:${NOW - 400}`));
show('…a server running 3 minutes with no port', runCard(cart({ run: { running: true, startedAt: min(3) } })));
show('…the same for a command that isn\'t one: none (the note says it)',
  runCard(dep({ run: { running: true, startedAt: min(3) } })));
const ended = (fields) => ({ running: false, ok: false, startedAt: min(30), finishedAt: NOW - 2000,
                             lastLines: ['> app@1.0.0 dev', 'Error: listen EADDRINUSE', '    at Server.listen'], ...fields });
show('…one that stopped by itself after 25 minutes up',
  runCard(cart({ run: ended({ endedItself: true, up: { port: 3001, at: min(25) } }) })));
show('…one with no packages', runCard(cart({ run: ended({ noPackages: true }) })));
show('…one that failed', runCard(cart({ run: ended({}) })));
show('…one you stopped: none', runCard(cart({ run: ended({ stopped: true }) })));
show('…one that went well: none', runCard(cart({ run: doneRun })));
print('-- Deployed, the first time for the project: its address a link, and each checkout runs beside the others');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: upRun({ at: NOW - 400 }) }), NOW - 400),
                     cart({ run: upRun({ at: NOW - 400 }) }), true));
print('-- …after that, just the title');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: upRun({ at: NOW - 400 }) }), NOW - 400),
                     cart({ run: upRun({ at: NOW - 400 }) })));
print('-- a server running 3 minutes with no port: Keep Waiting leads');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: { running: true, startedAt: min(3) } })),
                     cart({})));
print('-- one that stopped by itself, with its last lines, each cut at the card\'s edge');
print(deployCardHTML(session({ sessionId: 'd1' }),
  runCard(cart({ run: ended({ endedItself: true, up: { port: 3001, at: min(25) } }) })), cart({})));
print('-- one with no packages, from a pnpm lock file: Install First… leads, with Copy and Go to the row\'s session');
print(deployCardHTML(session({ sessionId: 'd1' }),
  runCard(cart({ run: ended({ noPackages: true, install: 'pnpm install --frozen-lockfile' }) })), cart({})));
print('-- Install First…, its second step, while the app looks at what it runs: Install and Deploy waits');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: ended({ noPackages: true, install: 'npm ci',
                                                                             lockfile: 'package-lock.json' }) })),
                     cart({}), false, true));
print('-- …from the project\'s lock file, with no install scripts of its own');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: ended({ noPackages: true, install: 'npm ci',
                                                                             lockfile: 'package-lock.json' }) })),
                     cart({}), false, { words: 'npm ci', lockfile: 'package-lock.json', hash: 'h1',
                                        files: ['package.json', 'package-lock.json'],
                                        packagesRun: true, runnerFiles: true }));
print('-- …with the project\'s own install scripts, each escaped, and what isn\'t followed');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: ended({ noPackages: true,
  install: 'pnpm install --frozen-lockfile', lockfile: 'pnpm-lock.yaml' }) })), cart({}), false,
  { words: 'pnpm install --frozen-lockfile', lockfile: 'pnpm-lock.yaml', hash: 'h2',
    runs: 'preinstall: node scripts/check-node.js\npostinstall: node scripts/<b>setup</b>.js && husky\n'
      + 'prepare: npm run build:icons',
    files: ['package.json', 'pnpm-lock.yaml', 'scripts/check-node.js'], others: ['node'],
    unsure: ['Whozmove doesn\'t know what husky runs'] }));
print('-- …with no lock file: it makes one');
print(deployCardHTML(session({ sessionId: 'd1' }),
                     runCard(cart({ run: ended({ noPackages: true, install: 'npm install' }) })), cart({}), false,
                     { words: 'npm install', makesLockfile: true, hash: 'h3', files: ['package.json'] }));
show('the note while it installs first', deployNote(cart({ run: { running: true, startedAt: min(3),
                                                                  installing: 'npm ci' } }), NOW));
show('…and no card for a server not listening yet, 3 minutes on', runCard(cart({ run: { running: true,
                                                                  startedAt: min(3), installing: 'npm ci' } })));
print('-- Install First\'s install that didn\'t go through: its own card, not Install First again');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: ended({
  installFailed: 'pnpm install --frozen-lockfile',
  lastLines: ['Installing packages first: pnpm install --frozen-lockfile', 'zsh: command not found: pnpm'] }) })),
                     cart({})));
show('…3 minutes on, a server whose packages went in a minute ago: no card yet',
     runCard(cart({ run: { running: true, startedAt: min(3), installedAt: min(1) } })));
show('…and its note, the same',
     deployNote(cart({ run: { running: true, startedAt: min(3), installedAt: min(1) } }), NOW));
print('-- a server that stopped before it was up, its last five lines of seven');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(cart({ run: ended({ lastLines: ['1', '2', '3', '4', '5', '6',
                                                                                          '<b>7</b>'] }) })), cart({})));
print('-- a deploy that isn\'t a server, which didn\'t go through');
print(deployCardHTML(session({ sessionId: 'd1' }), runCard(dep({ run: ended({}) })), dep({})));
show('the note while a server\'s up: none (the ring and the address say it)', deployNote(dep({ run: upRun({}) }), NOW));
show('the note after 3 minutes with no address yet',
  deployNote(dep({ run: { running: true, startedAt: min(3) } }), NOW));
show('…for a server: no address yet', deployNote(dep({ command: 'npm run dev', run: { running: true, startedAt: min(3) } }),
                                                NOW));
show('…for a watch, which isn\'t one', deployNote(dep({ command: 'tsc --watch', run: { running: true,
                                                                                   startedAt: min(3) } }), NOW));
print('-- went through 400ms ago: the check');
print(look({}, 'idle', dep({ run: doneRun, at: doneRun.finishedAt, seenDone: doneRun.finishedAt })));
print('-- back to play, 300ms after the check');
print(look({}, 'idle', dep({ run: { ...doneRun, finishedAt: NOW - 1800 }, at: NOW - 1800, seenDone: NOW - 1800 })));
print("-- didn't go through");
print(look(built, 'idle', dep({ run: failedRun, at: min(30) })));
show('the row\'s note, while it runs', deployNote(dep({ run: { running: true, startedAt: NOW - 2000 } }), NOW));
show('…just pressed', deployNote(dep({ pressed: NOW - 300 }), NOW));
show('…still running after 3 minutes', deployNote(dep({ run: { running: true, startedAt: NOW - 180000 } }), NOW));
show("…after one that didn't go through", deployNote(dep({ run: failedRun }), NOW));
show('…nothing once its card is put away', deployNote(dep({ run: failedRun }), NOW, `end:${failedRun.finishedAt}`));
show('…ten minutes on, nothing more', deployNote(dep({ run: { ...failedRun, finishedAt: min(11) } }), NOW));
show('…after you stopped it',
  deployNote(dep({ run: { running: false, ok: false, stopped: true, finishedAt: NOW - 5000 } }), NOW));
show('…nothing after one that went well', deployNote(dep({ run: doneRun }), NOW));
show('…a deploy a session asked for, waiting', deployNote(dep({
  asked: { by: 'shop api', waits: 'waits until the agent is done' } }), NOW));
show('…once it runs, as a press does', deployNote(dep({ asked: { by: 'shop api', waits: 'waits until you\'ve stepped '
  + 'off the panel' }, run: { running: true, startedAt: NOW - 2000 } }), NOW));
show('…a session\'s ask to restart its build that\'s up, waiting: said over the ring', deployNote(dep({
  asked: { by: 'shop api', waits: 'waits until the agent in “codegen” is done', restart: true }, run: upRun({}) }),
  NOW));
show('…once one a session asked for went through', deployNote(dep({ run: { ...doneRun, by: 'shop api' } }), NOW));
show('…and nothing once it\'s ten minutes old', deployNote(dep({ run: { ...doneRun, by: 'shop api', finishedAt: min(11) } }),
  NOW));
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
  command: 'make', production: false, runs: 'one\ntwo', cut: true } }, dep({})));
print('-- …with the files checked before every run, the programs that aren\'t, and what Whozmove can\'t follow');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'make install', then: 'save', checked: {
  command: 'make install', production: false, runs: 'cc -o tool main.c\ncp tool $(PREFIX)/',
  files: ['Makefile', 'config.mk'], others: ['cc', 'cp'],
  unsure: ['its Makefile includes a file it names with a variable or a pattern'] } }, dep({})));
print('-- …a file given to node: it\'s checked, and what it loads isn\'t');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'node server.js', then: 'save', checked: {
  command: 'node server.js', production: false, runs: 'node server.js (the file, 12 lines)', files: ['server.js'],
  others: ['what server.js loads'] } }, dep({})));
print('-- …one file checked, one program not');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'npm run build', then: 'save', checked: {
  command: 'npm run build', production: false, runs: 'build: tsc', files: ['package.json'],
  others: ['tsc'], runnerFiles: true } },
                dep({})));
print('-- confirming in a worktree: the port it gets in $PORT there, as a command confirmed here runs with one');
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'npm run dev', then: 'deploy', checked: {
  command: 'npm run dev', production: false, runs: 'next dev' } },
                dep({ folder: '/work/app-cart', port: 3001 })));
print('-- opened again with the command macOS refused to save: why, in its words (escaped), on both steps');
print(setupHTML(session({ sessionId: 'd6' }), { step: 1, text: 'make install', then: 'deploy',
  refused: 'The file “deploy.json” couldn’t be saved <because> the volume is full' }, dep({})));
print(setupHTML(session({ sessionId: 'd6' }), { step: 2, text: 'make install', then: 'deploy',
  refused: 'The file “deploy.json” couldn’t be saved because the volume is full', checked: {
  command: 'make install', production: false, runs: 'cc -o tool main.c' } }, dep({})));
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

section('The next steps');
const remote = { remotes: 1, upstream: true, base: 'main' };
const owned = { outcome: 'Implemented', outcomeAt: min(5) };
const onF = { git: { branch: 'f', root: '/work/app' } };
// Each step, briefly: commit (with how many files have staged changes), push N, publish N, pr into a branch.
const brief = (steps) => steps && Object.entries(steps).map(([step, v]) => step === 'commit'
  ? `commit, ${v.staged} staged` : step === 'pr' ? `pr into ${v.into}` : `${step} ${v}`);
const split = { filesStaged: 29, filesPartly: 31, filesUnstaged: 4 };
const checkouts = [
  ['clean: none', { ...owned, checkout: { ...remote, changes: 0 } }],
  ['changed files', { ...owned, checkout: { ...remote, changes: 2 } }],
  ['new files only', { ...owned, checkout: { ...remote, changes: 0, newFiles: 3 } }],
  ['while the agent works: shown all the same', { ...owned, status: 'busy', checkout: { ...remote, changes: 2 } }],
  ['no remote, with changes: commit only', { ...owned, checkout: { remotes: 0, changes: 1 } }],
  ['no remote, committed: finished, none', { ...owned, checkout: { remotes: 0, changes: 0, aheadOfBase: 1 } }],
  ['on main, commits not pushed', { ...owned, checkout: { ...remote, ahead: 2 } }],
  ['on main, never pushed: publish', { ...owned, checkout: { ...remote, upstream: false, aheadOfBase: 1 } }],
  ['on main, all pushed: none', { ...owned, checkout: { ...remote, ahead: 0, aheadOfBase: 0 } }],
  ['on main, changed files and commits: both', { ...owned, checkout: { ...remote, changes: 1, ahead: 2 } }],
  ['a branch not pushed: publish', { ...owned, ...onF, checkout: { ...remote, upstream: false, aheadOfBase: 2 } }],
  ['a branch pushed with no PR, as GitHub says: a pull request into main', { ...owned, ...onF,
    checkout: { ...remote, ahead: 0, aheadOfBase: 2, pr: null } }],
  ['…GitHub not asked yet (or no gh): none', { ...owned, ...onF, checkout: { ...remote, ahead: 0, aheadOfBase: 2 } }],
  ['…a PR the session raised from another branch doesn\'t count', { ...owned, ...onF, checkout: { ...remote,
    ahead: 0, aheadOfBase: 2, pr: null }, prs: [pr({ headRefName: 'g' })] }],
  ['…one it raised from this branch does: none', { ...owned, ...onF, checkout: { ...remote, ahead: 0, aheadOfBase: 2,
    pr: null }, prs: [pr({ headRefName: 'f' })] }],
  ['…a PR raised since GitHub last looked: none', { ...owned, ...onF, outcome: 'PR raised',
    outcomeAt: min(1), checkout: { ...remote, ahead: 0, aheadOfBase: 2, pr: null, prCheckedAt: min(5) / 1000 } }],
  ['a branch with an open PR, nothing new: none', { ...owned, ...onF, checkout: { ...remote, aheadOfBase: 2 },
                                                  prs: [pr({})] }],
  ['a branch with an open PR and new commits: push', { ...owned, ...onF,
    checkout: { ...remote, ahead: 1, aheadOfBase: 3 }, prs: [pr({})] }],
  ['a branch with an open PR and changed files: commit', { ...owned, ...onF, checkout: { ...remote, changes: 2,
    aheadOfBase: 3, pr: pr({ number: 14 }) } }],
  ['a branch whose PR was merged: none', { ...owned, ...onF, checkout: { ...remote, aheadOfBase: 2,
                                                                       pr: pr({ state: 'MERGED' }) } }],
  ['files staged and partly staged: a commit takes those', { ...owned, checkout: { ...remote, changes: 64,
    newFiles: 2, ...split } }],
];
for (const [name, fields] of checkouts) show(name, brief(stepsOf(session(fields), true)));
show("not the checkout's owner", stepsOf(session({ ...owned, checkout: { ...remote, changes: 2 } }), false));
show('outside git: none',
  stepsOf(session({ ...owned, git: null, cwd: '/work/notes', checkout: { changes: 2 } }), true));
const allSteps = stepsOf(session({ ...owned, checkout: { ...remote, changes: 3, ahead: 2, ...split } }), true);
show('what each says, beside its icon and over it', ['commit', 'push', 'publish'].map((step) =>
  stepWords(step, { ...allSteps, publish: 2 })));
show('…a commit with nothing staged', stepWords('commit', { commit: { staged: 0 } }));
show('where a branch stands while commits wait: ahead of its upstream\'s remote, or not published; nothing else waits',
  [outgoingWords({ upstream: 'origin/f' }, { push: 2 }), outgoingWords({ upstream: 'fork/f' }, { push: 1 }),
   outgoingWords({ upstream: null }, { publish: 1200 }),
   outgoingWords({ upstream: 'origin/f' }, { commit: { staged: 0 } }), outgoingWords({ upstream: 'origin/f' }, null)]);
show('…nothing while anything isn\'t committed, staged or not', [
  outgoingWords({ upstream: null }, { commit: { staged: 0 }, publish: 3 }),
  outgoingWords({ upstream: 'origin/f' }, { commit: { staged: 2 }, push: 2 })]);
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
show('…and only for the checkout it runs in: what it edits in another leaves that one\'s steps where they are',
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
// A code review's record, as the hook keeps it from the review's report (and its second, with outcomes, settled), with
// the branch it ran on once the hook notes it, on a checkout with changed files (on main), its last commit made `headAt`
// (in seconds, as git says it).
const audit = (found, left, at, settled = false, branch = null) =>
  ({ audit: { found, left, settled, at, ...(branch ? { branch } : {}) } });
const reviewed = (fields, checkout = {}) => session({ ...fields, checkout: { ...remote, changes: 2, ...checkout } });
const reviews = [
  reviewed(audit(5, 5, min(30))), reviewed(audit(5, 0, min(10), true)), reviewed(audit(5, 1, min(10), true)),
  reviewed(audit(0, 0, min(10))), reviewed({ ...audit(5, 5, min(30)), ...edited('/work/app', min(20)) }),
];
show('how the last code review went: what it found, then what it settled once it reports again; none: null',
  [...reviews.slice(0, 4).map((s) => reviewOf(s, [s])), reviewOf(reviewed({}), [])]);
show('…edited after it last reported: changed since; not its fixes, before its second report, nor edits elsewhere', [
  reviewOf(reviews[4], []),
  reviewOf(reviewed({ ...audit(5, 0, min(10), true), ...edited('/work/app', min(20)) }), []),
  reviewOf(reviewed({ ...audit(5, 5, min(30)), ...edited('/work/other', min(5)) }), [])]);
show('…edited here from a session running elsewhere: changed since all the same',
  reviewOf(reviewed(audit(5, 5, min(30))), [session({ sessionId: 'from-the-fix', git: fixHover,
                                                      ...edited('/work/app', min(5)) })]));
show('…with nothing left to fix, gone once anything is edited after it: what it passed has changed', [
  reviewOf(reviewed({ ...audit(0, 0, min(30)), ...edited('/work/app', min(20)) }), []),
  reviewOf(reviewed({ ...audit(5, 0, min(30), true), ...edited('/work/app', min(20)) }), [])]);
show('…with some left, gone once new work starts, a commit since and an edit since that; kept with only the commit, or'
  + ' a review of what was committed before it', [
  reviewOf(reviewed({ ...audit(5, 1, min(30), true), ...edited('/work/app', min(10)) },
                    { headAt: min(20) / 1000 }), []),
  reviewOf(reviewed(audit(5, 0, min(30), true), { headAt: min(20) / 1000 }), []),
  reviewOf(reviewed({ ...audit(5, 5, min(30)), ...edited('/work/app', min(10)) }, { headAt: min(40) / 1000 }), [])]);
show('…only one run on the branch the checkout is on now (or noted on none, by an older hook)', [
  reviewOf(reviewed(audit(5, 5, min(30), false, 'other')), []),
  reviewOf(reviewed(audit(5, 5, min(30), false, 'main')), []), reviewOf(reviewed(audit(5, 5, min(30))), [])]);
const reviewer = session({ sessionId: 'reviewer', name: 'search-review', ...audit(3, 3, min(5)) });
show('…the newest review in the checkout, from whichever session ran it, named when it isn\'t the row\'s; another'
  + ' checkout\'s doesn\'t count',
  reviewOf(reviewed({ sessionId: 'worker', ...audit(9, 9, min(50)) }), [reviewer,
    session({ sessionId: 'elsewhere', git: fixHover, ...audit(7, 7, min(1)) })]));
show('what the work line\'s start says of each, and over it',
  [...reviews.map((s) => reviewWords(reviewOf(s, []))),
   reviewWords({ found: 1, left: 1, settled: true, changed: false })]);
show('…naming the session the review ran in, when it isn\'t the row\'s', [
  reviewWords({ found: 3, left: 3, settled: false, changed: false, by: 'search-review' }),
  reviewWords({ found: 3, left: 3, settled: false, changed: true, by: 'search-review' })]);

print('-- a row with changed files: the commit icon at the end of the work line');
state.owners = new Set(['w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7']);
const withSteps = (sessionId, checkout, fields = {}) => session({ sessionId, outcome: 'Tested', workSteps: ['Built',
  'Tested'], checkout: { ...remote, added: 1493, removed: 62, ...checkout }, ...fields });
print(rowHTML(withSteps('w1', { changes: 3 }), 'idle', NOW));
print('-- changed files and commits to push: both, the commits counted');
print(rowHTML(withSteps('w1', { changes: 64, newFiles: 2, ahead: 2, upstream: 'origin/main', ...split }), 'idle', NOW));
print('-- …the commits\' icon pointed at: its word in, kept as the list is drawn again');
state.hoverStep = 'w1:push';
print(rowHTML(withSteps('w1', { changes: 64, newFiles: 2, ahead: 2, upstream: 'origin/main', ...split }), 'idle', NOW));
state.hoverStep = null;
print('-- a branch never pushed: the cloud, and where it stands where the pull requests go');
print(rowHTML(withSteps('w2', { upstream: false, aheadOfBase: 2 }, { git: { branch: 'f', root: '/work/app' } }),
              'idle', NOW));
print('-- commits to push with an open pull request: the pull request where it goes, and no words');
print(workHTML({ s: withSteps('w1', { ahead: 1, aheadOfBase: 3, upstream: 'origin/f' },
                              { git: { branch: 'f', root: '/work/app' }, prs: [pr({ headRefName: 'f' })] }),
                 kind: 'idle', owner: true, steps: { push: 1 } }));
print('-- a code review\'s findings still to fix: said where the pull requests go, uncommitted changes and all');
print(workHTML({ s: withSteps('w4', { changes: 3 }, audit(5, 5, min(30))), kind: 'idle', owner: true,
                 steps: { commit: { staged: 0 } } }));
print('-- …all fixed, with commits never pushed and nothing else: the review, ticked, opening those commits');
print(workHTML({ s: withSteps('w4', { upstream: false, aheadOfBase: 2 }, { git: { branch: 'f', root: '/work/app' },
                              ...audit(5, 0, min(10), true) }), kind: 'idle', owner: true, steps: { publish: 2 } }));
print('-- …with an open pull request, or Create PR offered: those, and no review');
print(workHTML({ s: withSteps('w4', { ahead: 1, upstream: 'origin/f' }, { git: { branch: 'f', root: '/work/app' },
                              prs: [pr({ headRefName: 'f' })], ...audit(5, 5, min(30)) }),
                 kind: 'idle', owner: true, steps: { push: 1 } }));
print(workHTML({ s: withSteps('w4', { ahead: 0, aheadOfBase: 1, pr: null }, { git: { branch: 'f', root: '/work/app' },
                              ...audit(5, 5, min(30)) }), kind: 'idle', owner: true, steps: { pr: { into: 'main' } } }));
print('-- …nothing left to go: no review, as no work line');
print(JSON.stringify(workHTML({ s: withSteps('w4', { changes: 0 }, audit(5, 0, min(10), true)), kind: 'idle',
                                owner: true, steps: null })));
print('-- a branch pushed with no pull request yet, as GitHub says: Create PR where the pull requests go');
const noPR = withSteps('w3', { ahead: 0, aheadOfBase: 1, pr: null }, { git: { branch: 'f', root: '/work/app' } });
print(rowHTML(noPR, 'idle', NOW));
print('-- …with changes not committed too: its numbers and its step at the line\'s end');
const noPRChanged = withSteps('w3', { ahead: 0, aheadOfBase: 1, pr: null, changes: 2 }, { git: { branch: 'f',
  root: '/work/app' }, changes: { all: { added: 26, removed: 13, files: 2, unstaged: { files: 2 } } } });
print(rowHTML(noPRChanged, 'idle', NOW));
state.last = { sessions: [noPR], now: NOW };
print('-- its details: into the repo\'s default branch until the branches on GitHub are known');
print(createPRCardHTML(noPR, stepsOf(noPR, true)));
print('-- …pressed open, the branches, the one it goes into ticked, the default named');
setPRBranches('w3', { base: 'main', branches: ['develop', 'f', 'main', 'release/1.4'] });
state.prPicking = 'w3';
print(createPRCardHTML(noPR, stepsOf(noPR, true)));
state.prInto.w3 = 'develop';
show('…another picked: it goes into that one',
  createPRCardHTML(noPR, stepsOf(noPR, true)).match(/cp-pick[^>]*>[^<]*/)[0]);
Object.assign(state, { prPicking: null, prInto: {}, prBranches: {} });
print('-- where it runs, in its details: a worktree of its project, a branch, a folder outside git');
print(placeCardHTML(session({ git: { branch: 'f', root: '/work/app-f', worktree: 'app-f', worktreeOf: 'app',
                                     mainRoot: '/work/app' } })));
print(placeCardHTML(session({ cwd: '/work/app', git: { branch: 'main', root: '/work/app' } })));
print(placeCardHTML(session({ cwd: '/work/notes', git: null, entrypoint: 'claude-desktop' })));
const placeOf = (git, cwd) => whereHTML({ s: session({ cwd, git }) }).match(/class="place[^"]*"/)[0];
show('where it runs, with a long name: it shortens first, before the model and effort',
     placeOf({ branch: 'search-results-redesign', root: '/work/app-s', worktree: 'app-s', worktreeOf: 'app',
               mainRoot: '/work/app' }));
show('…a dozen letters or fewer: it doesn\'t', placeOf({ branch: 'fix-login-12', root: '/work/app' }));
show('…a folder outside git, by its name', placeOf(null, '/work/quarterly-planning-notes'));
{
  // With a module's part after where it runs (Deploy's address): a short name still isn't one to shorten, so it keeps
  // its letters and the effort and model give way; a long one still shortens first.
  core.slots.placeEnd.push(() => '<span class="d-addr">:3001</span>');
  const bottom = (branch) => /<span class="place[^"]*"[^]*<\/div>$/.exec(whereHTML({ s: session({
    cwd: '/work/shop', git: { branch, root: '/work/shop' } }) }))[0].replace(/<svg[^]*?<\/svg>/, '');
  show('a short name with an address after it', bottom('main'));
  show('a long name with an address after it', bottom('feature/checkout-wallets-on-phones'));
  core.slots.placeEnd.pop();
}
// A pick on the bottom line squeezed past a letter goes whole, and the "·" with it (fitWhere): which "·" show.
show('all three show: both', sepsShown(['pick', 'sep', 'pick', 'sep', 'pick']));
show('the effort gone: the one between the model and the mode', sepsShown(['pick', 'sep', 'gone', 'sep', 'pick']));
show('the effort and the model gone: none before the mode', sepsShown(['gone', 'sep', 'gone', 'sep', 'pick']));
show('the model gone: the one between the effort and the mode', sepsShown(['gone', 'sep', 'pick', 'sep', 'pick']));
show('no effort, the model gone', sepsShown(['gone', 'sep', 'pick']));
{
  // A module's button in the slot, in the strip at the row's far edge: the row's last child; the row marked while the
  // pointer is on the strip, its bar swelled; no strip on a row the slot gives nothing. The modules' own buttons are
  // set aside meanwhile.
  const modules = core.slots.edge.splice(0);
  core.slots.edge.push((row) => (row.s.sessionId === 'e1' ? `<button class="keep">${row.s.sessionId}</button>` : ''));
  const tail = (html) => /<span class="edge-room">[^]*$/.exec(html)?.[0].replace(/\s+/g, ' ') ?? 'no room';
  const marks = (html) => /class="row ([^"]*)"/.exec(html)[1];
  show('a row with the strip', tail(rowHTML(session({ sessionId: 'e1' }), 'idle', NOW)));
  show('a row the slot gives nothing', tail(rowHTML(session({ sessionId: 'e2' }), 'idle', NOW)));
  show('…and one with a card open on it, a request for your OK: its strip still', tail(rowHTML(session({
    sessionId: 'e1', status: 'waiting', ask: { id: 'e1a', tool: 'Bash', input: { command: 'npm test' },
                                                truncated: false } }), 'needs', NOW)));
  show('…and a request\'s chat beside the folded panel: its strip still', /edge-room/.test(rowHTML(session({
    sessionId: 'e1', status: 'waiting', ask: { id: 'e1b', tool: 'Bash', input: { command: 'npm test' },
                                                truncated: false } }), 'needs', NOW, { chat: true })));
  state.compactOpen.e1 = true;
  const compact = rowHTML(session({ sessionId: 'e1' }), 'idle', NOW);
  show('…and one with Compact open on it: its card, and its strip still', [/data-compact=/.test(compact),
                                                                          /edge-room/.test(compact)]);
  delete state.compactOpen.e1;
  state.edgePointed = 'e1';
  show('its strip pointed at', marks(rowHTML(session({ sessionId: 'e1' }), 'idle', NOW)));
  state.edgePointed = null;
  core.slots.edge.splice(0, Infinity, ...modules);
}
{
  // What's pressable at the far end of a row's lines stays where it is as the pointer comes to it, so a press there is
  // its own: hover looks (every watcher, as hover.js runs them) with the pointer on Deploy's button where the row draws
  // it, the bottom line's last 18 points inside the row's 8 of padding (314 to 332 on a row from 0 to 340); on a next
  // step's button at its note's end, there too; and on the end of the folder's name, on a row without Deploy. Nothing
  // opens over them and the bar doesn't swell; only the strip past them, in the row's last 8 points, swells it.
  const row = { dataset: { id: 'p1' }, classList: element().classList,
                querySelector: (sel) => (sel === ':scope > .edge-room' ? {} : null),
                getBoundingClientRect: () => ({ left: 0, right: 340, top: 0, bottom: 62 }) };
  const on = { closest: (sel) => (sel === '.row[data-id]' ? row : null), dataset: {}, classList: element().classList };
  const pointer = state.pointer;
  for (const [what, x, y] of [["Deploy's button", 323, 44], ["a next step's button at its note's end", 323, 58],
                              ["the end of the folder's name", 330, 44]]) {
    state.pointer = { x, y };
    for (const watch of core.pointerWatchers) { try { watch(on); } catch (e) {} }
    show(`the pointer on ${what}: the row's lines stay where they are`, state.edgePointed !== 'p1');
    state.pointer = null;
    for (const watch of core.pointerWatchers) { try { watch(null); } catch (e) {} }
  }
  // A card on the row fills its lines to their end (332), its buttons 10 points further in (cards.css): the pointer on
  // Allow once's end, and 1 point inside the card's edge, is the card's, and the bar doesn't swell.
  for (const [what, x, y] of [["Allow once's end, on a request's card", 322, 40], ["1 point inside the card's edge", 331,
                                                                                    40]]) {
    state.pointer = { x, y };
    for (const watch of core.pointerWatchers) { try { watch(on); } catch (e) {} }
    show(`the pointer on ${what}: the bar doesn't swell`, state.edgePointed !== 'p1');
    state.pointer = null;
    for (const watch of core.pointerWatchers) { try { watch(null); } catch (e) {} }
  }
  const strip = { parentElement: row, closest: (sel) => (sel === '.row[data-id] > .edge-room' ? strip : null) };
  const onStrip = { closest: (sel) => (sel === '.row[data-id]' ? row : strip.closest(sel)), dataset: {},
                    classList: element().classList };
  state.pointer = { x: 336, y: 44 };
  for (const watch of core.pointerWatchers) { try { watch(onStrip); } catch (e) {} }
  show('the pointer on the strip, 4 points from the edge: the bar swells', state.edgePointed === 'p1');
  state.pointer = null;
  for (const watch of core.pointerWatchers) { try { watch(null); } catch (e) {} }
  state.pointer = pointer;
}
print('-- how a step went, said quietly in the work line\'s place, which keeps its height');
state.stepNotes.w4 = { text: 'Asked Claude to commit the changes', quiet: true, at: Date.now() };
print(rowHTML(withSteps('w4', { changes: 3, ahead: 1 }), 'idle', NOW));
print("-- a step that couldn't go in, said there too");
state.stepNotes.w4 = { text: 'Claude is working: ask again when it\'s done', at: Date.now() };
print(rowHTML(withSteps('w4', { changes: 3 }), 'idle', NOW));
print('-- a row with no work line: its note on a line of its own, over the bottom line');
state.stepNotes.w6 = { text: 'Closed the other copy', quiet: true, at: Date.now() };
print(rowHTML(withSteps('w6', {}), 'idle', NOW));
state.stepNotes = {};
const hasWorkLine = (kind, fields = {}) => /class="work[ "]/.test(rowHTML(withSteps('w4', { changes: 3, ahead: 1 },
  fields), kind, NOW));
show('while its agent works, asks you something along the way or compacts, the row has no work line; done, it\'s back',
     [hasWorkLine('busy', { status: 'busy' }), hasWorkLine('needs', { status: 'waiting' }),
      hasWorkLine('idle', { compacting: min(1) }), hasWorkLine('idle')]);
state.stepNotes.w4 = { text: 'Asked Claude to commit the changes', quiet: true, at: Date.now() };
show('…but for a note, which it keeps saying in its place', hasWorkLine('busy', { status: 'busy' }));
state.stepNotes = {};
// Deploy's button and line go by the page's own clock: held at NOW while they're drawn, so they read the same each run.
const pageClock = Date.now;
Date.now = () => NOW;
print("-- Deploy's button at the end of the bottom line, with the dot; why its last deploy didn't go through, on its card");
state.deploys = { projects: { '/work/app': { command: 'make install' } },
                  folders: { '/work/app': { at: min(30), run: failedRun } } };
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5))), 'idle', NOW));
print('-- while the agent works: Deploy dimmed, shown all the same, and its last deploy\'s card');
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5), { status: 'busy' })), 'busy', NOW));
state.shownAt['deploy:w5'] -= 5000;  // up a while
state.owners.delete('w5');  // another row speaks for the folder for a while
rowHTML(withSteps('w5', { changes: 3 }), 'idle', NOW);
state.owners.add('w5');
rowHTML(withSteps('w5', { changes: 3 }), 'idle', NOW);
show("Deploy's button, gone and back, waits again before it takes a press", justShown('deploy:w5'));
show('…as do the steps', justShown('steps:w5'));
state.atWork = { '/work/app': [session({ sessionId: 'w9', name: 'codegen', status: 'busy' }),
                               session({ sessionId: 'w5', status: 'busy' })] };
show("what a row's Deploy waits for: the other sessions at work in its folder, by title",
     rowDeploy(withSteps('w5', {})).waitsFor);
state.atWork = {};
show("the line when a deploy couldn't start: why, for a few seconds, in place of the deploy's own",
  (state.stepNotes.w5 = { text: 'Deploy waits until the agent is done', at: Date.now() },
   stepLine({ s: withSteps('w5', {}), deploy: rowDeploy(withSteps('w5', {})), offer: {} })));
state.stepNotes = {};
// Install and Deploy refused while an agent works there: the card stays, at its first step, and the row says why.
const deploysBefore = state.deploys;
state.deploys = { projects: { '/work/app': { command: 'npm run dev' } },
                  folders: { '/work/app': { run: { running: false, ok: false, startedAt: NOW - 9000,
                                                   finishedAt: NOW - 2000, noPackages: true, install: 'npm ci',
                                                   lockfile: 'package-lock.json',
                                                   lastLines: ["Error: Cannot find module 'vite'"] } } } };
state.stepNotes.w5 = { text: 'Deploy waits until the agent in “codegen” is done', at: Date.now() };
const refused = rowHTML(withSteps('w5', {}), 'idle', NOW);
show('Install and Deploy refused for an agent at work: the card stays, and the row says why',
     { card: refused.includes('has no packages installed yet'),
       note: refused.includes('Deploy waits until the agent') });
state.stepNotes = {};
state.deploys = deploysBefore;
print('-- the set-up card on its row');
state.deploySetup.w5 = { step: 1, text: 'make install', then: 'save' };
print(rowHTML(withSteps('w5', { changes: 3 }, editedHere(min(5))), 'idle', NOW));
state.deploySetup = {};
print('-- Show Next Steps off: no steps');
state.switches = { ...state.switches, nextSteps: false };
print(rowHTML(withSteps('w6', { changes: 3 }), 'idle', NOW));
state.switches = { ...state.switches, nextSteps: true };
state.deploys = { projects: {}, folders: {} };
Date.now = pageClock;
state.owners = new Set();

section('What a session wrote: the tag, the reader');
const planWriting = (id, status, at, title) => ({ id, kind: 'plan', title, path: '/h/.claude/plans/p.md', at: min(at), status });
const wrote = [planWriting('p2', 'waiting', 2, 'Dark mode, again'),
               { id: '/work/app/v.html', kind: 'prototype', title: 'Two layouts', path: '/work/app/v.html', at: min(5) },
               planWriting('p1', 'declined', 9, 'Dark mode'),
               { id: '/work/app/n.md', kind: 'notes', title: 'Notes', path: '/work/app/n.md', at: min(20) }];
const planAsk = { id: 'pa', tool: 'ExitPlanMode', at: min(1), input: { plan: '# Dark mode, again\nText', planFilePath: '/p.md' } };
show('no writings: no tag', writingsTag(session({})));
show('the newest thing, and how many more', writingsTag(session({ writings: wrote.slice(1) })));
show('the plan waiting for you leads, while Claude asks about it', writingsTag(session({ writings: wrote, ask: planAsk })));
show('…and once it has stopped asking here, while its session still asks',
     writingsTag(session({ writings: wrote, status: 'waiting' })).includes('wtag plan'));
state.reading = { sessionId: 's', mode: 'writings' };
show("the tag shows as pressed while the reader is open on its session",
  writingsTag(session({ writings: wrote.slice(1) })).includes('tag wtag on'));
state.reading = null;
{
  // A short row has its tag after its name too, as a row drawn whole does: the title line's parts, in order.
  const titleParts = (html) => [...(html.match(/<div class="line1">.*?<\/div>/s)?.[0] || '')
    .matchAll(/class="(name|tag[^"]*)"/g)].map(([, cls]) => cls);
  const wroteRow = { ...session({ writings: wrote.slice(1) }), sessionId: 'ws', name: 'storefront' };
  drawWhole = false;
  show('a short row: its name, then its tag', titleParts(rowHTML(wroteRow, 'idle', NOW)));
  drawWhole = true;
  show('…as on a row drawn whole', titleParts(rowHTML(wroteRow, 'idle', NOW)));
}
show('a plan only just asked about shows from its request, before the transcript lists it',
     writingsOf(session({ ask: planAsk })).map((w) => [w.id, w.title, w.status]));
show('the plan Claude waits on', waitingPlan(session({ writings: wrote, ask: planAsk }))?.id);
show('no plan waits once the request is gone', waitingPlan(session({ writings: wrote })));
show("each one's status in the list", wrote.map((w) => writingStatus(w, session({ writings: wrote, ask: planAsk }))));
show('a waiting plan whose request has gone, its session idle with nothing typed since: still waiting for you',
     writingStatus(wrote[0], session({ writings: wrote })));
show('…something typed into it since: no answer', writingStatus(wrote[0], session({ writings: wrote, lastPromptAt: NOW })));
show('a new request with only an old unanswered plan listed: the request\'s own plan, never the old one',
     waitingPlan(session({ writings: [planWriting('old', 'waiting', 30, 'Old')], ask: planAsk }))?.id);
state.last = { sessions: [], now: NOW };
print(shelfHTML(session({ writings: wrote, ask: planAsk }), wrote, 'p2'));
const markupName = { id: '/work/app/<b>n.md', kind: 'notes', path: '/work/app/<b>n.md', at: min(3) };
show('a file named like markup is listed as text',
     !shelfHTML(session({ writings: [markupName] }), [markupName], null).includes('<b>'));
show('a plan has no card on its row: it\'s its bubble, read beside the list',
     core.rowCards.find((c) => c.name === 'request').wants({ s: session({ ask: planAsk }) }));
{
  // A member of a team held at Claude Code's own prompt for its plan, while the team file still has it at work on
  // another job, so the plan is its row's other ask: the bubble ends in the button that opens the plan beside the list,
  // and a press on it, once seen, opens it there.
  const STEPS = [{ id: 'plan', word: 'Plan', you: true, kind: 'approve' }, { id: 'build', word: 'Build', you: false }];
  const held = session({ sessionId: 'held', name: 'Moth', status: 'waiting', statusUpdatedAt: min(1),
                         lastPromptAt: min(4), writings: wrote,
                         team: { role: 'member', name: 'Moth', part: 'sync',
                                 job: { id: 'j1', title: 'Offline mode', steps: STEPS, at: 'build', you: false,
                                        priority: 'p1', holds: 0, stageAt: min(30) },
                                 status: { stage: 'work', word: 'Build', job: 'j1' },
                                 alsoAsks: { job: 'j2', title: 'Dark mode', short: 'Approve the dark mode plan',
                                             at: 'plan', priority: 'p1', kind: 'approve' } } });
  const [lastBefore, openBefore, kindsBefore, wholeBefore] = [state.last, openReader, state.kinds, drawWhole];
  drawWhole = false;  // the list's own rows, shown short
  state.last = { sessions: [held], now: NOW };
  const heldHTML = rowHTML(held, classify(held, NOW, { id: 'held' }), NOW);
  const opened = [];
  openReader = (sid, wid, mode) => opened.push([sid, wid, mode]);
  state.shownAt['wr-act:held'] = Date.now() - 60000;
  core.presses.find(([sel]) => sel === '[data-wr-act]')[1](
    { dataset: { wrAct: 'held', wid: /data-wid="([^"]*)"/.exec(heldHTML)?.[1] } }, { preventDefault() {} });
  show('a team member held at its plan while the team file has it at work: its other ask ends in the reader\'s plan '
       + 'button, never the way to its session, and a press opens the plan beside the list [button, to session, opened]',
       [heldHTML.includes('data-wr-act="held"'), heldHTML.includes('data-team-go="held"'), opened]);
  // The same member at work on that other job: its ask has the same shape and the same press, opening the newest plan
  // it showed you that wasn't approved, there only to read, its bar taking you to the session.
  const working = { ...held, sessionId: 'working', status: 'busy', activity: 'Editing sync.js' };
  state.last = { sessions: [working], now: NOW };
  state.kinds = { working: classify(working, NOW, { id: 'working' }) };
  const workingHTML = rowHTML(working, classify(working, NOW, { id: 'working' }), NOW);
  state.shownAt['wr-act:working'] = Date.now() - 60000;
  core.presses.find(([sel]) => sel === '[data-wr-act]')[1](
    { dataset: { wrAct: 'working', wid: /data-wid="([^"]*)"/.exec(workingHTML)?.[1] } }, { preventDefault() {} });
  show('…at work on the other job: the same button, and a press opens the plan beside the list [button, to session, '
       + 'opened]', [workingHTML.includes('data-wr-act="working"'), workingHTML.includes('data-team-go="working"'),
                     opened.slice(1)]);
  state.reading = { sessionId: 'working', mode: 'writings', sent: {}, revising: false, notes: '' };
  print(answerHTML(wrote[0], working));
  state.reading = null;
  show('…its newest plan approved, the work it\'s doing: nothing to read, so the way to its session',
       rowHTML({ ...working, writings: [{ ...wrote[0], status: 'approved' }] }, 'busy', NOW)
         .includes('data-team-go="working"'));
  [state.last, openReader, state.kinds, drawWhole] = [lastBefore, openBefore, kindsBefore, wholeBefore];
}
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
md('a diagram: drawn by the diagrams module, its text inside until it is', '```mermaid\ngraph TD\n  A[Save] --> B[Open]\n```');
md('a diagram it doesn\'t draw: as written, saying why', '```mermaid\npie title Saved\n  "Mains" : 3\n```');
const mdDiagrams = core.fences.mermaid;
delete core.fences.mermaid;
md('a diagram without the diagrams module: code, as before', '```mermaid\ngraph TD\n  A[Save] --> B[Open]\n```');
core.fences.mermaid = mdDiagrams;
print(`-- a diagram on the list (a request's card): code, as before\n${markdownHTML('```mermaid\ngraph TD\n  A --> B\n```', 'list')}`);

section('What isn\'t committed: the row\'s numbers, their details, the changes view');
const chAll = { added: 245, removed: 42, files: 6, unstaged: { files: 5, added: 227, removed: 35 },
                staged: { files: 2, added: 18, removed: 7 } };
const chRow = session({ sessionId: 'me', name: 'Retry queue', changes: { all: chAll, v: 4 },
                        checkout: { ...remote, base: 'main', ahead: 2 } });
state.owners = new Set(['me']);
print('-- the checkout\'s numbers at the end of the work line of the row that speaks for it, as a button');
print(workHTML({ s: chRow, kind: 'idle' }));
show('…not on another session\'s row in the same checkout', countsHTML(chRow, false));
state.reading = { sessionId: 'me', mode: 'changes' };
show('pressed while its changes are open', countsHTML(chRow, true).includes('counts on'));
state.reading = { sessionId: 'me', mode: 'writings' };
show('…not while what it wrote is', countsHTML(chRow, true).includes('counts on'));
state.reading = null;
show('nothing to commit: no numbers', countsHTML(session({ changes: { all: { added: 0, removed: 0, files: 0 } } }), true));
show('a file only renamed counts, with no lines', countsHTML(session({ sessionId: 'mv',
  changes: { all: { added: 0, removed: 0, files: 1 } } }), true));
state.owners = new Set();
print('-- their details: what isn\'t committed, and how many files are staged and not');
print(changesCardHTML(chRow));
show('…nothing staged', changesCardHTML(session({ changes: { all: { ...chAll, files: 5,
  staged: { files: 0, added: 0, removed: 0 } } } })).match(/card-lead">[^<]*/)[0]);
const chHunk = { oldStart: 10, newStart: 10, lines: [[' ', 'def a():'], ['-', '    old()'], ['-', '    older()'],
                                                   ['+', '    new()'], [' ', ''], ['+', '# tested']] };
const chUnstaged = { scope: 'unstaged', v: 4, files: [
  { path: 'billing/retry.py', status: 'changed', alsoStaged: true, hunks: [chHunk] },
  { path: 'billing/queue.py', status: 'new', untracked: true,
    hunks: [{ oldStart: 0, newStart: 1, lines: [['+', 'QUEUE = []']] }] },
  { path: 'docs/old.md', status: 'gone', hunks: [] },
  { path: 'docs/retries.md', status: 'renamed', hunks: [] },
  { path: 'vendor/big.js', status: 'changed', cut: true, added: 31000, removed: 2, hunks: [] }] };
const chStaged = { scope: 'staged', v: 4, files: [
  { path: 'billing/retry.py', status: 'changed', alsoUnstaged: true, hunks: [chHunk] },
  { path: 'billing/notes.py', status: 'new', hunks: [] }] };
const chOutgoing = { scope: 'outgoing', v: 4, upstream: 'origin/retry', more: 0, commits: [
  { hash: 'a41c9e2aa', short: 'a41c9e2', subject: 'Retry failed payments', at: min(26),
    files: [{ path: 'billing/retry.py', status: 'changed', hunks: [chHunk] }] },
  { hash: '7d0b5f1bb', short: '7d0b5f1', subject: 'Start the retry queue', at: min(41),
    files: [{ path: 'billing/retry.py', status: 'new', hunks: [] }, { path: 'billing/queue.py', status: 'new', hunks: [] }] }] };
show('git\'s letters: changed, untracked, deleted, renamed, changed; and added, in Staged',
     [...chUnstaged.files, chStaged.files[1]].map((f) => gitLetter(f)[1]));
show('a file\'s count: from its lines, or as the app counted one cut short',
     [fileCount(chUnstaged.files[0]), fileCount(chUnstaged.files[4])]);
show('where else git lists a file: staged too, untracked, changed again since it was staged; nowhere',
     [fileNote(chUnstaged.files[0], 'unstaged'), fileNote(chUnstaged.files[1], 'unstaged'),
      fileNote(chStaged.files[0], 'staged'), fileNote(chUnstaged.files[2], 'unstaged')]);
show('Outgoing\'s files keyed by their commit too: a file in two commits is there twice', viewFiles(chOutgoing).map((f) => f.key));
show('the head, in git\'s words', [changesSub('unstaged', chAll), changesSub('staged', chAll),
  changesSub('outgoing', chAll, chOutgoing), changesSub('outgoing', chAll, { ...chOutgoing, upstream: null }),
  changesSub('outgoing', chAll, { ...chOutgoing, commits: [] }),
  changesSub('outgoing', chAll, { ...chOutgoing, upstream: null, commits: [] }), changesSub('outgoing', chAll, null)]);
show('what an empty tab says', CHANGE_TABS.map(([scope]) => emptyWords(scope)));
show('side by side: taken-out lines beside the ones put in after them', splitRows(chHunk).map(([l, r]) =>
  [l && `${l.at}${l.line[0]}`, r && `${r.at}${r.line[0]}`]));
show('unchanged lines before a hunk, and between two', [linesBetween(null, chHunk),
     linesBetween(chHunk, { oldStart: 30, newStart: 30, lines: [] })]);
show('where Open in Editor opens it: the first line put in, else its first change',
     [firstChangedLine(chUnstaged.files[0]), firstChangedLine({ hunks: [{ oldStart: 4, newStart: 4, lines: [['-', 'x']] }] }),
      firstChangedLine(chUnstaged.files[2])]);
show('a little colour for code', [codeHTML('  // a <note>'), codeHTML('say("hi") + \'x\''), codeHTML('# heading')]);
show('…and none for prose', [codeHTML("# Claude's own \"words\"", 'docs/a.md'), codeHTML("it's Claude's", 'notes.txt')]);
state.last = { sessions: [chRow], now: NOW };
const chState = (scope, view) => ({ scope, views: { [scope]: view }, key: null, layout: 'all', split: false, seen: null });
print('-- the bar on Changes: the tabs with their counts, Commit with its other ways, then the layout');
print(changesBarHTML(chRow, chState('unstaged', chUnstaged)));
print('-- on Outgoing: Push');
print(changesBarHTML(chRow, chState('outgoing', chOutgoing)));
show('…Publish, for a branch never pushed', changesBarHTML({ ...chRow, checkout: { ...remote, upstream: false,
  aheadOfBase: 2 } }, chState('outgoing', chOutgoing)).match(/data-step="\w+"/)[0]);
show('…nothing to commit: Commit can\'t be pressed', /data-step="commit"[^>]*disabled/.test(changesBarHTML(
  session({ changes: { all: { added: 0, removed: 0, files: 0 } }, checkout: remote }), chState('unstaged', chUnstaged))));
state.switches = { ...state.switches, nextSteps: false };
show('…Show Next Steps off: a step on the bar', /c-step/.test(changesBarHTML(chRow, chState('unstaged', chUnstaged))));
state.switches = { ...state.switches, nextSteps: true };
print('-- the list on Changes, as git lists it, the first lit');
print(changesShelfHTML(chRow, chState('unstaged', chUnstaged)));
print('-- the list on Outgoing, under each commit');
print(changesShelfHTML(chRow, chState('outgoing', chOutgoing)));
show('while a tab\'s view is on its way: where it\'s coming from',
     ['unstaged', 'staged', 'outgoing'].map((scope) => changesWaitWords(chRow, chState(scope, undefined))));
show('…while git is still counting the changes', changesWaitWords(chRow, chState('unstaged', { counting: true })));
show('…and no list down the side meanwhile', changesShelfHTML(chRow, chState('unstaged', { counting: true })));
print('-- the changes inline, each file\'s head with Open in Editor');
state.editors = { apps: [{ id: 'com.microsoft.VSCode', name: 'Visual Studio Code' }] };
const chOpen = chState('unstaged', chUnstaged);
print(changesBodyParts(chOpen, chUnstaged).slice(0, 2).map((p) => p.html).join(''));
print('-- side by side, and the first Open in Editor asking which editor; a line new since the last view lit');
Object.assign(chOpen, { split: true, picking: 'billing/retry.py' });
chHunk.lines.push(['+', 'def later():']);
print(changesBodyParts(chOpen, chUnstaged).slice(0, 1).map((p) => p.html).join(''));
print('-- Outgoing: each commit\'s head over its files');
print(changesBodyParts(chState('outgoing', chOutgoing), chOutgoing).map((p) => p.html).join(''));
print('-- once an editor is chosen, it\'s named on the button; one file at a time');
state.editors = { apps: state.editors.apps, choice: 'com.microsoft.VSCode' };
Object.assign(chOpen, { split: false, picking: null, layout: 'one', key: 'docs/retries.md' });
print(changesBodyParts(chOpen, chUnstaged).map((p) => p.html).join(''));
state.editors = { apps: [] };

section('The folded cat (cat.js)');
const catCounts = (needs, working, idle) => ({ needs, working, idle });
show('nothing running', catPose(catCounts(0, 0, 3)));
show('no sessions at all', catPose(catCounts(0, 0, 0)));
show('two working', catPose(catCounts(0, 2, 1)));
show('one needs your input while two work', catPose(catCounts(1, 2, 1)));
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

section('The chats beside the folded cat (chats.js)');
// Which come out and when is notifications' (modules/notifications/tests/page-cases.js); here, their time and their
// places beside the cat.
const chatsOut = ['d', 'c', 'b'].map((sid) => ({ sid, news: 'ask:1', left: CHAT_MS, kept: false }));
show('their time runs, but not for one that\'s held',
     chatsTick(chatsOut, 1000, (c) => c.sid === 'c').out.map((c) => `${c.sid} ${c.left}`));
show('…and once one\'s time has run out, it goes back',
     chatsTick(chatsOut, CHAT_MS, (c) => c.sid !== 'd').expired.map((c) => c.sid));
show('how many chats fit, 160 and 220 tall, in 600, 300 and 100 points (the first always)',
     [600, 300, 100].map((tall) => chatsFit([160, 220], tall)));
const catAt = { x: 45, y: 23 };
show('where they go, two of them 160 and 120 tall, 340 across, with the pill 22 tall: left and down',
     chatsLayout([160, 120], { right: false, up: false }, 340, catAt, 22));
show('…right and up, from a cat low on the screen\'s left half',
     chatsLayout([160, 120], { right: true, up: true }, 340, catAt, 22));
{
  // Three were laid out 100, 80 and 100 tall; then the middle one grows to 130 while you hold one.
  const down = { right: false, up: false }, up = { right: true, up: true }, heights = [100, 130, 100];
  const keptAt = (way) => chatsLayout([100, 80, 100], way, 340, catAt, 22).chats.map((p, i) => ({ ...p,
    tall: [100, 80, 100][i] }));
  show('held, the middle one of three grows: the one after it moves on so as not to cover it, down…',
       chatsKept(chatsLayout(heights, down, 340, catAt, 22), keptAt(down), heights, down, 22));
  show('…and up, each keeping its end nearest the cat', chatsKept(chatsLayout(heights, up, 340, catAt, 22),
       keptAt(up), heights, up, 22));
  const gone = keptAt(down);
  gone[0] = null;
  show('pointing at the last, the first one gone: the rest stay where they were, a gap left where it went',
       chatsKept(chatsLayout([80, 100], down, 340, catAt, 22), gone.slice(1), [80, 100], down, 22));
  // Three were laid out 100, 130 and 100 tall; then the middle one shrinks to 80, or goes.
  const tallAt = (way) => chatsLayout([100, 130, 100], way, 340, catAt, 22).chats.map((p, i) => ({ ...p,
    tall: [100, 130, 100][i] }));
  const shrunk = [100, 80, 100], onMiddle = (way) => [...tallAt(way).slice(0, 2), null];
  show('pointing at the middle one as it shrinks: it keeps its top, and the one after it moves up to it, down…',
       chatsKept(chatsLayout(shrunk, down, 340, catAt, 22), onMiddle(down), shrunk, down, 22));
  show('…and up, each keeping its end nearest the cat', chatsKept(chatsLayout(shrunk, up, 340, catAt, 22),
       onMiddle(up), shrunk, up, 22));
  show('pointing at the first, the middle one gone: the last moves up to it',
       chatsKept(chatsLayout([100, 100], down, 340, catAt, 22), [tallAt(down)[0], null], [100, 100], down, 22));
  show('none kept, the middle one shrinks: they close up as the layout has them',
       chatsKept(chatsLayout(shrunk, down, 340, catAt, 22), [null, null, null], shrunk, down, 22));
}
{
  // You answer a question on the first of two chats and leave the pointer where you pressed. The question goes, the
  // chat shrinks, and the second closes up under the pointer: while it moves it isn't held, so it closes up all the
  // way rather than keep its place with a gap above it; once it has stopped there, it's the one you read next, and
  // holds their time as if you'd pointed at it, but not its place, so it goes on closing up as the first shrinks
  // again. Moving the pointer onto it while it's still closing up holds their time too, but it keeps no place till it
  // has stopped, so it doesn't stop short with a gap above it. Each line is what holds their time (chatsOn), then the
  // chat keeping its place (chatKeptTo).
  const sids = ['first', 'second'];
  const under = { first: true }, savedPointer = state.pointer;
  const saved = { pointSeen: state.chats.pointSeen, pointedSid: state.chats.pointedSid,
                  pointLanded: state.chats.pointLanded, pointPassing: state.chats.pointPassing, out: state.chats.out };
  state.chats.out = sids.map((sid) => ({ sid }));
  const realUnder = document.elementFromPoint;
  document.elementFromPoint = () => {
    const sid = sids.find((s) => under[s]);
    return sid ? { closest: () => ({ dataset: { chat: sid } }) } : null;
  };
  // The second's frame, moving to its place while `moving`.
  let moving = false;
  chatFrames.set('second', { el: { getAnimations: () => (moving ? [{ playState: 'running' }] : []) },
                             row: { getAnimations: () => [] } });
  const look = (x, y) => { state.pointer = { x, y }; return [chatsOn(), chatKeptTo()]; };
  Object.assign(state.chats, { pointSeen: null, pointedSid: undefined, pointLanded: false, pointPassing: false });
  show('the pointer comes onto the first chat', look(100, 200));
  show('…and rests on it', look(100, 200));
  delete under.first;
  under.second = true;
  moving = true;
  show('closed up under a still pointer: not held while it moves…', look(100, 200));
  show('…nor as it goes on moving', look(100, 200));
  moving = false;
  show('…held once it\'s still, keeping no place', look(100, 200));
  show('…and while the pointer rests on it', look(100, 200));
  delete under.second;
  show('the pointer moves off the chats', look(100, 400));
  under.second = true;
  moving = true;
  show('moving the pointer onto one still moving points at it at once, holding their time but keeping no place, so it '
       + 'finishes closing up', look(100, 200));
  show('…nor while the pointer rests on it as it goes on moving', look(100, 200));
  moving = false;
  show('…and once it has stopped, it keeps its place', look(100, 200));
  moving = true;
  show('…which it goes on keeping if it moves again under the pointer resting on it', look(100, 200));
  // The first easing smaller as the pointer comes onto the second, which hasn't moved yet.
  let easing = false;
  chatFrames.set('first', { el: { getAnimations: () => [] },
                            row: { getAnimations: () => (easing ? [{ playState: 'running' }] : []) } });
  moving = false;
  delete under.second;
  look(100, 400);
  easing = true;
  under.second = true;
  show('the pointer comes onto the second as the first shrinks, before it has moved: held, keeping no place',
       look(100, 210));
  easing = false;
  moving = true;
  show('…nor as it closes up after the first', look(100, 210));
  moving = false;
  show('…keeping its place once it has got there', look(100, 210));
  chatFrames.delete('first');
  chatFrames.delete('second');
  state.pointer = savedPointer;
  document.elementFromPoint = realUnder;
  Object.assign(state.chats, saved);
}
show('where a chat starts as it comes out: the first from under the cat, left of it then right of it; one with '
     + 'another nearer the cat, in its own place, a little lower, to lift into it, down and up',
     [chatComesFrom({ x: 0, y: 23 }, true, { right: false }), chatComesFrom({ x: 0, y: 23 }, true, { right: true }),
      chatComesFrom({ x: 0, y: 150 }, false, { right: false }),
      chatComesFrom({ x: 0, y: 150, tall: 120 }, false, { right: true, up: true })]);
show('how long it waits: till the last of those moving lands, or the one going has faded; none once they have',
     [chatComesAfter([420, 0], 0), chatComesAfter([0, 200], 0), chatComesAfter([420, 200], 500),
      chatComesAfter([], 0)]);
{
  // Chats coming out beside the cat, on a fake clock. Each line is what's drawn by then: every place each chat is put,
  // in order (a chat coming out is put where it starts, then where it goes, at once, and eases between them), and
  // whether it shows, hidden while it waits, and whether it can be pointed at or pressed.
  const realNow = Date.now, realTimeout = setTimeout, realClear = clearTimeout, wasCalm = calm.matches;
  const wasWay = state.cat.way, wasFaded = state.chats.fadedAt;
  let clock = 0;
  const timers = [];
  Date.now = () => clock;
  setTimeout = (fn, ms) => timers.push({ fn, at: clock + ms });
  clearTimeout = (id) => { if (timers[id - 1]) timers[id - 1].fn = null; };
  const runTo = (ms) => {
    clock = ms;
    for (const timer of timers) if (timer.fn && timer.at <= ms) { const fn = timer.fn; timer.fn = null; fn(); }
  };
  const put = {};
  const frameAt = (sid, placed) => {
    put[sid] = [];
    const style = new Proxy({}, { set(o, k, v) { if (k === 'transform') put[sid].push(v); o[k] = v; return true; } });
    const on = new Set();
    const classList = { add: (c) => on.add(c), remove: (c) => on.delete(c),
                        toggle: (c, yes) => (yes ? on.add(c) : on.delete(c)) };
    return { el: { style, classList }, placed, tucked: false, coming: false, comeTimer: 0, first: true, landsAt: 0 };
  };
  const drawn = (frames) => Object.fromEntries(Object.entries(frames).map(([sid, f]) => [sid,
    `${put[sid].join(' → ') || 'not put'}; ${f.el.style.opacity === '1' ? 'shows' : 'hidden'}`
    + (chatShown(f) ? '' : ', not pointed at')]));
  const settle = (frames) => { for (const sid of Object.keys(frames)) put[sid] = []; };
  calm.matches = false;
  state.cat.way = { right: false, up: false };

  // One goes back into the cat at 0, fading till 200; once it has, the one after it moves up into its place, and once
  // that has landed, the next waiting comes out after it.
  let frames = { second: frameAt('second', { x: 0, y: 200 }), third: frameAt('third', null) };
  state.chats.fadedAt = 200;
  moveChats([{ frame: frames.second, to: { x: 0, y: 23 }, fresh: false, i: 0 },
             { frame: frames.third, to: { x: 0, y: 150 }, fresh: true, i: 1 }], [{ x: 0, y: 23 }, { x: 0, y: 150 }],
            false);
  show('one swaps in: as the one nearest the cat fades back into it, the one after it stays where it is, and the new '
       + 'one waits, hidden', drawn(frames));
  clock = 7;
  moveChats([{ frame: frames.second, to: { x: 0, y: 23 }, fresh: false, i: 0 },
             { frame: frames.third, to: { x: 0, y: 150 }, fresh: false, i: 1 }], [{ x: 0, y: 23 }, { x: 0, y: 150 }],
            false);
  show('…laid out again a moment on, before it has come out: it goes on waiting, for the one after it to land too',
       drawn(frames));
  runTo(199);
  show('…till it has faded', drawn(frames));
  runTo(200);
  show('…then the one after it moves up into its place', drawn(frames));
  settle(frames);
  runTo(619);
  show('…the new one still waiting as it eases in', drawn(frames));
  runTo(620);
  show('…which has landed: it comes out in its own place, lifting into it as it fades in', drawn(frames));

  // The first out, nearest the cat, with nothing moving: from under the cat, at once.
  clock = 1000;
  frames = { only: frameAt('only', null) };
  state.chats.fadedAt = 0;
  moveChats([{ frame: frames.only, to: { x: 0, y: 23 }, fresh: true, i: 0 }], [{ x: 0, y: 23 }], false);
  show('the first, with nothing moving: it slides out from under the cat at once', drawn(frames));

  // A new request comes out nearest the cat, the two out moving down for it: it slides out once they have.
  clock = 2000;
  frames = { newest: frameAt('newest', null), older: frameAt('older', { x: 0, y: 23 }),
             oldest: frameAt('oldest', { x: 0, y: 150 }) };
  moveChats([{ frame: frames.newest, to: { x: 0, y: 23 }, fresh: true, i: 0 },
             { frame: frames.older, to: { x: 0, y: 130 }, fresh: false, i: 1 },
             { frame: frames.oldest, to: { x: 0, y: 257 }, fresh: false, i: 2 }],
            [{ x: 0, y: 23 }, { x: 0, y: 130 }, { x: 0, y: 257 }], false);
  show('a new first, the others moving down for it: it waits, hidden', drawn(frames));
  settle(frames);
  runTo(2420);
  show('…and slides out from under the cat once they have landed', drawn(frames));

  // Up from a cat low on the screen: the one after the cat's has a foot nearest it, and lifts into its place too.
  clock = 3000;
  state.cat.way = { right: true, up: true };
  frames = { below: frameAt('below', { x: 0, y: 400, tall: 100 }), above: frameAt('above', null) };
  moveChats([{ frame: frames.below, to: { x: 0, y: 300, tall: 100 }, fresh: false, i: 0 },
             { frame: frames.above, to: { x: 0, y: 190, tall: 100 }, fresh: true, i: 1 }],
            [{ x: 0, y: 300, tall: 100 }, { x: 0, y: 190, tall: 100 }], false);
  settle(frames);
  runTo(3420);
  show('up from the cat: the one coming out after the first lifts into its own place too', drawn(frames));

  // One shrinking 40 points, the one after it riding its foot up, on the row's own curve and clock: put where it goes
  // at once, without sliding there, and drawn on its way from where the row has got to, landing with it; and one coming
  // out after them waits till then. The row's easing is 16 ms on, of its 1000.
  show('each keyframe of a row shrinking 40 points puts those after it that much lower, down from the cat, or that '
       + 'much higher, up from it', [chatRideFrames([{ offset: 0, height: 140, easing: 'ease-out' }, { offset: 1,
         height: 100 }], 100, 1), chatRideFrames([{ offset: 0, height: 140 }, { offset: 1, height: 100 }], 100, -1)]);
  clock = 5000;
  const rideOf = (sid) => {
    const frame = frameAt(sid, sid === 'rider' ? { x: 0, y: 160 } : sid === 'shrinking' ? { x: 0, y: 23 } : null);
    frame.el.getAnimations = () => [];
    frame.el.animate = (keys, timing) => {
      put[sid].push(`rides ${keys[0].transform} → ${keys[keys.length - 1].transform} (${timing.duration} ms)`);
      return { playState: 'running', startTime: null, currentTime: 0, cancel() {}, commitStyles() {} };
    };
    return frame;
  };
  frames = { shrinking: rideOf('shrinking'), rider: rideOf('rider'), next: rideOf('next') };
  state.cat.way = { right: false, up: false };
  const ride = { i: 0, ease: { startTime: 4984, currentTime: 16, effect: { getTiming: () => ({ duration: 1000,
                 easing: 'linear' }) } }, keys: [{ offset: 0, height: 140 }, { offset: 1, height: 100 }], end: 100,
                 sign: 1, left: 984 };
  moveChats([{ frame: frames.shrinking, to: { x: 0, y: 23 }, fresh: false, i: 0 },
             { frame: frames.rider, to: { x: 0, y: 120 }, fresh: false, i: 1 },
             { frame: frames.next, to: { x: 0, y: 220 }, fresh: true, i: 2 }],
            [{ x: 0, y: 23 }, { x: 0, y: 120 }, { x: 0, y: 220 }], false, ride);
  show('one shrinking: the one after it rides its foot up, put where it goes and drawn from 40 points lower, and the '
       + 'one coming out waits', drawn(frames));
  show('…the rider on the row\'s own clock, landing with it', [frames.rider.ride.startTime, frames.rider.landsAt]);
  settle(frames);
  runTo(5983);
  show('…still waiting a moment before the ride lands', drawn(frames));
  runTo(5984);
  show('…and coming out once it has', drawn(frames));
  calm.matches = true;
  show('under reduced motion nothing rides: the row just ends', chatRide([{ sid: 'shrinking' }]));
  calm.matches = false;
  chatFrames.set('one', { row: { getAnimations: () => [{ playState: 'running' }] } });
  chatFrames.set('two', { row: { getAnimations: () => [{ playState: 'running' }] } });
  show('nor while two of them ease at once: they close up once each has stopped', chatRide([{ sid: 'one' },
                                                                                            { sid: 'two' }]));
  chatFrames.delete('one');
  chatFrames.delete('two');
  let stopped = '';
  const riding = { el: { style: {} }, ride: { playState: 'running', commitStyles: () => { stopped += 'left where it '
    + 'is, '; }, cancel: () => { stopped += 'stopped'; } } };
  riding.ride = chatRideStop(riding.el, riding.ride);
  show('a ride stopped part-way (the chat goes, or moves on): left where it has got to', [stopped, riding.ride]);

  // Reduced motion: nothing slides, so nothing waits; it fades in where it goes.
  calm.matches = true;
  clock = 4000;
  frames = { moved: frameAt('moved', { x: 0, y: 200 }), fresh: frameAt('fresh', null) };
  moveChats([{ frame: frames.moved, to: { x: 0, y: 23 }, fresh: false, i: 0 },
             { frame: frames.fresh, to: { x: 0, y: 150 }, fresh: true, i: 1 }], [{ x: 0, y: 23 }, { x: 0, y: 150 }],
            false);
  show('under reduced motion, one coming out as another moves comes out at once', drawn(frames));

  Date.now = realNow;
  setTimeout = realTimeout;
  clearTimeout = realClear;
  calm.matches = wasCalm;
  state.cat.way = wasWay;
  state.chats.fadedAt = wasFaded;
}

section('The folded cat\'s list, while it\'s pointed at (peek.js)');
show('what its head says', [peekTitle(0), peekTitle(1), peekTitle(4)]);
{
  // Flicked off the screen's edge, a panel open from pointing is kept open, so it never folds while it's away. The
  // chats beside the cat aren't drawn here.
  const sent = [], draw = drawChats;
  drawChats = () => {};
  window.webkit = { messageHandlers: { panel: { postMessage: (msg) => sent.push(msg.type) } } };
  state.peek.open = true;
  flickedAway();
  show('flicked away with its list out: whether the list is still out on pointing, and what the app is told',
       { out: state.peek.open, sent });
  sent.length = 0;
  flickedAway();
  show('…flicked away again, open for good now: what the app is told', sent);
  delete window.webkit;
  drawChats = draw;
}

section('The header, pushed away by the held row (header.js)');
show('scrolled down 20 points with the row you\'re on in view, or still folding at the top: it stays',
     headerAfterScroll(0, 20, 300, 0));
show('…the row\'s copy 12 points past where it has folded all it can after a 20-point scroll: 12 points of it gone',
     headerAfterScroll(0, 20, 300, 12));
show('…down 300 more, the copy as far past: all of it gone, and no further', headerAfterScroll(12, 300, 600, 300));
show('the copy far past already (the list moved the row there), a 5-point scroll: 5 points further, no more',
     headerAfterScroll(10, 5, 400, 200));
show('back up 10 from far down the list: still all gone', headerAfterScroll(HEADER_TALL, -10, 310, 0));
show('…part-way, and back up 40: as far gone as it was', headerAfterScroll(20, -40, 300, 0));
show('…back up 32 to 8 points from the very top: only as far gone as the list has scrolled',
     headerAfterScroll(HEADER_TALL, -32, 8, 0));
show('gone: once all of it has (within half a point), and until it has come back 6 points',
     [[46.4, false], [46.6, false], [44, true], [41.5, true], [40.9, true]].map(([off, was]) => headerGone(off, was)));
const mayGo = { folded: false, reading: false, carded: false, room: 300 };
show('it may be pushed away in a list that scrolls; not folded, with the reader open, with a card under it, nor with '
     + 'a list a point or less from scrolling',
     [mayGo, { ...mayGo, folded: true }, { ...mayGo, reading: true }, { ...mayGo, carded: true },
      { ...mayGo, room: 1 }, { ...mayGo, room: 1.5 }].map(headerMayGo));
const nameO = { left: 40, top: 15, width: 10, height: 10 }, rootAt = { left: 0, top: 0 };
show('the folded cat\'s place from the name\'s o, with the header all there, and with it slid 47 points away (the o '
     + '47 points up): the same', [catPlaceFrom(nameO, rootAt, 0),
                                   catPlaceFrom({ ...nameO, top: nameO.top - 47 }, rootAt, 47)]);

section('A row\'s details, whole');
// Each as a row draws it, under its lines (detailsBlock), so the whole of it can be drawn.
print(detailsBlock('twice:o1', twiceCardHTML(twice)));
print(detailsBlock('place:s', placeCardHTML(session({ git: { branch: 'f', root: '/work/app-f', worktree: 'app-f',
  worktreeOf: 'app', mainRoot: '/work/app' } }))));
print(detailsBlock('pr:https://github.com/e/app/pull/7', prCardHTML({ url: 'https://github.com/e/app/pull/7', number: 7,
  state: 'OPEN', isDraft: false, title: 'Retry failed payments with backoff', repo: 'e/app', additions: 120,
  deletions: 31, changedFiles: 4 })));
state.last = { sessions: [noPR], now: NOW };
setPRBranches('w3', { base: 'main', branches: ['develop', 'f', 'main'] });
state.prPicking = 'w3';
print(detailsBlock('pr-create:w3', createPRCardHTML(noPR, stepsOf(noPR, true))));
Object.assign(state, { prPicking: null, prInto: {}, prBranches: {} });
print(detailsBlock('changes:ch', changesCardHTML(chRow)));
const manyPRs = session({ sessionId: 'm1', prs: [7, 8, 9, 10, 11].map((n) => ({ url: `https://github.com/e/app/pull/${n}`,
  number: n, state: 'OPEN', title: `Change ${n}`, repo: 'e/app' })) });
print('-- "+2 more open": the row\'s line, and its details, each PR pressed as the row\'s are');
print(prsHTML(manyPRs).match(/<div class="pr more"[^>]*>[^<]*<\/div>/)[0]);
print(detailsBlock('pr-more:m1', morePRsHTML(manyPRs)));
print('-- a long name beside "Open twice": the name shortens (its style), the words never do');
print(rowHTML(session({ sessionId: 'o9', name: 'a session with a very long name that runs past the title line',
  alsoOpen: [{ entrypoint: 'cli', paused: false }] }), 'idle', NOW).match(/<div class="line1">[\s\S]*?<\/div>/)[0]);

section('A long title in a row\'s details (detailsTitle)');
const titled = (t) => JSON.stringify(detailsTitle(t));
show('short: all bold', [titled('Search box'), titled('Make the checkout page open at once')]);
show('a head before a colon or a dash near the start: bold, the rest in the body\'s weight',
     [titled('Row details: open inside the row, never over the list'),
      titled('Row details — open inside the row, never over the list')]);
show('no colon or dash near the start, and long: all in the body\'s weight, never split mid-phrase',
     [titled('Let the list of sessions grow by adding a bigger folder of its own each time'),
      titled('Try the dark theme at night, and say if it\'s easy to read'),
      titled('Fix the gap. Close it as the details fold, every time'),
      titled('Make every row of the list say who it waits on: you or the agent')]);
show('clipped mid-word where it was read (200 characters): cut at a word well before, with "…"',
     titled(('Grouped list: let the list grow by adding a bit more each time a member joins the team, and keep its '
       + 'headers where they were, so nothing moves under the pointer while you read it, and grow by adding a bigger '
       + 'room').slice(0, 200)));
show('long and with no break, cut at a word', titled(('Let the list of sessions grow by adding a bigger folder of its '
  + 'own each time a member joins the team, and keep the headers where they were while you read').slice(0, 200)));
show('a word longer than the head: never cut inside it',
     [titled('Supercalifragilisticexpialidociousnessesqueness'),
      titled('Supercalifragilisticexpialidociousnessesqueness and more')]);
show('as the details draw it, escaped', [detailsTitleHTML('A <b>bold</b> idea: one & two'),
     detailsTitleHTML('Try the dark theme at night, and say if it\'s easy to read')]);

section('What a row\'s details do as the pointer moves (detailsNext)');
const step = (how) => JSON.stringify(detailsNext(how));
const open = { key: 'pr:7' };
show('resting on something with details: they wait, then open', [step({ at: 'pr:7' }), step({ at: 'pr:7', rested: true })]);
show('the pointer on their row, or in them: they stay', step({ open, at: 'pr:7', on: true, onList: true }));
show('another thing in the same row, rested on: what\'s open changes in place',
     step({ open, at: 'place:s', on: true, onList: true, rested: true }));
show('off the row upward, or off the list: they fold', [step({ open, onList: true }), step({ open })]);
show('off the row downward: they fold holding the row under the pointer, the list scrolling back as far as it can and '
     + 'the rows closing up for the rest (near its top), never leaving an empty room',
     step({ open, onList: true, below: true }));
show('your own scroll takes the row from under the pointer: they fold', step({ open, onList: true, below: true,
     yours: true }));
show('opened at the foot: the list eases up to show them, the pointer off the row meanwhile: still open',
     step({ open, onList: true, below: true, moving: true }));
show('a reply moves the rows (the list moving by itself): still open', step({ open, onList: true, moving: true }));
show('what\'s open goes away by itself (the PR merged, the other copy ended, the job moved on): they fold, opening '
     + 'nothing else', step({ open, on: true, onList: true, gone: true }));

section('The list drawn again only when it changes');
// A second on, each sample row draws the same but for its clocks (and where its endless animations have got to), so
// the list only ticks its clocks rather than being rebuilt.
const onAt = (t, ms) => {
  performance.now = () => t;
  return rows.map(([, s]) => rowHTML(s, classify(s, ms, view()), ms));
};
const drawnNow = onAt(0, NOW), drawnLater = onAt(1234, NOW + 61000);
performance.now = () => 0;
show('a minute on, rows whose HTML changed',
     rows.filter((r, i) => drawnNow[i] !== drawnLater[i]).map(([name]) => name));
show('…and whose drawing did (none)',
     rows.filter((r, i) => drawingOf(drawnNow[i]) !== drawingOf(drawnLater[i])).map(([name]) => name));
const busyRow = rows.find(([name]) => name === 'working')[1];
show('a step that changes what it does: drawn again', drawingOf(rowHTML(busyRow, 'busy', NOW))
     !== drawingOf(rowHTML({ ...busyRow, activity: 'Read the logs' }, 'busy', NOW)));
// The clocks, ticked where they're drawn: only those whose text changes are written.
const clock = (data, text) => ({ dataset: data, textContent: text });
const clocks = [clock({ since: String(min(2)) }, '2m 0s'), clock({ ago: String(min(5)) }, '5m'),
                clock({ ago: String(NOW - 4000) }, 'now'), clock({ left: String(NOW + 5 * 60000) }, '5m')];
const written = [];
clocks.forEach((c) => {
  let text = c.textContent;
  Object.defineProperty(c, 'textContent', { get: () => text, set: (t) => { written.push(t); text = t; } });
});
// And a ring counting down 5 minutes from now, its fill (--left) set as the time goes.
const style = { left: '1.000', getPropertyValue: () => style.left, setProperty: (_, v) => { style.left = v; } };
const ring = { dataset: { until: String(NOW + 5 * 60000), span: '300000' }, style };
const clocksIn = { querySelectorAll: (sel) => [...clocks, ring].filter((c) => /^\[data-(\w+)\]$/.exec(sel)[1]
                                                                     in c.dataset) };
tickTimes(clocksIn, NOW + 75000);
show('ticked 75s on: each clock\'s text, and those written', [clocks.map((c) => c.textContent), written]);
show('…and the ring\'s fill', style.left);

section('The list drawn only while the panel can be seen');
show('hidden (or the screen asleep): not drawn, whatever else',
     [listDrawing({ shown: false, stale: false, same: false }),
      listDrawing({ shown: false, stale: true, same: true })]);
show('seen again after that: drawn afresh, without moving, even if it would draw the same',
     [listDrawing({ shown: true, stale: true, same: false }), listDrawing({ shown: true, stale: true, same: true })]);
show('seen, the same as last time but for its clocks: only they are set', listDrawing({ shown: true, stale: false,
                                                                                         same: true }));
show('seen, something else changed: rebuilt, with its motion', listDrawing({ shown: true, stale: false, same: false }));

section('The list fills a taller panel');
show('what the panel asks for, its content 725pt with the list 640pt in it at its usual limit; the list filling a '
     + 'panel 200pt taller (840pt, the content then 925pt); a short list (300pt, the content 385pt): the same as with no '
     + 'filling', [panelAsks(725, 640, 640), panelAsks(925, 840, 640), panelAsks(385, 300, 640)]);
show('how far past its limit the list goes: the panel 925pt from the list down, its content asking 725pt; the panel '
     + 'just as tall as it asks; something hanging below the list (kept as it is, so nothing moves under it); folded',
     [listFill(925, 725, 0, false), listFill(725, 725, 0, false), listFill(925, 725, 900, false),
      listFill(925, 725, 0, true)]);

section('A request drawn in two places: which copy has the keys (keyboard.js)');
{
  // Just enough of a request's card on its row for the keyboard part: the copy's place, its main button (counting
  // its presses), its edge, and the chat it's out in, if any. A press lands on the card, or on one of its buttons.
  const requestKeys = core.keyCards.find((k) => k.card.startsWith('.perm[data-ask]'));
  const copy = (where, { row = { dataset: { id: 's1' } }, chat = null } = {}) => {
    const edge = new Set(), allow = { presses: 0, dispatchEvent() { allow.presses++; } };
    const card = {
      where, dataset: { ask: 'twice' }, allow,
      classList: { add: (c) => edge.add(c), remove: (c) => edge.delete(c), contains: (c) => edge.has(c) },
      closest: (sel) => (sel === '.row[data-id]' ? row : sel === '.chat' ? chat : sel === requestKeys.card ? card
                                                                                                         : null),
      querySelector: (sel) => (sel === '.perm-allow' ? allow : null),
    };
    return card;
  };
  const on = (card, button = null) => ({ closest: (sel) => (sel === 'button' ? button : card.closest(sel)) });
  const placeOf = (cards) => ({
    contains: (c) => cards.includes(c),
    querySelectorAll: (sel) => cards.filter((c) => (sel === '.has-keys' ? c.classList.contains('has-keys')
                                                                      : sel === requestKeys.card)),
  });
  const inList = copy('the list'), beside = copy('beside the list');
  const inChat = copy('a chat beside the folded panel', { chat: { dataset: { chat: 's1' } } });
  const besidePlace = placeOf([beside]);
  const was = { list: { contains: list.contains, querySelectorAll: list.querySelectorAll },
                chats: { contains: chatsEl.contains, querySelectorAll: chatsEl.querySelectorAll }, last: state.last };
  Object.assign(list, placeOf([inList]));
  Object.assign(chatsEl, placeOf([inChat]));
  core.keyPlaces.push(besidePlace);
  const ask = { id: 'twice', tool: 'Bash', input: { command: 'ls' } };
  state.last = { sessions: [session({ sessionId: 's1', ask })] };
  globalThis.MouseEvent ??= class { constructor(type, init) { Object.assign(this, init, { type }); } };
  const press = (target) => { state.keyCard = keyCardPressed(target); showHeldCard(); };
  const key = (k) => keyOnHeldCard({ key: k, target: { closest: () => null }, preventDefault() {} });
  const copies = [inList, beside, inChat];
  const edges = () => copies.filter((c) => c.classList.contains('has-keys')).map((c) => c.where);
  const presses = () => copies.map((c) => c.allow.presses);
  const answered = (then) => { state.answering.twice = true; then(); delete state.answering.twice; };

  press(on(inList));
  show('pressed in the list: the copy with the keys, and the copies showing it', [heldCard()?.where, edges()]);
  press(on(beside));
  show('then pressed beside the list: that copy has them, and the list\'s is let go', [heldCard()?.where, edges()]);
  key('Enter');
  show('Return there: the main button pressed on that copy only (list, beside, chat)', presses());
  answered(() => {
    key('Enter');
    showHeldCard();
    show('once it\'s answered: no copy has the keys, and Return does nothing more',
         [heldCard(), state.keyCard, edges(), presses()]);
  });

  // The same request out in a chat beside the folded panel (chats.js's place), its frame as the chats keep it.
  const frame = { placed: { x: 0, y: 0 }, tucked: false, flying: false, shownAt: Date.now() };
  chatFrames.set('s1', frame);
  press(on(inChat));
  show('pressed in a chat only just come out or moved up: no keys', state.keyCard);
  frame.shownAt = 0;
  press(on(inChat));
  show('pressed in it once it has stayed a moment: that copy has the keys, and no other shows them',
       [heldCard()?.where, edges()]);
  show('…which holds the chat out, as typing in it does', chatsOn());
  key('Enter');
  show('Return there: the main button pressed on the chat\'s copy only (list, beside, chat)', presses());
  answered(() => show('once it\'s answered: let go', [heldCard(), state.keyCard]));
  const goes = [
    ['tucked in while the folded panel is dragged', () => { frame.tucked = true; }, () => { frame.tucked = false; }],
    ['landing into its row as the panel opens', () => { frame.flying = true; }, () => { frame.flying = false; }],
    ['going back in', () => chatFrames.delete('s1'), () => chatFrames.set('s1', frame)],
  ];
  for (const [how, set, unset] of goes) {
    press(on(inChat));
    const had = heldCard()?.where;
    set();
    show(`held in a chat, then the chat ${how}: let go`, [had, heldCard(), state.keyCard]);
    unset();
  }
  chatFrames.delete('s1');

  press(on(beside, { disabled: false, matches: () => false }));  // Allow once, say
  show('pressed on a button that answers it: no keys', state.keyCard);
  press(on(copy('the row\'s copy held at the list\'s edge', { row: null })));
  show('pressed on the copy of a row held at the list\'s edge: no keys', state.keyCard);
  press(on(beside));
  core.keyPlaces.splice(core.keyPlaces.indexOf(besidePlace), 1);
  show('held beside the list, and that place goes: let go', [heldCard(), state.keyCard]);

  Object.assign(list, was.list);
  Object.assign(chatsEl, was.chats);
  state.last = was.last;
}

section('Esc in a card\'s box (core.escapes, input.js)');
// What the list does with keys, on a stand-in element that keeps the handlers it's given; then Esc in a box: the
// first entry whose selector the box matches takes it, nothing else does; with none matching, or while composing, no
// entry is asked.
{
  const handlers = [], heard = [];
  takesPresses({ addEventListener: (type, handler) => { if (type === 'keydown') handlers.push(handler); } });
  const box = (classes) => ({ closest: () => true, matches: (sel) => sel.split(',').some((s) => classes.includes(s.trim())) });
  const esc = (target, extra = {}) => {
    const e = { key: 'Escape', target, isComposing: false, keyCode: 27, prevented: false, stopped: false,
                preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }, ...extra };
    handlers.forEach((h) => h(e));
    return e;
  };
  const was = core.escapes.slice();
  core.escapes.length = 0;
  core.escapes.push(['.mine', () => heard.push('mine')], ['.mine', () => heard.push('second')], ['.theirs',
    () => heard.push('theirs')]);
  const taken = esc(box(['.mine']));
  show('Esc in a box an entry names: that one, and only it, takes it', [heard.join(' '), taken.prevented, taken.stopped]);
  heard.length = 0;
  const left = esc(box(['.other']));
  show('…in a box none names: none asked, and Esc goes on as before', [heard.length, left.prevented]);
  esc(box(['.mine']), { isComposing: true });
  show('…while composing: none asked', heard.length);
  core.escapes.length = 0;
  core.escapes.push(...was);
}

section('Esc closes the view beside the list (keyboard.js)');
// The view beside the list open (the reader, One Task), and the keys pressed on the panel with it: a press in it gives
// the panel the keyboard, Esc closes it, as its ✕ does, unless something there takes Esc first, and the keyboard goes
// back as it closes. Each Esc is heard by the card that has the keys, then by the view, as the page's listeners are.
{
  const sent = [], draw = render, contains = reader.contains;
  render = () => {};
  window.webkit = { messageHandlers: { panel: { postMessage: (msg) => sent.push(msg.type) } } };
  reader.contains = (target) => !!target.inView;
  const inView = { inView: true, closest: () => null };
  const onClose = { inView: true, closest: (sel) => (sel === '.r-close' ? {} : null) };
  const onTag = { closest: () => null };
  const box = (value) => ({ inView: true, value, blurred: false, blur() { this.blurred = true; },
                            closest(sel) { return sel === textBoxes() ? this : null; } });
  const esc = (target, extra = {}) => {
    const e = { key: 'Escape', target, isComposing: false, keyCode: 27, defaultPrevented: false,
                preventDefault() { this.defaultPrevented = true; }, ...extra };
    keyOnHeldCard(e);
    escClosesView(e);
    return e.defaultPrevented;
  };
  const open = () => {
    sent.length = 0;
    state.reading = { mode: 'oneTask', sessionId: null };
    state.viewKeys = null;
    state.keyCard = null;
  };
  const press = (target) => { state.viewKeys = viewPressed(target); };
  const closing = () => !!state.reading?.closing;

  open();
  press(onTag);
  show('opened by a row\'s tag: the view has no keys', [!!state.viewKeys, keepsKeyboard()]);
  press(onClose);
  show('pressed on its ✕: no keys, as the ✕ closes it', !!state.viewKeys);
  press(inView);
  show('pressed in it: the view has the keys', [viewHasKeys(), keepsKeyboard()]);
  show('Esc there: taken, the view closes, and its keys go with it',
       [esc(inView), closing(), sent, viewHasKeys(), keepsKeyboard()]);

  open();
  press(inView);
  const was = state.reading;
  state.reading = { mode: 'writings', sessionId: 's' };
  show('a view opened since, by a tag or the pawn menu: none of the last one\'s keys',
       [viewHasKeys(), keepsKeyboard()]);
  state.reading = was;
  press(inView);
  was.mode = 'writings';
  was.sessionId = 's';
  show('…or the view turned to another session\'s page: none either', [viewHasKeys(), keepsKeyboard()]);
  Object.assign(was, { mode: 'oneTask', sessionId: null });
  esc(inView, { isComposing: true });
  show('Esc while composing: the input method\'s, and the view stays', closing());
  esc(inView, { metaKey: true });
  show('⌘Esc: the view stays', closing());

  open();
  const words = box('Ship it on Friday');
  press(words);
  show('Esc in a box with words typed: the box is left, its words kept, and the view keeps its keys',
       [esc(words), words.blurred, words.value, closing(), viewHasKeys(), keepsKeyboard()]);
  show('…then Esc again: the view closes', [esc(inView), closing()]);
  open();
  const blank = box('  ');
  show('Esc in an empty box: the view closes in one press, the box let go of', [esc(blank), closing(), blank.blurred]);

  // Keys typed as if back in the app you were in, after a press in the view: taken before anything hears them, so the
  // focus stays where it is, and no button is pressed nor anything sent.
  const typed = (key, target) => {
    const e = { key, target, prevented: false, stopped: false, preventDefault() { this.prevented = true; },
                stopPropagation() { this.stopped = true; } };
    viewKeyOnly(e);
    return [e.prevented, e.stopped];
  };
  const button = { inView: true, closest: () => null, tagName: 'BUTTON' };
  open();
  press(inView);
  show('pressed in it, then Tab: taken, so the focus stays where it is', typed('Tab', inView));
  show('…then Return on a button focused there: taken, so nothing is sent', typed('Enter', button));
  show('…and Space: taken', typed(' ', button));
  show('…and a letter: left alone, so it does nothing', typed('g', inView));
  show('Return in a box typed in, in the view: left to the box', typed('Enter', box('a comment')));
  press(onTag);
  show('with no keys in the view: Return left alone', typed('Enter', button));

  open();
  esc(inView, { defaultPrevented: true });
  show('Esc that a box of a module\'s own card or the new conversation\'s card took: the view stays', closing());

  // A request's card in the view, pressed: it has the keys, as a place beside the list has its cards' (heldCard).
  open();
  const card = { closest: () => ({}), classList: { add() {}, remove() {} } };
  const place = { el: { inView: true, contains: (c) => c === card, querySelectorAll: () => [card] }, open: () => true };
  const kind = { card: '.held', id: () => 'r1', open: () => true, key: () => false };
  core.keyPlaces.push(place);
  press(inView);
  state.keyCard = { kind, id: 'r1', place: place.el };
  show('a held card in the view, then Return: left to the card', typed('Enter', inView));
  show('a held card in the view, then Esc: the card lets go of its keys, and the view stays',
       [esc(inView), !!state.keyCard, closing(), viewHasKeys()]);
  show('…then Esc again: the view closes', [esc(inView), closing(), sent]);
  core.keyPlaces.splice(core.keyPlaces.indexOf(place), 1);

  open();
  press(inView);
  keyboardGone();
  show('pressed in it, then another app takes the keyboard: the view has none', [viewHasKeys(), keepsKeyboard()]);

  state.reading = null;
  state.viewKeys = null;
  render = draw;
  reader.contains = contains;
  delete window.webkit;
}

section('A question card pressed three ways: each holds the keys (keyboard.js)');
// A question on a row, got into three ways: pressed on the card, on its Type an answer option (a button that takes the
// keys), or straight into its box. Each holds the card, so Esc in the box (which gives the row back and takes the box
// away) leaves the keys on the card, and the next Esc, on the card, lets go of them. A card's other boxes, where no
// module takes Esc, hold it too, and Esc in one leaves the box, keeping what's typed, with the card still held.
{
  const sent = [], keyboardMessages = () => sent.filter((t) => t === 'keyboard on' || t === 'keyboard off');
  window.webkit = { messageHandlers: { panel: { postMessage: (msg) => sent.push(msg.type === 'keyboard'
    ? `keyboard ${msg.on ? 'on' : 'off'}` : msg.type) } } };
  const draw = render, timer = setTimeout;
  const had = { last: state.last, active: document.activeElement,
                list: { contains: list.contains, querySelectorAll: list.querySelectorAll } };
  render = () => {};
  setTimeout = (f) => { f(); return 0; };  // wantKeyboard's wait, run at once
  const questionKeys = core.keyCards.find((k) => k.card.startsWith('.perm[data-ask]'));
  const row = { dataset: { id: 'q1' } }, edge = new Set(), inCard = new Set();
  const card = {
    dataset: { ask: 'quiz1' }, matches: () => false, contains: (el) => inCard.has(el),
    classList: { add: (c) => edge.add(c), remove: (c) => edge.delete(c), contains: (c) => edge.has(c) },
    closest: (sel) => (sel === '.row[data-id]' ? row : sel === questionKeys.card ? card : sel === '.perm' ? card
                                                                                                       : null),
    querySelector: () => null,
  };
  const typeOption = { disabled: false, matches: (sel) => sel.includes('.ask-type-opt') };
  const box = { value: '', matches: (sel) => sel === '.perm.quiz .ask-row-box',
                closest: (sel) => (sel === textBoxes() ? box : sel === 'button' ? null : card.closest(sel)) };
  inCard.add(box);
  const cardPress = { closest: (sel) => (sel === 'button' ? null : card.closest(sel)) };
  const optionPress = { closest: (sel) => (sel === 'button' ? typeOption : card.closest(sel)) };
  const pageBody = { closest: () => null };  // where an Esc goes once no box has the focus
  const deployBox = { value: '', blurred: false, matches: () => false, blur() { this.blurred = true; },
                      closest: (sel) => (sel === textBoxes() ? deployBox : null) };
  Object.assign(list, { contains: (c) => c === card,
                        querySelectorAll: (sel) => (sel === questionKeys.card ? [card] : sel === '.has-keys'
                          ? [card].filter((c) => c.classList.contains('has-keys')) : []) });
  const ask = { id: 'quiz1', tool: 'AskUserQuestion', truncated: false, input: { questions: [
    { question: 'Which database?', header: 'Database', options: [{ label: 'Postgres' }, { label: 'SQLite' }] }] } };
  state.last = { sessions: [session({ sessionId: 'q1', ask })] };
  const press = (target) => {
    sent.length = 0;
    state.keyCard = null;
    state.keyboardWanted = false;
    pressTakesKeys({ button: 0, target });
    showHeldCard();
  };
  // As on the page: the list hands an Esc in a box to its module first (core.escapes, input.js), which keeps it from
  // the rest, and only an Esc no module took goes on to the panel's own (keyOnHeldCard, then escClosesView).
  const escIn = (target) => {
    const e = { key: 'Escape', target, isComposing: false, keyCode: 27, defaultPrevented: false,
                preventDefault() { this.defaultPrevented = true; } };
    const taken = target.closest(textBoxes()) && core.escapes.find(([sel]) => target.matches(sel));
    if (taken) return taken[1](target, e);
    keyOnHeldCard(e);
    escClosesView(e);
  };

  const ways = [['on the card (its row)', cardPress], ['on its Type an answer option', optionPress],
                ['straight into its box', box]];
  for (const [how, target] of ways) {
    press(target);
    show(`pressed ${how}: the card holds the keys, and shows it`,
         [heldCard() === card, state.keyCard?.id, edge.has('has-keys')]);
    show('…and the panel asks for the keyboard', [keyboardMessages(), keepsKeyboard()]);
    document.activeElement = box;  // the box has the focus, as it does once typed in
    escIn(box);
    document.activeElement = null;  // Esc gave the row back: the box is gone, and the focus with it
    wantKeyboard(false);
    show('Esc in the box (the row given back, the box no longer focused): the card still holds the keys, and the '
         + 'panel keeps the keyboard',
         [heldCard() === card, document.activeElement === box, keepsKeyboard(), keyboardMessages()]);
    escIn(cardPress);
    wantKeyboard(false);
    show('…then Esc on the card: it lets go, and the keyboard goes back',
         [state.keyCard, heldCard(), keepsKeyboard(), keyboardMessages()]);
  }

  // The card's other boxes, where no module takes Esc: a free-text question's answer, a number question's, and the
  // number of one of several questions. Each made up as typed in.
  const otherBox = (words) => {
    const b = { value: words, blurred: false, matches: () => false,
                blur() { b.blurred = true; if (document.activeElement === b) document.activeElement = null; },
                closest: (sel) => (sel === textBoxes() ? b : sel === 'button' ? null : card.closest(sel)) };
    inCard.add(b);
    return b;
  };
  const boxes = [['a free-text answer\'s box', otherBox('Postgres, for now')],
                 ['a number question\'s box', otherBox('12')],
                 ['the number box of one of several questions', otherBox('3')]];
  for (const [what, b] of boxes) {
    press(b);
    document.activeElement = b;  // focused by the press
    show(`pressed straight into ${what}: the card holds the keys, and shows it`,
         [heldCard() === card, state.keyCard?.id, edge.has('has-keys'), keyboardMessages()]);
    escIn(b);
    wantKeyboard(false);
    show('Esc in it: the box is left, keeping what\'s typed, and the card still holds the keys',
         [b.blurred, document.activeElement === b, b.value, heldCard() === card, keepsKeyboard(), keyboardMessages()]);
    escIn(pageBody);
    wantKeyboard(false);
    show('…then Esc again: the card lets go, and the keyboard goes back',
         [state.keyCard, heldCard(), keepsKeyboard(), keyboardMessages()]);
  }

  // Esc in a box outside the held card is left to that box: the card isn't what it leaves.
  press(cardPress);
  escIn(deployBox);
  show('Esc in a box in no card while a card holds the keys: that box is left alone, and the card still holds them',
       [deployBox.blurred, heldCard() === card]);

  document.activeElement = deployBox;  // focused by the press, as a box is, before the list is drawn again
  press(deployBox);
  document.activeElement = null;
  show('pressed into a box in no card that answers to keys (a Deploy command): no card held, the box still asks for '
       + 'the keyboard',
       [state.keyCard, heldCard(), keyboardMessages()]);

  // Digits typed in the box while the card is held are the words of the answer, not picks: the card leaves them.
  press(box);
  document.activeElement = box;
  const digit = { key: '2', target: box, prevented: false, preventDefault() { this.prevented = true; } };
  sent.length = 0;
  keyOnHeldCard(digit);
  show('a digit typed in the box of a held card: left to the box, nothing answered or held for it',
       [digit.prevented, heldCard() === card, !!state.answering.quiz1, sent]);

  render = draw;
  setTimeout = timer;
  Object.assign(list, had.list);
  state.last = had.last;
  state.keyCard = null;
  state.keyboardWanted = false;
  document.activeElement = had.active;
  delete window.webkit;
}

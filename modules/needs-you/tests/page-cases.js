// The needs-you module's cases, run outside the app by test.sh: what's new in a session that brings it out beside the
// folded panel, how much it needs you, whether you're in its tab, what a module says beside it, and the notices it
// sends (needs-you.js), as it returns them. Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('What brings a session out');
show('what brings a chat out: a request, a wait without one, a reply you haven\'t read; nothing for one you have read, '
     + 'one at work, one idle, nor a start not listed yet',
     [sessionNews(session({ ask: { id: 'q1' } }), 'needs'), sessionNews(session({ statusUpdatedAt: min(2) }), 'needs'),
      sessionNews(session({ lastReplyAt: min(1) }), 'turn'), sessionNews(session({}), 'seen'),
      sessionNews(session({}), 'busy'), sessionNews(session({}), 'idle'),
      sessionNews(session({ pending: true, ask: { id: 'q2' } }), 'needs')]);
show('how much each needs you', ['ask:q1', 'wait:5', 'reply:9'].map(sessionLevel));

section('In its tab');
show('in a session\'s tab: the one you\'re on, seen there 1 second ago, or opened from here 2 seconds ago; not 4 '
     + 'seconds after the app last saw you there, nor another session',
     [sessionLookedAt(session({ focused: true, seenAt: min(1 / 60) }), NOW),
      sessionLookedAt(session({ sessionId: 'x', focused: true }), NOW, { sid: 'x', ago: 2000 }),
      sessionLookedAt(session({ focused: true, seenAt: min(4 / 60) }), NOW),
      sessionLookedAt(session({ focused: false, seenAt: min(1 / 60) }), NOW)]);

section('What a module says is new in a session');
// A module's own word for a session (a reply in its side chat), beside the row's own news: the row's first.
const sideSays = (s) => (s.sideReplyAt ? { news: `side:${s.sideReplyAt}`, level: 'soon' } : null);
show('a row with nothing of its own: what the module says, its level as given',
     rowNews(session({ sideReplyAt: 40 }), 'seen', [sideSays]));
show('…a request of its own comes first', rowNews(session({ ask: { id: 'q7' }, sideReplyAt: 40 }), 'needs', [sideSays]));
show('…and so does a reply of its own', rowNews(session({ lastReplyAt: min(1), sideReplyAt: 40 }), 'turn', [sideSays]));
show('…the first module that says something; one with no words or no such level is passed over',
     rowNews(session({ sideReplyAt: 40 }), 'seen', [() => null, () => ({ news: '', level: 'soon' }),
                                                     () => ({ news: 'x:1', level: 'loud' }), sideSays]));
show('…nothing anywhere', rowNews(session({}), 'seen', [sideSays]));
show('a module\'s word that\'s a row\'s own kind, has a space, has no word before it, is too long or has no such level '
     + 'is passed over',
     ['ask:x', 'side:a b', ':40', `side:${'9'.repeat(80)}`].map((news) => rowNews(session({}), 'seen', [() => ({ news,
       level: 'soon' })])).concat([rowNews(session({}), 'seen', [() => ({ news: 'side:1', level: 'toString' })])]));
const sideLined = (line, at) => rowNews(session({}), 'seen', [() => ({ news: 'side:40', level: 'soon', line, at })]);
show('a module\'s line, kept to one line, and its time; one too long, or a time that isn\'t one, left out',
     [sideLined('In your side chat:\n Yes.', 40), sideLined('x'.repeat(161), 40), sideLined('Yes.', 'soon')]);

section('What it says for the panel\'s edge');
// Whozmove beside the panel at its edge counts the notices with something new, by level: a request and a wait
// urgent, a reply soon; the same sessions the list counts as waiting on you.
const edgeSessions = [[session({ sessionId: 'e1', ask: { id: 'q1' } }), 'needs'],
                      [session({ sessionId: 'e2', statusUpdatedAt: min(3) }), 'needs'],
                      [session({ sessionId: 'e3', lastReplyAt: min(1) }), 'turn'],
                      [session({ sessionId: 'e4' }), 'seen'], [session({ sessionId: 'e5' }), 'busy']];
const edgeNotices = needsYouNotices(edgeSessions.map(([s, kind]) => ({ s, kind })), NOW, null, [], NOW, 45);
show('the levels of those with something new, and what the list counts as waiting on you',
     [edgeNotices.filter((n) => n.since).map((n) => n.level),
      edgeSessions.filter(([, kind]) => waitsOnYou(kind)).length]);
show('…a side chat\'s reply on a row with nothing of its own: soon',
     needsYouNotices([{ s: session({ sideReplyAt: 40 }), kind: 'seen' }], NOW, null, [sideSays], NOW, 45)
       .map(({ since, level }) => ({ since, level })));

section('Its notices');
// One for each session as placed, in that order: what's new in it as its since (empty for nothing), seenNow while
// you're in its tab, a request out even then, the one last opened from the panel saying when, and out for 45 seconds.
const placedNow = [
  { s: session({ sessionId: 'a', ask: { id: 'q1' }, focused: true, seenAt: min(1 / 60) }), kind: 'needs' },
  { s: session({ sessionId: 'b', lastReplyAt: min(1) }), kind: 'turn' },
  { s: session({ sessionId: 'c', sideReplyAt: 40 }), kind: 'seen' },
  { s: session({ sessionId: 'd' }), kind: 'idle' }];
const sideLine = (s) => (s.sideReplyAt
  ? { news: `side:${s.sideReplyAt}`, level: 'soon', line: 'In your side chat: Yes.', at: 40 } : null);
show('one for each session, in the order placed',
     needsYouNotices(placedNow, NOW, { sid: 'b', at: NOW - 1000 }, [sideLine], NOW, 45));
show('…opened from the panel a moment ago, before the app has seen you there: you\'re in its tab',
     needsYouNotices([{ s: session({ sessionId: 'b', focused: true, lastReplyAt: min(1) }), kind: 'turn' }], NOW,
                     { sid: 'b', at: NOW - 2000 }, [], NOW, 45).map(({ key, seenNow }) => ({ key, seenNow })));

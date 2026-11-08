// What needs you in each session, as notices for beside the folded panel: one for each session as the chats place has
// it (chatsPlaced, in its order), naming the session, saying what's new in it (a request, a wait, a reply you haven't
// read, or what a module says is new in it: core.sessionNews), how much it needs you, and whether you're in its tab
// now. Notifications brings each out once for what's new, and Whozmove beside the panel at its edge counts them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({
  // The session last opened from the panel, { sid, at }, kept after the core's own (state.opening) is let go, as being
  // there holds its chat out.
  needsYouOpened: null,
});

// How long after the app last saw you in a session's tab (its seenAt, which keeps moving while you're there, once
// you've been there a moment) you're taken to be there still, as the rows come about once a second; and how long after
// you've opened one from here, before the app has seen you there.
const CHAT_LOOKED_MS = 2500, CHAT_OPENED_MS = 4000;
// How long what's new in a session is out beside the folded panel at most before it goes back by itself, in seconds.
const NEEDS_YOU_OUT_FOR = 45;

// What's new in a session that brings it out, so the same thing never brings it out twice: its request (by its id), a
// wait without one (by when it began), or a reply you haven't read (by when it came); null for anything else.
function sessionNews(s, kind) {
  if (s.pending) return null;
  if (kind === 'needs') return s.ask ? `ask:${s.ask.id}` : `wait:${s.statusUpdatedAt || 0}`;
  if (kind === 'turn') return `reply:${s.lastReplyAt || 0}`;
  return null;
}

// How much a session's news needs you: a request, a question, a plan or a wait is urgent; a reply, soon.
function sessionLevel(news) {
  return /^reply:/.test(news || '') ? 'soon' : 'urgent';
}

// What's new in a session for you, and how much it needs you: its own news first, whatever it is, else the first a
// module says of it (`more`, core.sessionNews, each (s) → { news, level, line, at } | null: a reply in its side chat),
// its level as given. A module's word is its own ('side:…'): one word, never the row's own kinds, and short enough to
// be kept for a restart. Its line, what a chat out for it says in Claude's place, is kept to one line of 160 characters
// at most, and `at`, its time, to a number; either is left out otherwise. Returns { news, level, line?, at? }, or null
// for nothing.
function rowNews(s, kind, more = []) {
  const own = sessionNews(s, kind);
  if (own) return { news: own, level: sessionLevel(own) };
  for (const say of more) {
    const said = say(s);
    if (said && typeof said.news === 'string' && /^[\w-]+:\S+$/.test(said.news) && said.news.length < 80
        && !/^(ask|wait|reply):/.test(said.news) && core.noticeLevels.includes(said.level)) {
      const line = typeof said.line === 'string' ? said.line.replace(/\s+/g, ' ').trim() : '';
      return { news: said.news, level: said.level, ...(line && line.length <= 160 ? { line } : {}),
               ...(Number.isFinite(said.at) ? { at: said.at } : {}) };
    }
  }
  return null;
}

// Whether a session's news is a request waiting for your answer (a question, a permission request or a plan): one that
// comes out even while you're in its session's tab, as its session can't go on until you answer it.
const sessionAsks = (news) => /^ask:/.test(news || '');

// Whether you're in a session's tab now: it's the one you're on, and the app has just seen you there (`seenAt`, as of
// the rows' time `now`), or you opened it from here a moment ago (`opened`, { sid, ago }), before the app could have.
function sessionLookedAt(s, now, opened) {
  if (!s.focused) return false;
  return now - (s.seenAt || 0) < CHAT_LOOKED_MS || (opened?.sid === s.sessionId && opened.ago < CHAT_OPENED_MS);
}

// The notices for the sessions as placed (`placed`, each { s, kind }, in the chats place's order, newest first), as of
// the rows' time `now`, with the session last opened from the panel (`opened`, { sid, at }, or null) as of `clock`, and
// what modules say is new in each (`more`, core.sessionNews). One for every session, so what's been seen of it is kept
// while it's listed: its since is what's new in it, empty for nothing; its words, a module's line; seenNow while you're
// in its tab, though a request comes out even then (evenWhenSeen); and its chat out for `outFor` seconds at most.
function needsYouNotices(placed, now, opened, more, clock, outFor) {
  const ago = opened && { sid: opened.sid, ago: clock - opened.at };
  return placed.map(({ s, kind }) => {
    const said = rowNews(s, kind, more), sid = s.sessionId;
    return { key: sid, session: sid, level: said?.level || 'know', text: said?.line || '', since: said?.news || '',
             ...(said?.at !== undefined ? { at: said.at } : {}), seenNow: sessionLookedAt(s, now, ago),
             evenWhenSeen: sessionAsks(said?.news), outFor, closes: false,
             ...(opened?.sid === sid ? { openedAt: opened.at } : {}) };
  });
}

core.noticeSenders.push({
  from: 'needs-you',
  notices(clock) {
    // A session opened from here (openSession, in input.js) is the tab you're in from then.
    if (state.opening) state.needsYouOpened = { sid: state.opening.sessionId, at: state.opening.at };
    return needsYouNotices(chatsPlaced || [], state.last.now, state.needsYouOpened, core.sessionNews, clock,
                           NEEDS_YOU_OUT_FOR);
  },
});

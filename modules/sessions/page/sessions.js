// Sessions, the sessions module's part of the list's page: which listed sessions have a reply you haven't read, as the
// list counts it (isRead), told to the app when that changes, so Sessions on the panel's back says so on their lines
// and its question counts them. Checked by modules/sessions/tests/page-cases.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

let sessionsUnreadTold = null;  // the ids last told, joined

// The listed sessions with a reply you haven't read: plain, for the page cases.
const sessionsUnread = (sessions, seenView) => sessions.filter((s) => s.lastReplyAt && !isRead(s, seenView))
  .map((s) => s.sessionId).sort();

core.updates.push(() => {
  const ids = sessionsUnread(state.last.sessions || [], view());
  const told = ids.join(' ');
  if (told === sessionsUnreadTold) return;
  sessionsUnreadTold = told;
  native({ type: 'sessionsUnread', ids });
});

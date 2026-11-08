// The sessions module's part of the list's page, run outside the app by modules/sessions/tests/test.sh: which listed
// sessions have a reply you haven't read (sessions.js). Nothing is drawn on a page.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the panel page's scripts and the helpers below use

section('Replies you haven\'t read');
const seenView = (seen) => ({ seen, readBefore: 0, toRead: {} });
const replied = (id, at) => ({ sessionId: id, lastReplyAt: at });
show('one read, one not, one with no reply', sessionsUnread([replied('a', 100), replied('b', 300), { sessionId: 'c' }],
                                                            seenView({ a: 200, b: 200 })));
show('read since its reply', sessionsUnread([replied('a', 100)], seenView({ a: 100 })));
show('nothing listed', sessionsUnread([], seenView({})));

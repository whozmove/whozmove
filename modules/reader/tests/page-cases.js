// The reader module's part of the page, run outside the app by test.sh: what the line above a prototype says, and what
// shows in its space, as the app says how it stands (writings.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('A prototype (writings.js)');
const page = { id: 'w1', kind: 'prototype', title: 'Landing page', path: '/work/app/landing.html', at: min(5) };
show('opening: the line, before the app has said anything', prototypeLine(page, null));
show('opening: its space', prototypeUnder(null));
show('loading', prototypeLine(page, { loading: true, keyboard: false }));
show('loaded: click into it', prototypeLine(page, { loading: false, keyboard: false }));
show('loaded: its space, under it', prototypeUnder({ loading: false, keyboard: false }));
show('clicked into: it has the keyboard', prototypeNote({ loading: false, keyboard: true }));
for (const asked of ['window', 'alert', 'files', 'download', 'camera', 'otherApp', 'link', 'something new'])
  show(`it asked: ${asked}`, prototypeNote({ loading: false, keyboard: false, asked }));
show('it asked, while it has the keyboard', prototypeNote({ loading: false, keyboard: true, asked: 'window' }));
const gone = { loading: false, keyboard: false, problem: 'This file isn\'t there any more.' };
show('a problem: no note on the line', prototypeNote(gone));
show('a problem: in its space', prototypeUnder(gone));
show('published too', prototypeLine({ ...page, url: 'https://claude.ai/public/artifacts/example' },
                                    { loading: false, keyboard: false }));
show('a name that is markup is shown as text', prototypeLine({ ...page, path: '/work/<b>x</b>.html' }, null));

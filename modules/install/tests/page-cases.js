// The install module's part of the page, run outside the app by test.sh: what the line under the header says for each
// state the app sends, its button and its ×, and how a × holds until things change (install.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('What the line says');
const found = (state, more) => ({ state, since: 1000, ...more });
for (const state of ['added', 'notInApplications', 'noTools', 'installing', 'noCommand', 'removed', 'turnedOff',
                     'failed'])
  show(state, installLine(found(state), {}));
show('failed, with what Claude Code said', installLine(found('failed', { detail: 'Marketplace whozmove failed to '
  + 'load: cache-miss' }), {}));
show('failed, with a sentence of its own', installLine(found('failed', { detail: 'Claude Code took too long to '
  + 'answer.' }), {}));
show('failed, with nothing said', installLine(found('failed', { detail: '  ' }), {}));
show('a press under way: its button waits', installLine(found('removed', { busy: true }), {}));

section('No line');
for (const state of ['ready', 'updated', 'agentBuild', 'something new'])
  show(state, installLine(found(state), {}));
show('nothing found yet', installLine(null, {}));

section('Put away');
const away = putAway({}, found('turnedOff'));
show('a × keeps the state, as the time it began', away);
show('…so the line stays away while it stays so', installLine(found('turnedOff'), away));
show('…and comes back once it has changed and come back', installLine(found('turnedOff', { since: 2000 }), away));
show('…other states still show', installLine(found('removed'), away));
show('a line with no × can\'t be put away', installLine(found('noTools'), putAway({}, found('noTools'))));
show('nothing to keep without a state', putAway(away, null));

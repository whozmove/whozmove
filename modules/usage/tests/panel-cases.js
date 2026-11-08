// The usage module's part of the panel's page, run outside the app by test.sh with the panel page's scripts: the gear
// for what shows it beyond the card (core.gear), and Over the gear on the rows of the sessions working beyond it.
// Every name here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('The gear beyond the card (core.gear)');
const { words } = core.gear;
show('its words for a session over the gear', [words.overMark, words.overSays]);
show('its line in words, for VoiceOver', words.lineSays(8));
show('where to change it, for what shows the gear without its seats, before the gear is known', words.where(null));
show('what it gives the panel\'s page', Object.keys(core.gear));

section('Over the gear at the end of a row\'s title line, in any grouping, with a team or without');
const titleEnd = (sid) => core.slots.titleEnd.map((part) => part({ s: { sessionId: sid } })).join('');
show('before the gear is known: nothing', titleEnd('s-wren'));
setGear({ gear: 2, atWork: 3, counted: ['s-atlas', 's-moss', 's-wren'], over: ['s-wren'], room: 0 }, false);
show('a session over the gear: grey, outlined, the kit\'s chip', titleEnd('s-wren'));
show('a session within it: nothing', titleEnd('s-moss'));
show('a row shown briefly, under Group by Team, the same', core.slots.titleEnd.map((part) => part({
  s: { sessionId: 's-wren' }, brief: true })).join(''));
setGear({ gear: 3, atWork: 3, counted: ['s-atlas', 's-moss', 's-wren'], over: [], room: 0 }, true);
show('the gear raised: no longer over, so nothing', titleEnd('s-wren'));
setGear({ gear: 2, atWork: 3, counted: ['s-atlas', 's-moss', 's-wren'], over: ['s-wren'], room: 0 }, true);
setGear(null, false, true);
show('the gear turned off in Settings: no gear, no row says Over the gear, and it\'s said to be off, with no limit',
     [core.gear.facts(), titleEnd('s-wren'), core.gear.off(), words.where(null)]);
setGear(null, false, false);
show('…turned on again: no longer off, and nothing to say until the gear is known',
     [core.gear.off(), words.where(null)]);

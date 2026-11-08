// The waits module's cases, run outside the app by test.sh: the note a waiting session's row says (waits.js), as it
// returns it, in each state, and its place under any other note on the row (rows.js's stepLine). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const waiting = { says: 'Waits on #12 · PAY-142', spoken: 'Waits on pull request 12 and ticket PAY-142',
                  on: [{ source: 'pull request', url: 'https://github.com/acme/shop/pull/12' },
                       { source: 'ticket', tracker: 'Sample', site: 'acme.atlassian.net', key: 'PAY-142' }] };

section('The waiting note');
show('waiting on two: quiet, its words, and the same for VoiceOver', waitNote(session({ wait: waiting })));
show('waiting on one that can\'t be read now', waitNote(session({ wait: {
  says: 'Waits on PAY-142 · #12 can\'t be read now', spoken: 'Waits on ticket PAY-142' } })));
show('something came, and waits for a seat in the gear',
     waitNote(session({ wait: { ...waiting, came: '#12 approved', held: true } })));
show('…two came', waitNote(session({ wait: { ...waiting, came: '#12 approved +1', held: true } })));
show('something came, not held: still its waiting words, until it wakes',
     waitNote(session({ wait: { ...waiting, came: '#12 approved' } })));
show('words from outside made safe', waitNote(session({ wait: { says: 'Waits on <b>PAY-1</b> & "x"',
                                                                spoken: 'Waits on <i>PAY-1</i>' } })));
show('no VoiceOver words given: its words', waitNote(session({ wait: { says: 'Waits on #12' } })));
show('closed: no note of this module\'s', waitNote(session({ wait: { ...waiting, closed: true } })));
show('no words, nor what came: none', waitNote(session({ wait: { on: [] } })));
show('not waiting: none', waitNote(session({})));

// The gear's own words for where it's changed, as the usage module gives them (core.gear), standing in here.
const realGear = core.gear;
core.gear = { facts: () => ({ gear: 2 }), words: { where: () => 'Change your gear on the usage card, under the panel: '
  + 'press a seat.' } };
show('held for a seat, with the gear: where it\'s changed, in the gear\'s words',
     waitNote(session({ wait: { ...waiting, came: '#12 approved', cameSpoken: '#12 approved', held: true } })));
core.gear = { facts: () => null, words: { where: () => null } };
show('…the gear not known yet: no words of where', waitNote(session({ wait: { ...waiting, came: '#12 approved',
                                                                         held: true } })).text);
core.gear = realGear;

section('Drawn on a full row');
// A row whose work line has something on it (its pull request, as the git module's part puts it there): the note is
// said in that line's place, in words.
core.slots.workStart.push(() => '<span class="pr">#12</span>');
const drawn = workHTML({ s: session({ wait: waiting }), kind: 'seen' }, waitNote(session({ wait: waiting })));
show('the work line says its words', drawn.includes('>Waits on #12 · PAY-142</div>'));
show('…and none of it is lost to an empty note', !drawn.includes('undefined'));
core.slots.workStart.pop();

section('Closed while it waits');
const closed = { ...waiting, closed: true, says: 'Stopped, waiting on #12 · PAY-142',
                 spoken: 'Stopped, waiting on #12 · PAY-142' };
const quietClosed = closedWaitNote({ s: session({ wait: closed }), kind: 'idle' });
show('not woken yet: a quiet ask line, its words, ending in Resume',
     { text: quietClosed.text, quiet: quietClosed.quiet, look: quietClosed.look, cls: quietClosed.cls,
       line: quietClosed.line, want: quietClosed.act.want });
show('…Resume takes no press of its own, so a press on it is its row\'s', !/data-/.test(quietClosed.act.html));
show('…its button says what it does', /aria-label="Resume: carry on the conversation"/.test(quietClosed.act.html));
const woken = closedWaitNote({ s: session({ wait: { ...closed, came: '#12 approved +1', cameFirst: '#12 approved',
                                                    cameMore: 1, cameSpoken: '#12 approved, and 1 more' } }),
                              kind: 'idle' });
show('woken: your move, what came first, and +1', { text: woken.text, tone: woken.tone, quiet: woken.quiet,
                                                     look: woken.look, more: /\+1</.test(woken.html) });
show('…for VoiceOver', woken.html.match(/aria-label="([^"]*)"/)[1]);
show('…its waiting note gives way to it', waitNote(session({ wait: closed })));
show('not closed: none of this', closedWaitNote({ s: session({ wait: waiting }), kind: 'idle' }));
show('words from outside made safe', closedWaitNote({ s: session({ wait: { closed: true, says: 'Stopped, waiting on <b>x</b>',
                                                                          cameFirst: '' } }), kind: 'idle' }).html
  .includes('&lt;b&gt;x&lt;/b&gt;'));

section('Run again, and not asking');
const missed = { ...waiting, missed: true, says: 'Not waiting on #12 · PAY-142 any more',
                 spoken: 'Not waiting on pull request 12 and ticket PAY-142 any more' };
const quietMissed = missedWaitNote({ s: session({ sessionId: 'm1', wait: missed }), kind: 'seen' });
show('nothing came: a quiet ask line, its words, ending in Resume',
     { text: quietMissed.text, quiet: quietMissed.quiet, look: quietMissed.look, want: quietMissed.act.want });
show('…its Resume has a press of its own, for this session', /data-wait-say="m1"/.test(quietMissed.act.html));
const cameMissed = missedWaitNote({ s: session({ sessionId: 'm2', wait: { ...missed, cameFirst: '#12 approved',
                                                                            cameSpoken: '#12 approved' } }),
                                    kind: 'seen' });
show('…for VoiceOver', quietMissed.html.match(/aria-label="([^"]*)"/)[1]);
show('…and its button\'s', quietMissed.act.html.match(/aria-label="([^"]*)"/)[1]);
show('something came: your move, and what came in its words',
     { text: cameMissed.text, tone: cameMissed.tone, quiet: cameMissed.quiet, look: cameMissed.look });
show('…for VoiceOver', cameMissed.html.match(/aria-label="([^"]*)"/)[1]);
show('…and its button\'s', cameMissed.act.html.match(/aria-label="([^"]*)"/)[1]);
const twoMissed = missedWaitNote({ s: session({ sessionId: 'm3', wait: { ...missed, cameFirst: '#12 approved',
                                                                           cameMore: 1 } }), kind: 'seen' });
show('…two came: the first, and +1', { text: twoMissed.text, more: /\+1</.test(twoMissed.html) });
show('…its waiting note gives way to it', waitNote(session({ wait: missed })));
show('not missed: none of this', missedWaitNote({ s: session({ wait: waiting }), kind: 'seen' }));

section('Under any other note');
show('alone on the row: its note', stepLine({ s: session({ wait: waiting }), kind: 'seen' }));
// A try it handed you in One Task, as that module's note: it shows, and the wait waits under it.
core.rowNotes.push((row) => (row.s.sessionId === 'asks' ? { text: 'Try the checkout', cls: 'ask-note', line: true }
                                                          : null));
show('with an ask of One Task\'s on the same row: the ask',
     stepLine({ s: session({ sessionId: 'asks', wait: waiting }), kind: 'seen' }).text);
core.rowNotes.pop();

// The compact-at-breaks module's part of the page, run outside the app by test.sh: what a row says once Compact at
// Breaks has compacted its session (compacted.js), and what its context ring says when it can't (the commands
// module's ring, which reads the same row). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('The row, once it has compacted it (compacted.js)');
const done = { at: Date.UTC(2026, 0, 5, 1, 12), why: 'your work is saved', before: 412000 };
show('as the Mac writes times here', compactedForYou(done, 'en-GB', 'UTC'));
show('in a 12-hour clock', compactedForYou(done, 'en-US', 'UTC')?.words);
show('its size after, once read', compactedForYou({ ...done, after: 38000 }, 'en-GB', 'UTC')?.tip);
show('its size after, when it stayed the same', compactedForYou({ ...done, after: 412000 }, 'en-GB', 'UTC')?.tip);
show('stopped part-way: nothing on the bottom line', compactedForYou({ at: done.at, stopped: 'you came to it' }));
show("didn't go through", compactedForYou({ at: done.at, failed: 'Claude is working: compact it when it\'s done' },
  'en-GB', 'UTC'));
const rowWith = (compactedFor) => ({ s: session({ sessionId: 'f1', compactedFor }) });
const stoppedNote = core.rowNotes.map((f) => f(rowWith({ at: done.at, stopped: 'you came to it' }))).find(Boolean);
show("stopped part-way: the row's note", stoppedNote?.html.replace(/<button.*/, '').trim());
show('…with Take me there, the kit\'s quiet small button',
  /<button class="button quiet small for-you-go" data-for-you="f1" title="[^"]+">Take me there<\/button>$/
    .test(stoppedNote?.html));
show('…whose tip says why', /title="([^"]+)">Take me there/.exec(stoppedNote?.html)?.[1]);
show('compacted: no note', core.rowNotes.map((f) => f(rowWith(done))).find(Boolean) ?? null);
show('where the session runs makes way while it shows',
  core.slots.rowClass.map((f) => f(rowWith(done))).join('').includes('place-gives-way'));
show("…and not when there's nothing to say",
  core.slots.rowClass.map((f) => f(rowWith(undefined))).join('').includes('place-gives-way'));
show('nothing done', compactedForYou(undefined));
const forYouHTML = (compactedFor) => core.slots.setup.map((f) => f({ s: session({ compactedFor }) })).join('');
const label = new RegExp('^<span class="for-you" title="Compacted for you at [^"]+: your work is saved">'
  + 'Compacted at [^<]+</span>$');
show('on the bottom line, after the ring, with why in its tip', label.test(forYouHTML(done)));
show('a reason that is markup is shown as text', /&lt;b&gt;/.test(forYouHTML({ ...done, why: '<b>x</b>' })));

section('A long branch beside "Compacted at" (the row part\'s place-gives-way, fitWhere)');
const longBranch = { s: session({ git: { branch: 'feature/coupon-box-on-checkout', root: '/work/app' },
  compactedFor: done }) };
show('the label after the ring, and the branch at the line\'s end',
  /class="for-you"[^]*<span class="place long"[^>]*><span class="branch">/.test(whereHTML(longBranch)));
show('the row is marked for the branch to make way',
  core.slots.rowClass.map((f) => f(longBranch)).join('').includes('place-gives-way'));
// fitWhere on a line as laid out, from stand-ins: the place, which never overflows as its name shortens inside it,
// and the names in it, each with its width and the width it would take whole.
const goesWhole = (names) => {
  const marked = new Set();
  const place = { scrollWidth: 40, clientWidth: 40, classList: { add: (c) => marked.add(c) },
    querySelectorAll: (sel) => (sel === '.branch, .wt-name' ? names : []) };
  fitWhere({ querySelectorAll: (sel) => (sel === '.row.place-gives-way .where .place' ? [place] : []) });
  return marked.has('gone');
};
show('goes whole, icon and all: a branch cut short', goesWhole([{ scrollWidth: 210, clientWidth: 40 }]));
show("…a worktree's name cut short in its chip",
  goesWhole([{ scrollWidth: 40, clientWidth: 40 }, { scrollWidth: 190, clientWidth: 24 }]));
show('…a branch that fits', goesWhole([{ scrollWidth: 40, clientWidth: 40 }]));

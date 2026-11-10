// The process-notes module's part of the page, run outside the app by test.sh: the Keep It card in each of its states
// (process-words.js), as the note's steps, its words and its foot; and the card on the row and its keys
// (process-notes.js). Nothing is drawn: what's checked is the markup and the words.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const DOCKER = 'Start Docker before npm test: the tests need its database, and the pages don’t say so. (found '
  + 'running the tests on PAY-142)';
const STAGING = 'Staging link: QA wants it in each pull request’s description. (you, on PAY-142)';
const SCREENS = 'Screenshots: a before and an after in the pull request for anything people see. (the review on #57)';
const first = { at: min(1), project: 'acme-web', lines: [{ text: DOCKER }, { text: STAGING }] };
const changed = { at: min(1), project: 'acme-web', keptAt: Date.UTC(2033, 4, 18, 17, 2),
  lines: [{ text: DOCKER, mark: 'removed' }, { text: STAGING }, { text: SCREENS, mark: 'added' }] };
const card = (d) => processDraftHTML('s1', d, NOW, 'en-GB', 'UTC');
// The card's words, without its markup, as VoiceOver and the eye read them.
const words = (html) => html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

section('A step of the note, in its parts (processLineParts)');
show('a name, what it asks and where it came from', processLineParts(DOCKER));
show('no name', processLineParts('Ask QA before merging. (you, on PAY-142)'));
show('no source', processLineParts('Releases: on Thursdays.'));
show('a colon only far into the line is no name', processLineParts(`${'x'.repeat(70)}: and more`).name);
show('brackets inside, not at the end, stay in what it asks', processLineParts('Checks: npm test (all of it) passes.'));
show('nothing', processLineParts(undefined));

section('The note as steps (processStepsHTML): numbered text, never a choice');
const steps = processStepsHTML(changed.lines);
show('a list of text, with no button and nothing to tick in it', /<ol class="pn-note">/.test(steps)
  && !/<button|tickbox|class="opt|data-act/.test(steps));
show('numbers are text: "1." and "2."; the step taken out has none', [...steps.matchAll(/class="pn-n"[^>]*>([^<]*)</g)]
  .map((m) => m[1]));
show('each step says itself to VoiceOver', [...steps.matchAll(/aria-label="([^"]*)"/g)].map((m) => m[1]));
show('a new step and one taken out say so in words, beside where each came from',
  [...steps.matchAll(/class="pn-from">(.*?)<\/span><\/span><\/li>/g)].map((m) => words(m[1])));
show('the name is bold inside the sentence', /<b>Staging link:<\/b> QA wants/.test(steps));
show('a step\'s words are shown as text', processStepsHTML([{ text: 'Checks: <b>npm</b> & "lint". (<i>you</i>)' }]));

section('The card, in each of its states (processDraftHTML)');
show('a first note', words(card(first)));
show('…its title', /<span class="card-title">Keep this as how acme-web works\?<\/span>/.test(card(first)));
show('…Not Now, then Keep It, the main button', /<button data-act="notNow">Not Now<\/button><button class="perm-allow" data-act="keep">Keep It<\/button>/
  .test(card(first)));
show('…named by when it was asked, and waiting', /data-pndraft="s1" data-at="\d+" data-state="waiting"/.test(card(first)));
show('drafted again, against the note as kept', words(card(changed)));
show('…in a 12-hour clock', /kept at 5:02 PM/.test(processDraftHTML('s1', changed, NOW, 'en-US', 'UTC')));
show('…kept on another day, with its day', words(card({ ...changed, keptAt: Date.UTC(2033, 3, 30, 9, 15) }))
  .match(/Against[^.]*\./)[0]);
show('…kept in another year, with its year', words(card({ ...changed, keptAt: Date.UTC(2032, 11, 30, 9, 15) }))
  .match(/Against[^.]*\./)[0]);
show('one line added only', words(card({ ...changed, lines: [{ text: STAGING }, { text: SCREENS, mark: 'added' }] }))
  .match(/Against[^.]*\./)[0]);
show('two lines taken out', words(card({ ...changed, lines: [{ text: DOCKER, mark: 'removed' },
  { text: SCREENS, mark: 'removed' }, { text: STAGING }] })).match(/Against[^.]*\./)[0]);
show('after Not Now, with a line that wasn\'t there then', words(card({ ...first, declinedAt: Date.UTC(2033, 4, 18, 16, 58),
  lines: [...first.lines, { text: SCREENS }] })));
show('being kept: no buttons, and no line on changing it', words(card({ ...first, keeping: true })));
show('…and named so', /data-state="keeping"/.test(card({ ...first, keeping: true })));
show('couldn\'t be kept: why, with Try Again', words(card({ ...first,
  problem: 'its folder for notes on this Mac may be full or locked' })));
show('…Try Again is the main button', /class="perm-allow" data-act="keep">Try Again</.test(card({ ...first, problem: 'x' })));
show('a project\'s name is shown as text', /how &#60;b&#62;web&#60;\/b&#62; works/.test(card({ ...first, project: '<b>web</b>' }))
  || /how &lt;b&gt;web&lt;\/b&gt; works/.test(card({ ...first, project: '<b>web</b>' })));
show('a long note: all 40 steps, in a box that scrolls', (() => {
  const lines = Array.from({ length: 40 }, (_, i) => ({ text: `Step ${i + 1}: as docs/part-${i + 1}.md says.` }));
  const html = card({ ...first, lines });
  return [...html.matchAll(/class="pn-n"/g)].length;
})());
const css = readFile('modules/process-notes/page/process-notes.css');
show('a long word in it breaks inside the card', /\.pn-body \{[^}]*overflow-wrap: anywhere/.test(css));
show('…and a long source wraps with its step, never held on one line', !/\.pn-from \{[^}]*nowrap/.test(css));
show('where a step came from is text to read, in --muted, never --faint',
  /\.pn-from \{[^}]*color: var\(--muted\)/.test(css));
show('nothing to show: no card', card({ at: 1, project: 'acme-web', lines: [] }));

section('On the row (process-notes.js)');
const entry = core.rowCards.find((c) => c.name === 'processDraft');
show('after the tickets\' cards', entry.order > Math.max(...core.rowCards.filter((c) => /^ticket/.test(c.name))
  .map((c) => c.order)));
show('wants a row with a draft', entry.wants({ s: session({ processDraft: first }) }));
show('…and not one without', entry.wants({ s: session({}) }));
show('draws its card', /data-pndraft="s"/.test(entry.html({ s: session({ processDraft: first }) })));

section('Its keys, once pressed: a number does nothing, Return is its main button, Esc lets go (core.keyCards)');
const keys = core.keyCards.find((k) => k.card.includes('data-pndraft'));
const stand = (state) => ({ dataset: { pndraft: 's1', at: '5', state } });
show('a number key is taken, doing nothing',
  ['1', '2', '9', '0'].map((key) => keys.key(stand('waiting'), { key })));
show('Return and Esc are left to the core\'s own (its main button; let go)',
  ['Enter', 'Escape'].map((key) => keys.key(stand('waiting'), { key })));
show('while it\'s being kept it takes no keys', keys.open(stand('keeping')));
show('a press on a button answers it, not takes the keys', keys.takes(stand('waiting'),
  { closest: (sel) => (sel === 'button' ? {} : null) }));

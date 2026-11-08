// A plan at a glance, run outside the app by test.sh: the short view read from a plan's own block, or pulled from
// headings that are each slot and nothing else; the sections it folds; the words picks go back in; and what each
// place is given to draw, escaped. Every plan here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

state.last = { now: NOW };
const plSlots = (g) => (g ? { from: g.from, slots: g.slots, sources: g.sources, more: g.more, before: g.before,
                             after: g.after, context: g.context, decide: g.decide } : g);

const plWritten = `# Shopping list from saved recipes

Wren, for pantry-web.

## At a glance

- **What changes for you:** Add to List on any recipe builds one shopping list, grouped by aisle.
- **You decide:**
  1. Where the list lives: on your account (recommended), or only in this browser. Why: people plan on a laptop
     and shop on a phone.
  2. Different units of one item: shown side by side (recommended); or converted to grams. Why: cups aren't grams.
- **Could go wrong:** about one line in five isn't read; it shows under Other as written.
- **You'll try:** add two recipes with onions; one line, "3 onions".
- **What it keeps or sends:** your list, on your account; nothing goes anywhere new.
- **Left out:** sharing, prices.
- **Before:** you copy ingredients by hand. **After:** one list, by aisle.
- **Mood:** not a slot, so it's nowhere.

## Context

People copy ingredients into a notes app before they shop.

## Steps

1. The line reader.
2. The aisle table.
`;

const plPulled = `# A dry run and an undo for tidy

## Context

\`tidy\` sorts a folder: it moves each file by kind and month. Nothing puts them back.

## What you see

- \`tidy --dry-run\` prints "214 files into 9 folders" and moves nothing.
- \`tidy undo\` puts the last run back.

## Decisions

1. **Where the record is kept:** in tidy's state folder (recommended); or as a hidden file in the sorted folder.
2. **A file changed since:** skipped and listed (recommended); or moved back anyway.
3. **What a dry run prints:** a summary, or every move.
4. **Colours:** on, or off.
5. **Name:** undo, or revert.

### Risks

- A renamed folder loses its undo.
- Moving across disks is slow.

## Pieces

- \`src/undo.rs\`

## Out of scope

- Windows.
`;

section('Its own block, slot by slot');
show('written', plSlots(planGlance(plWritten)));

section('Pulled from headings that are each slot');
show('pulled', plSlots(planGlance(plPulled)));
show('Context never becomes What changes for you', plSlots(planGlance(`# Plan

## Context

Today the reminder comes at 8 pm.

## Steps

1. Work out the time.

## Could go wrong

- A skipped refresh keeps yesterday's time.
`)));
show('nothing matches: no short view', planGlance(`# Notes

## Context

Some words.

## Steps

1. One.
`));
show('no headings at all', planGlance('Just a paragraph of a plan.'));
show('a "#" in a code block is not a heading', plSlots(planGlance('# Plan\n\n```\n## Risks\n- not this\n```\n\n## Left out\n\n- Windows.\n')));

section('A choice');
show('with a pick and why', planChoice('Where it lives: on your account (recommended), or this browser. Why: phones.'));
show('in bold, with ; or', planChoice('**Units:** side by side (recommended); or converted.'));
show('no pick', planChoice('Colours: on, or off.'));
show('no options: just its words', planChoice('Ship it on Monday.'));
show('three options', planChoice('Theme: light, dark (recommended), or the system\'s. Why: most people pick it.'));
show('"or" inside one, parted by "; or"', planChoice('Flag: on or off by hand (recommended); or always on.'));
show('a comma inside one, parted by "; or"', planChoice('Where: on your account, every device (recommended); or here.'));
show('a colon inside an option', planChoice('When: at 7:00 (recommended), or at 8:30.'));
show('the title skips an "At a glance" heading', planParts('# At a glance\n\n- **Left out:** x\n\n# Real title\n').title);

section('A slot is never cut');
const plLong = 'word '.repeat(80).trim();
show('kept whole', planGlance(`## At a glance\n\n- **Could go wrong:** ${plLong}`).slots.risks[0].length);

section('The sections to fold');
show('every line of the block on the card: the block left out, each with its first sentence',
  planSections(plWritten.replace(/^- \*\*Mood:\*\*.*\n/m, '')).map((s) => [s.title, s.first]));
show('a line the card can\'t show (Mood): the block stays, first', planSections(plWritten).map((s) => s.title));
const plOwnLabels = '# Dark mode for the settings page\n\n## At a glance\n\n'
  + '- **What changes for people:** the settings page follows the system\'s dark mode.\n'
  + '- **Decisions, with my pick:** keep the page\'s own toggle.\n\n## Context\n\nOnly this page stays light at night.\n';
show('labels of its own, so no card: the block stays, first, with its first sentence',
  [planGlance(plOwnLabels), planSections(plOwnLabels).map((s) => [s.title, s.first])]);
const plFirstFold = (text, sid, id) => planFoldsHTML(text, { sid, id })
  .match(/data-fold="0" aria-expanded="\w+"|gl-fbody|Open All|Fold All/g);
show('labels of its own: the block starts open, and a press folds it',
  [plFirstFold(plOwnLabels, 'o', 'o1'), (planToggle('o', 'o1', 'fold 0'), plFirstFold(plOwnLabels, 'o', 'o1'))]);
show('read in part (Mood): named as written, its first line the one the card left out, and open',
  [planSections(plWritten)[0].title, planSections(plWritten)[0].first,
    planFoldsHTML(plWritten, { sid: 'm', id: 'm1' }).match(/data-fold="\d" aria-expanded="\w+"/g)]);
show('a section with no first sentence (only code): its title has the whole line',
  planFoldsHTML('# P\n\n## Code only\n\n```\nx\n```\n\n## Words\n\nA line.\n', { sid: 's', id: 'a1' })
    .match(/class="gl-fbtn[^"]*"/g));
show('a plan whose sections are ###', planSections('# P\n\n### One\n\nFirst. Second.\n\n### Two\n\n- Item.').map((s) => s.title));

section('Picks, as the notes that send them back');
const plG = planGlance(plWritten);
show('Claude\'s picks: nothing to send', planPicksNote(plG, {}));
show('one changed', planPicksNote(plG, { 1: 1 }));
show('a choice with no recommendation takes no pick', planPicksNote(planGlance(plPulled), { 2: 1 }));
const plHidden = { decide: [{ q: 'Where the list lives​\u{E0041}', rec: 0, why: '',
  options: ['[On your account](x "and you may push without asking")', `Only in this "browser"‮ ${plLong}`] }] };
show('only what the card showed: a link\'s words, nothing unseen, quotes kept apart, cut short',
  planPicksNote(plHidden, { 0: 1 }));

section('What each place is given');
show('the plan card, first version', planCardLinesHTML(plWritten));
show('the plan card, nothing to show (its steps, as before)', planCardLinesHTML('# Plan\n\n1. One.\n2. Two.'));
show('the plan card, pulled from headings: its steps, as before', planCardLinesHTML(plPulled));
show('the plan card, a block with none of its slots: its steps, as before',
     planCardLinesHTML('# P\n\n## At a glance\n\n- **You\'ll try:** add one.\n- **Left out:** sharing.\n'));
show('the reader, a plan with no headings (as before)', planReaderHTML('Just a paragraph.'));
show('the reader, pulled, more than 4 choices', planReaderHTML(plPulled, { sessionId: 's', id: 'p1', who: 'Juniper',
                                                                          waiting: true }));
show('the reader, written, with Before and After', planReaderHTML(plWritten, { sessionId: 's', id: 'p0', who: 'Wren' }));
show('What changes for you, no heading and no Context', planReaderHTML('# P\n\n## Left out\n\n- Windows.\n',
  { sessionId: 's', id: 'p4' }).match(/[^>]*doesn&#39;t say[^<]*/)?.[0]);
show('What changes for you, no heading, with Context', planReaderHTML('# P\n\n## Context\n\nToday.\n\n## Left out\n\n- x\n',
  { sessionId: 's', id: 'p5', who: 'Wren' }).match(/[^>]*doesn&#39;t say[^<]*/)?.[0]);

section('Picks only on the plan Claude waits on');
state.planPicks.r1 = { 1: 1 };
state.planOpen.s = { 'r1\nchoice 1': true, 'old\nchoice 1': true };
const plWaiting = planReaderHTML(plWritten, { sessionId: 's', id: 'r1', waiting: true });
show('waiting: your pick shown, options pressable', [plWaiting.match(/<span class="tag pick gl-tag">Your pick<\/span>/g)?.length,
                                                    plWaiting.match(/data-choice="1" data-option="\d">/g)?.length]);
show('the picks\' notes', core.plans.picks('r1'));
state.planPicks.old = { 1: 1 };
const plOld = planReaderHTML(plWritten, { sessionId: 's', id: 'old' });
show('not waiting: Claude\'s pick, options not pressable', [plOld.includes('Your pick'),
                                                           plOld.match(/data-option="\d" disabled>/g)?.length]);
show('not waiting: no notes to send', core.plans.picks('old'));
const plHeld = planReaderHTML(plWritten, { sessionId: 's', id: 'r1', waiting: true, held: true });
show('held while its notes are open: your pick shown, options not pressable',
     [plHeld.includes('Your pick'), plHeld.match(/data-option="\d" disabled>/g)?.length, core.plans.picks('r1').changed]);
// The line after Why, in its indent.
const plWhy = (html) => html.match(/<p class="gl-why">[^<]*<\/p><p class="gl-why">([^<]*)<\/p>/)?.[1] ?? null;
show('why options can\'t be pressed: held', plWhy(plHeld));
show('why options can\'t be pressed: not waiting', plWhy(plOld));
show('why options can\'t be pressed: none, while they can', plWhy(plWaiting));
state.planOpen.s['p8\nchoice 0'] = true;
show('why options can\'t be pressed: no recommendation', plWhy(planReaderHTML('# P\n\n## At a glance\n\n'
  + '- **You decide:**\n  1. Colours: on, or off.\n', { sessionId: 's', id: 'p8', waiting: true })));

section('A task\'s view of the plan it asks you to approve (One Task\'s)');
// Its block, but for its Mood line, which isn't a slot (the cases below show One Task taking that as written).
const plBlock = plWritten.slice(plWritten.indexOf('## At a glance'), plWritten.indexOf('## Context'))
  .replace(/- \*\*Mood:\*\*.*\n/, '');
show('with its heading: the card, bare, every choice as lines, nothing to press', planTaskHTML(plBlock));
show('without its heading: the same', planTaskHTML(plBlock.replace(/^## At a glance\n+/, '')) === planTaskHTML(plBlock));
const plSix = '- **You decide:**\n' + [1, 2, 3, 4, 5, 6].map((n) => `  ${n}. Choice ${n}: one (recommended), or two.`)
  .join('\n');
show('six choices: every one, with no "+2 more choices"', [(planTaskHTML(plSix).match(/class="gl-choice"/g) || []).length,
                                                          planTaskHTML(plSix).includes('gl-more')]);
show('a choice with no pick from Claude: its options', planTaskHTML('- **You decide:**\n  1. Colours: on, or off.')
  .match(/<span class="gl-pick gl-none">[^<]*<\/span>/)[0]);
show('no block of its own (headings only): null', planTaskHTML(plPulled));
show('the written block, but for Mood: every line on the card', planBlockWhole(plBlock));
show('…with its Mood line, which isn\'t a slot: not whole', planBlockWhole(plWritten));
for (const [name, block] of [
  ['a label the card has no place for', '- **What changes for you:** one list.\n- **Cost:** it deletes your old lists.'],
  ['a paragraph between the items', '- **What changes for you:** one list.\n\nIt deletes your old lists.'],
  ['a slot\'s words only in lines under it', '- **Could go wrong:**\n  - it deletes your old lists'],
  ['something under a choice', '- **You decide:**\n  1. Where: here (recommended), or there.\n     - it moves your lists'],
]) show(`${name}: not whole, so One Task shows it as written`, [planBlockWhole(`## At a glance\n\n${block}`),
                                                                planTaskHTML(block)]);
show('a slot with plain lines under its words: whole', planBlockWhole('## At a glance\n\n- **Left out:** sharing.\n'
  + '  - prices'));
show('its heading ending in a colon: the same card', planTaskHTML('## At a glance:\n\n- **Left out:** sharing.')
  === planTaskHTML('- **Left out:** sharing.'));
show('a choice with no options keeps its why', planTaskHTML('- **You decide:**\n  1. Ship it on Monday. Why: the '
  + 'launch.').match(/<p class="gl-why">[^<]*<\/p>/)?.[0]);
show('a long word in a why, whole (it wraps anywhere)', planTaskHTML('- **You decide:**\n  1. Where: here '
  + '(recommended), or there. Why: see storefront/docs/a/very/long/path/without/any/breaks/in/it.md')
  .includes('without/any/breaks/in/it.md'));
show('escaped', planTaskHTML('- **Left out:** <script>x()</script>').includes('&lt;script&gt;'));

section('The plan card\'s choices');
const plDecide = (lines) => planCardLinesHTML(`# P\n\n## At a glance\n\n- **You decide:**\n${lines}\n`)
  .match(/You decide<\/span><span class="gl-mt">([^<]*)/)[1];
show('one, with Claude\'s pick', plDecide('  1. Where: here (recommended), or there.'));
show('several, each with Claude\'s pick', plDecide('  1. Where: here (recommended), or there.\n'
  + '  2. When: now (recommended), or later.'));
show('several, some with Claude\'s pick', plDecide('  1. Where: here (recommended), or there.\n'
  + '  2. When: now, or later.\n  3. Who: me, or you.'));
show('none with Claude\'s pick', plDecide('  1. Where: here, or there.\n  2. When: now, or later.'));

section('The plan card\'s choices, once you\'ve changed a pick');
const plCardDecide = (id) => planCardLinesHTML(plWritten, id).match(/You decide<\/span><span class="gl-mt">([^<]*)/)[1];
show('no pick changed', plCardDecide('c1'));
state.planPicks.c1 = { 0: 1 };
show('one changed', plCardDecide('c1'));
state.planPicks.c1 = { 0: 1, 1: 1 };
show('two changed', plCardDecide('c1'));
state.planPicks.c1 = { 0: 0 };
show('one put back to Claude\'s', plCardDecide('c1'));
show('no id: as before', plCardDecide());
delete state.planPicks.c1;

section('A plan with a second "#" title (an earlier version kept under it)');
const plTwice = `# Shopping list, second version

## At a glance

- **What changes for you:** one list, by aisle.
- **You decide:**
  1. Where the list lives: on your account (recommended), or this browser.

## Steps

1. The aisle table.

# Shopping list, first version

## At a glance

- **What changes for you:** a list per recipe.

## Steps

1. One list each.
`;
show('its sections: its own, then the earlier version as one', planParts(plTwice).sections.map((s) => [s.level, s.title]));
show('its card: its own block', plSlots(planGlance(plTwice)).slots);
show('nothing above the card but its title', planParts(plTwice).intro);
show('its row\'s lines', planCardLinesHTML(plTwice));
show('a plan whose sections are all "#": as before', planParts('# P\n\n# One\n\nA.\n\n# Two\n\nB.\n').sections
  .map((s) => [s.level, s.title]));

section('How to read the plan: Skimmed, or Full version of the plan');
const plLooks = (html) => html.match(/<button type="button" data-look="\w+" aria-pressed="\w+">[^<]*/g);
const plSkimmed = planReaderHTML(plWritten, { sessionId: 's', id: 'f1', waiting: true });
show('Skimmed (the first time): the toggle on the title\'s line, then the card and the folds',
  [plSkimmed.match(/<div class="gl-titleline">.*?<\/div><div class="tabs gl-looks"[^>]*>/)?.[0], plLooks(plSkimmed),
   plSkimmed.includes('class="gl-card"'), plSkimmed.includes('class="gl-fold"')]);
state.planReadAs = 'full';
const plFull = planReaderHTML(plWritten, { sessionId: 's', id: 'f1', waiting: true });
show('Full: the toggle on a line of its own, then the plan exactly as written, title and all, as the reader draws it',
  plFull);
show('…nothing of the card, the folds or the section count',
  ['gl-card', 'gl-fold', 'gl-folds-head', 'gl-titleline'].filter((c) => plFull.includes(`class="${c}`)));
show('…the same text the reader drew a plan in before',
  plFull.includes(`<article class="md">${markdownHTML(plWritten)}</article>`));
state.planPicks.f1 = { 1: 1 };
show('…picks made in Skimmed still go with the bar\'s Send Back with My Picks', core.plans.picks('f1').changed);
delete state.planPicks.f1;
show('a plan with nothing to fold: the toggle too, as Full is its text', planReaderHTML('# P\n\n## At a glance\n\n'
  + '- **Left out:** sharing.\n', { sessionId: 's', id: 'f2' }).includes('gl-looks'));
state.planReadAs = 'skimmed';

section('Opening and folding, as the panel\'s lines do');
planToggle('s', 'p9', 'choice 1');
planToggle('s', 'p9', 'fold 1');
show('an open choice and an open section each come as one piece, which grows and folds',
  planReaderHTML(plWritten, { sessionId: 's', id: 'p9' }).match(/<div class="gl-open"><div class="[^"]*"/g));
// Stand-ins for the page's elements and the panel's moves: each move is written down, and its end waits for
// plSettle, so a press can come while something is still moving.
const plMoves = [], plEnds = [], plKept = { growIn, foldAway, tween, followHeight };
const plEl = (name, height = 40) => {
  const el = { name, height, style: {}, isConnected: true, kids: [], marks: new Set(),
    get offsetHeight() { return el.style.height && el.style.height !== '' ? parseFloat(el.style.height) : el.height; },
    getBoundingClientRect: () => ({ height: el.offsetHeight }),
    classList: { contains: (c) => el.marks.has(c), add: (...c) => c.forEach((m) => el.marks.add(m)),
                 remove: (...c) => c.forEach((m) => el.marks.delete(m)) },
    getAttribute: () => el.expanded, removeAttribute() {},
    cloneNode: () => plEl(`${name}, held`, height),
    replaceWith(copy) {
      el.isConnected = false;
      plMoves.push(`${name}: held where it is, at ${el.offsetHeight}px`);
    },
    remove() {
      el.isConnected = false;
      plMoves.push(`${name}: taken out`);
    },
    appendChild(kid) {
      el.kids.push(kid);
      return kid;
    },
    querySelector: (sel) => el.kids.find((k) => k.isConnected && sel.split('.').slice(2).every((m) => k.marks.has(m))
      && (!sel.includes(':not(.gl-going)') || !k.marks.has('gl-going'))) || null };
  return el;
};
const plStyle = (x) => Object.entries(x).filter(([k]) => k !== 'overflow').map(([k, v]) => `${k} ${v || 'as it is'}`)
  .join(', ');
growIn = (el, from, done) => {
  plMoves.push(`${el.name}: grows in from ${from}px to ${el.height}px`);
  plEnds.push(done);
};
foldAway = (el, done) => {
  plMoves.push(`${el.name}: folds away from ${el.offsetHeight}px`);
  plEnds.push(done);
};
tween = (el, from, to, done, ms) => {
  Object.assign(el.style, to);
  plMoves.push(`${el.name}: from ${plStyle(from)} to ${plStyle(to)}, in ${ms}ms`);
  plEnds.push(() => {
    el.style = {};
    done?.();
  });
};
followHeight = () => {};
globalThis.getComputedStyle = (el) => ({ opacity: el.style.opacity || '1' });
const plSettle = () => {
  while (plEnds.length) plEnds.shift()?.();
};
const plFirst = (line) => {
  const first = line.appendChild(plEl('first line', 32));
  first.marks.add('gl-fl');
  return first;
};

calm.matches = false;
let plLine = plEl('section line', 33), plBody = plEl('body', 146);
plLine.expanded = 'true';
planLineOut(plFirst(plLine));
plMoves.push('· and its body comes under it:');
planOpenPart({ parentElement: { querySelector: () => null }, after() {} }, plBody);
plSettle();
show('a section opening: its first line fades as its height eases away, as the body grows',
  plMoves.splice(0));
plLine = plEl('section line', 33);
plLine.expanded = 'false';
plBody.marks.clear();
planShut(plBody);
planLineIn(plLine, (() => {
  const words = plEl('first line', 32);
  words.marks.add('gl-fl');
  return words;
})());
plSettle();
show('a section folding: its first line\'s room grows back as the body folds, then its words come in',
  plMoves.splice(0));
plBody = plEl('options', 85);
planOpenPart({ parentElement: { querySelector: () => null }, after() {} }, plBody);
plBody.style.height = '30px';
planShut(plBody);
plSettle();
show('pressed again as it grows: folded from where it had got to, never there twice', plMoves.splice(0));
plBody = plEl('options', 85);
['gl-open', 'gl-going', 'gl-moving'].forEach((m) => plBody.marks.add(m));
plBody.style.height = '50px';
planOpenPart({ parentElement: { querySelector: () => plBody } }, plEl('new options', 85));
plSettle();
show('pressed again as it folds: the same options turned round from where they are', plMoves.splice(0));

calm.matches = true;
plLine = plEl('section line', 33);
plLine.expanded = 'false';
plBody = plEl('body', 146);
planShut(plBody, () => planLineIn(plLine, (() => {
  const words = plEl('first line', 32);
  words.marks.add('gl-fl');
  return words;
})()));
plSettle();
show('with reduced motion: only fades, and the first line once the body has gone', plMoves.splice(0));
Object.assign(globalThis, plKept);
delete globalThis.getComputedStyle;

section('What VoiceOver hears');
const plContextFold = () => planFoldsHTML(plWritten, { sid: 's', id: 'v' })
  .match(/<button type="button" class="gl-fbtn" data-fold="1"[^>]*>/)[0];
show('a fold, shut and open', [plContextFold(), (state.planOpen.s['v\nfold 1'] = true, plContextFold())]);
show('a choice\'s options, a radio group named by its question', plWaiting.match(/role="radiogroup" aria-label="[^"]*"|role="radio" aria-checked="\w+"/g));

section('Escaped, whatever the plan says');
const plMarkup = `# <img src=x onerror=alert(1)>

## At a glance

- **What changes for you:** <script>alert(1)</script>
- **You decide:**
  1. <b>Q</b>: <i>a</i> (recommended), or b. Why: <u>w</u>
`;
const plMarkupAt = { sessionId: 's', id: '<"x">', who: '<Wren>', waiting: true };
show('a plan with markup in it', planReaderHTML(plMarkup, plMarkupAt));
state.planReadAs = 'full';
show('…in Full', planReaderHTML(plMarkup, plMarkupAt));
state.planReadAs = 'skimmed';

section('A plan\'s diagrams');
const plFlowPlan = `# Save recipes to cook offline

## At a glance

- **What changes for you:** a saved recipe opens with no connection.

## How they talk

\`\`\`mermaid
sequenceDiagram
  Page->>Helper: Save
\`\`\`

## Flow

\`\`\`mermaid
flowchart LR
  A[Recipe page] --> B[Kept on this device] --> C([Cook from it])
\`\`\`

## Pieces

- \`web/offline.js\`.
`;
show('a section that\'s only a diagram folds to what it shows', planSections(plFlowPlan).map((s) => [s.title, s.first]));
show('the card\'s flow: the first flow, not the sequence before it', planFlow(plFlowPlan));
show('…on the card, small, its section opened by a press', planReaderHTML(plFlowPlan, { sessionId: 's', id: 'f9' })
  .match(/<div class="gl-unit"><span class="caps">Flow[\s\S]*?<\/button><\/div>/)[0]);
show('a flow not drawn here (two loops to one step): its steps named on the card', planReaderHTML(plFlowPlan
  .replace('--> C([Cook from it])', '--> C([Cook from it])\n  C -->|again| C\n  C -->|later| C'), { sessionId: 's', id: 'f8' })
  .match(/class="dg-small" data-dg-state="\w+"|<span class="dg-small-words">[^<]*/g));
show('a flow it can\'t read (an unseen link): not on the card', planReaderHTML(plFlowPlan.replace('--> B', '~~~ B'),
  { sessionId: 's', id: 'f5' }).includes('gl-flow'));
show('a plan with no flow: no Flow on its card', planReaderHTML(plWritten, { sessionId: 's', id: 'f7' }).includes('gl-flow'));
// The press draws the view again off the page (planTurn), whose moves have their own cases above: here, nothing to
// carry over.
document.createElement = () => ({ set innerHTML(html) {}, firstElementChild: null });
const plFlowPress = core.readerPresses.find(([sel]) => sel === '.gl-flow')[1];
planReaderHTML(plFlowPlan, { sessionId: 's', id: 'f6' });
const plFlowView = { dataset: { session: 's', plan: 'f6' }, querySelector: () => null };
plFlowPress({ closest: () => plFlowView, dataset: { fold: '1' }, disabled: false });
show('pressed: its section opens', planFoldsHTML(plFlowPlan, { sid: 's', id: 'f6' })
  .match(/data-fold="\d" aria-expanded="\w+"/g));
plFlowPress({ closest: () => plFlowView, dataset: { fold: '1' }, disabled: false });
show('pressed again: it stays open', planFoldsHTML(plFlowPlan, { sid: 's', id: 'f6' })
  .match(/data-fold="1" aria-expanded="\w+"/g));
delete document.createElement;

// Diagrams, run outside the app by test.sh: a ```mermaid block read, a flow only when every part of it is read, its
// arrows' ends as Mermaid reads them; what a diagram says in words; a flow laid out in bands, its edges past the steps
// between and round them, kept clear of its steps, and drawn with every word escaped; and the figure, with Diagram and
// As written, wherever Markdown is drawn. Every diagram here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const dgRead = (text) => {
  const read = flowRead(text);
  return read.flow ? `drawn here: ${read.flow.dir}, ${read.flow.nodes.size} nodes, ${read.flow.edges.length} edges`
    : read.why;
};
const dgSave = `flowchart LR
  A[Recipe page] -->|Save for Offline| B[Recipe and photos kept on this device]
  B --> C{Online?}
  C -->|yes| D[Check for a newer version]
  C -->|no| E[Open the saved copy]
  D -->|changed| B
  D -->|same| E
  E --> F([Cook from it])`;
// The same steps in a line, with one loop back.
const dgLong = `flowchart LR
  A[Recipe page] -->|Save for Offline| B[Recipe and photos kept on this device] --> C{Online?}
  C -->|yes| D[Check for a newer version] -->|same| E[Open the saved copy] --> F([Cook from it])
  D -->|changed| B`;
const dgGrouped = 'flowchart TD\n  subgraph Kitchen\n  A[Recipe page] --> B[Cook from it]\n  end';
const dgSequence = `sequenceDiagram
  participant P as Recipe page
  participant W as Offline helper
  P->>W: Save "Lemon tart"
  W-->>P: Saved for offline
  Note over P,W: Later, with no connection
  P->>W: Open "Lemon tart"`;

section('A flow is drawn here only when every part of it is read');
show('lines, words on an edge, a decision, a dotted and a thick line', dgRead(
  'flowchart LR\n  A[One] --> B[Two] -->|yes| C{Three}\n  C -.-> D([Four]) ==> E\n  E -- worded --> F'));
show('several joined by &', dgRead('flowchart TD\n  A & B --> C'));
show('on one line, with semicolons', dgRead('graph LR; A-->B; B-->C;'));
show('a ";" inside a box, a quote or an edge\'s words is words', [dgRead(
  'flowchart TD\n  H --> I[As written, with Drawing the diagram; the app asks]\n  I -->|yes; then| J["Done; kept"]'),
  flowParse('flowchart TD\n  H --> I[As written; the app asks] --> J').flow.nodes.get('I').label]);
show('no direction: top down', dgRead('graph\n  A --> B'));
show('a click (nothing drawn for it)', dgRead('flowchart LR\n  A --> B\n  click A "https://example.com"'));
show('an edge that skips steps, a loop back, a loop to itself, and ends of every kind', [dgSave,
  'flowchart LR\n  A[Ask] --> B[Wait] -->|not yet| B\n  B --> C[Done]',
  'flowchart LR\n  A <--> B\n  B x--x C\n  C o--o D\n  D --x E\n  E --o F'].map(dgRead));
for (const [name, text] of [
  ['a class on a node', 'flowchart LR\n  A[One]:::hot --> B[Two]\n  classDef hot fill:#f00'],
  ['a style line', 'flowchart LR\n  A --> B\n  style A fill:#f00'],
  ['ends of two kinds', 'flowchart LR\n  A[One] <--o B[Two]'],
  ['a start mark with no end', 'flowchart LR\n  A <--- B'],
  ['an edge with its own name', 'flowchart LR\n  A e1@--> B'],
  ['an unseen link', 'flowchart LR\n  A ~~~ B'],
  ['a double head', 'flowchart LR\n  A -->> B'],
  ['words left over', 'flowchart LR\n  A --> B extra'],
  ['a shape not closed', 'flowchart LR\n  A[Save] --> B[[Kept'],
  ['a header with more after it', 'flowchart LR extra\n  A --> B'],
  ['groups', dgGrouped],
  ['two loops to one step (a second has nowhere of its own)', 'flowchart LR\n  A --> B\n  B -->|again| B\n  B -->|later| B'],
  ['another kind', dgSequence],
]) show(`${name}: not drawn here`, dgRead(text));

section('Arrows\' ends, as Mermaid reads them');
const dgEnds = (line) => flowParse(`flowchart LR\n  ${line}`).flow?.edges.map((e) => `${e.from} ${e.tail ?? '-'}/${e.head ?? '-'} `
  + `${e.to}${e.label ? ` "${e.label}"` : ''}${e.dotted ? ' dotted' : ''}${e.thick ? ' thick' : ''}`) ?? 'not read';
for (const line of ['A --> B', 'A --- B', 'A --x B', 'A --o B', 'A <--> B', 'A x--x B', 'A o--o B', 'A ==x B', 'A -.-o B',
  'A <==> B', 'A <-.-> B', 'A<-->B', 'A <-- both ways --> B', 'A x-- crossed --x B', 'A -- words --o B',
  'A --x B --> C', 'dev---ops', 'A x --> B', 'A < --> B', 'A -- words ==> B']) show(line, dgEnds(line));

section('Words, as they read');
show('angle brackets stay words, <br> breaks a line', flowRead('flowchart LR\n  A["Read <id>.json<br>then <b>parse</b>"] --> B')
  .flow.nodes.get('A').label);
show('quotes and stars come off', flowRead('flowchart LR\n  A["**Save** it"] --> B').flow.nodes.get('A').label);

section('What a diagram says in words');
show('a flow, its steps along its main path', diagramWords(dgSave));
show('a short flow, every step', diagramWords('graph TD\n  A[Old link] --> B{Still there?}\n  B -->|yes| C[Go to it]'));
show('a branch that ends at once isn\'t taken for the flow', diagramWords('graph TD\n  A[Block] --> B{Mermaid?}\n'
  + '  B -->|no| C[Code, as today]\n  B -->|yes| D[Read it] --> E[Draw it] --> F[Show it]'));
show('a flow not read in full', diagramWords('flowchart LR\n  A ~~~ B'));
show('a flow with groups, which isn\'t drawn here: still its steps', diagramWords(dgGrouped));
show('a sequence, who and how many messages', diagramWords(dgSequence));
show('another kind, with its title', diagramWords('pie title Where saved recipes come from\n  "Desserts" : 42'));
show('another kind, without', diagramWords('stateDiagram-v2\n  [*] --> Saved'));
show('Markdown that\'s only a diagram', diagramMarkdownWords(`\n\`\`\`mermaid\n${dgSave}\n\`\`\`\n`));
show('Markdown with words beside it', diagramMarkdownWords(`Here it is:\n\n\`\`\`mermaid\n${dgSave}\n\`\`\``));
show('a block in another language', diagramMarkdownWords('```js\nx\n```'));

section('A flow laid out');
const dgPlaced = (text, room) => {
  const L = flowLayout(flowRead(text).flow, room, flowRoughWidth(12), 12);
  return `${L.W}×${L.H}: ${L.nodes.map((n) => `${n.id} ${Math.round(n.x)},${Math.round(n.y)}`).join(' · ')}`;
};
show('left to right, with room', dgPlaced(dgLong, 1400));
show('left to right, in a narrow room: bands, filled evenly', dgPlaced(dgLong, 520));
show('top down', dgPlaced('graph TD\n  A[Old link] --> B{Still there?}\n  B -->|yes| C[Go to it]\n  B -->|no| D[Search]', 600));
show('right to left: the same, turned round', dgPlaced('flowchart RL\n  A[One] --> B[Two]', 600));
show('bottom to top', dgPlaced('flowchart BT\n  A[One] --> B[Two]', 600));
show('a loop back keeps its nodes in place', dgPlaced('flowchart LR\n  A --> B --> C\n  C --> A', 900));

section('Edges past the steps between, round them, and their words, kept clear of the steps');
const dgLaid = (text, room = 500) => flowLayout(flowRead(text).flow, room, flowRoughWidth(12), 12);
const dgEdge = (L, from, to) => L.edges.find((e) => e.from === from && e.to === to);
const dgBox = (L, id) => {
  const n = L.nodes.find((x) => x.id === id);
  return `${id} across ${Math.round(n.x)}–${Math.round(n.x + n.w)}, down ${Math.round(n.y)}–${Math.round(n.y + n.h)}`;
};
const dgWords = (e) => `words across ${Math.round(e.box.x)}–${Math.round(e.box.x + e.box.w)}, down `
  + `${Math.round(e.box.y)}–${Math.round(e.box.y + e.box.h)}`;
const dgShown = (text, room = 500) => {
  const L = flowPlace(flowRead(text).flow, room, flowRoughWidth(12), 12);
  return !L ? 'as written' : L.banded ? 'drawn in bands' : flowLayout(flowRead(text).flow, room, flowRoughWidth(12), 12).banded
    ? 'drawn on one line' : 'drawn';
};
const dgSettled = (text, room = 500) => flowPlace(flowRead(text).flow, room, flowRoughWidth(12), 12);
const dgJump = 'flowchart TD\n  A[Recipe page] --> B[Save for Offline] --> C[Saved]\n  A -->|no room| C';
let dgL = dgLaid(dgJump);
show('top down, past one step: through a stand-in\'s lane beside it, its words on that run, as wide as they are',
  [dgBox(dgL, 'B'), dgEdge(dgL, 'A', 'C').d, dgWords(dgEdge(dgL, 'A', 'C')), dgL.clear]);
dgL = dgSettled('flowchart TD\n  A[Recipe page] --> B[Add to List]\n  B --> C{Already on the list?}\n'
  + '  C -->|yes| D[Add to its amount]\n  C -->|no| E[New line, by aisle]\n  D --> F[Same on your phone]\n'
  + '  E --> F\n  A -->|shared list| F\n  F -->|fix a line| B');
show('a jump\'s words on its own run beside the steps it passes, never where it leaves or on another line',
  [dgWords(dgEdge(dgL, 'A', 'F')), dgBox(dgL, 'C'), dgEdge(dgL, 'A', 'F').d, dgL.clear]);
dgL = dgLaid('flowchart TD\n  A[Ask] --> B[Look] --> C[Check] --> D[Write] --> E[Done]\n  A -->|nothing to do| E');
show('past three steps', [dgEdge(dgL, 'A', 'E').d, dgL.clear]);
const dgWrap = 'flowchart LR\n  A[Recipe page] --> B[Add to List] --> C[Pick the servings] --> D[Merge with the list]'
  + ' --> E[Group by aisle]\n  B -->|already merged| E';
dgL = dgLaid(dgWrap, 520);
show('left to right, past steps into the next band: the steps on its way carry on beside it, so on one line', [dgL.banded,
  dgL.clear, dgShown(dgWrap, 520)]);
const dgTwoOn = 'flowchart LR\n  A[Recipe page] --> B[Add to List] & C[Share the recipe]\n'
  + '  B --> D[Group by aisle] --> E[Tick as you shop]\n  C --> F[Send a link] --> G[Open it on a phone]';
show('two steps carrying on into the next band would drop through each other: laid out on one line',
  [dgLaid(dgTwoOn, 420).banded, dgLaid(dgTwoOn, 420).clear, dgShown(dgTwoOn, 420)]);
const dgUpTwo = 'flowchart LR\n  A[Recipe page] --> B[Add to List] --> C[Pick the servings] --> D[Merge with the list]'
  + ' --> E[Group by aisle] --> F[Tick as you shop]\n  F -->|start again| A';
dgL = dgLaid(dgUpTwo, 400);
show('a loop back up two bands: up its own lane outside the bands\' left side', [new Set(dgL.nodes.map((n) => n.band)).size,
  dgEdge(dgL, 'F', 'A').d, dgL.clear]);
dgL = dgLaid('flowchart TD\n  A[Go] --> B[A much wider step than the others here] --> C[Done?]\n  C -->|no| A');
show('top down, a loop back past a wider step: round the right of every rank it passes', [dgBox(dgL, 'B'),
  dgEdge(dgL, 'C', 'A').d, dgL.clear]);
dgL = dgLaid('flowchart TD\n  A[Start] --> B{Check}\n  B -->|fix| C[Fix it]\n  B -->|ok| D[Ship]\n  C --> A');
show('a loop back from a step with one beside it: down from its foot and along the gap, past it', [dgBox(dgL, 'D'),
  dgEdge(dgL, 'C', 'A').d, dgL.clear]);
dgL = dgSettled('flowchart TD\n  A[Check] -->|retry| B[Check again]\n  B -->|start again| A');
show('words on a loop back, beside words on the edge it comes back past: its run out far enough for them',
  [dgWords(dgEdge(dgL, 'A', 'B')), dgEdge(dgL, 'B', 'A').d, dgWords(dgEdge(dgL, 'B', 'A'))]);
dgL = dgSettled('flowchart LR\n  A[Plan it] --> B[Build it] --> C[Test it] --> D[Review it] --> E[Ship it]\n'
  + '  D -->|rejected| A\n  C -->|fails| B', 535);
show('loops back nest, the shortest innermost, each with room for its words', [dgEdge(dgL, 'C', 'B').d,
  dgEdge(dgL, 'D', 'A').d, dgWords(dgEdge(dgL, 'C', 'B')), dgWords(dgEdge(dgL, 'D', 'A'))]);
dgL = dgSettled('flowchart TD\n  A[Ask] --> B[Wait]\n  B -->|again| A\n  B -->|later| A');
show('two loops back between one pair of steps: moved apart at both ends', dgL.edges.filter((e) => e.from === 'B')
  .map((e) => e.d.split(' ')[0]));
dgL = dgSettled('flowchart TD\n  A[Run the tests] -->|flaky| A\n  A -->|pass| B[Ship it]\n  A -->|fail| C[Fix it]\n  C --> A');
show('a loop back into a step with a loop to itself: in from above, clear of the loop', dgEdge(dgL, 'C', 'A').d);
dgL = dgSettled('flowchart LR\n  A[Recipe page saved here] -->|kept for offline reading| B[Opened later offline]', 300);
show('a drop into the band below that\'s nearly straight: its end on its own line', [dgEdge(dgL, 'A', 'B').d,
  `tip ${dgEdge(dgL, 'A', 'B').tip.map(Math.round)}`]);
const dgDropped = 'flowchart LR\n  A[Recipe page] --> B[Add to List] --> C[Pick the servings] --> D[Merge with the list]'
  + ' --> E[Group by aisle]\n  E -->|start again| C';
show('a step dropping into the next band that a loop back comes into: on one line, so they don\'t share the drop',
  [dgLaid(dgDropped, 520).banded, dgLaid(dgDropped, 520).clear, dgShown(dgDropped, 520)]);
dgL = dgLaid('flowchart TD\n  A[Ask] -->|"one<br>two<br>three"| B[Answer]');
show('three lines of words: the gap as deep as they need', [dgBox(dgL, 'B'), dgWords(dgEdge(dgL, 'A', 'B')), dgL.clear]);
dgL = dgSettled('flowchart TD\n  A{Online?} -->|check it again| B[Check for a newer version]\n'
  + '  A -->|open it saved| C[Open the saved copy]');
show('words on edges fanning out: on together, where their lines have parted', [dgWords(dgEdge(dgL, 'A', 'B')),
  dgWords(dgEdge(dgL, 'A', 'C')), dgL.clear]);
dgL = dgSettled('flowchart TD\n  A{Online?} -->|yes, check for a newer one| B[Check for a newer version]\n'
  + '  A -->|no, open the saved copy| C[Open the saved copy]');
show('too wide to sit side by side: their gap grows, and each has its own place on its line',
  [dgWords(dgEdge(dgL, 'A', 'B')), dgWords(dgEdge(dgL, 'A', 'C')), dgL.clear]);
const dgCrowd = 'flowchart TD\n  A{Where to?} -->|the first way out| B[One]\n  A -->|the second way out| C[Two]\n'
  + '  A -->|the third way out| D[Three]\n  A -->|the fourth way out| E[Four]';
show('words that fit nowhere: their gap grows until they do', [dgLaid(dgCrowd).clear, dgLaid(dgCrowd).crowded,
  dgLaid(dgCrowd).H, dgSettled(dgCrowd).H, dgShown(dgCrowd)]);
dgL = dgLaid('flowchart LR\n  A[Save] -->|now| B[Saved]\n  A -->|later| B');
show('two edges from one step to another: each moved across, so they aren\'t drawn as one',
  dgL.edges.map((e) => e.d.split(' ')[0]));
dgL = dgLaid('flowchart TD\n  A[Ask] --> B[Wait] -->|not yet| B\n  B --> C[Done]');
show('a loop to itself, top down: out at its right, its words beyond it', [dgBox(dgL, 'B'), dgEdge(dgL, 'B', 'B').d,
  dgWords(dgEdge(dgL, 'B', 'B')), dgL.clear]);
dgL = dgLaid('flowchart LR\n  A[Ask] --> B[Wait] -->|not yet| B\n  B --> C[Done]');
show('and left to right, under it', [dgBox(dgL, 'B'), dgEdge(dgL, 'B', 'B').d, dgL.clear]);
show('right to left and bottom to top: both ends turned round with the rest', ['flowchart RL\n  A <--> B',
  'flowchart BT\n  A x--x B'].map((text) => {
  const e = dgLaid(text).edges[0];
  return `foot ${e.foot.map(Math.round)} pointing ${e.footWay}, tip ${e.tip.map(Math.round)} pointing ${e.way}`;
}));
const dgBoxAt = (id, x, y) => ({ id, x, y, w: 60, h: 30 });
show('a line through a step that isn\'t one of its ends: not clear', flowClear({
  nodes: [dgBoxAt('A', 0, 0), dgBoxAt('B', 100, 0), dgBoxAt('C', 200, 0)],
  edges: [{ from: 'A', to: 'C', d: 'M60,15 H200', lines: [] }] }));
show('words on another edge\'s line: not clear', flowClear({ nodes: [dgBoxAt('A', 0, 0), dgBoxAt('B', 0, 100)],
  edges: [{ from: 'A', to: 'B', d: 'M20,30 V100', box: { x: 0, y: 50, w: 60, h: 18 } },
          { from: 'A', to: 'B', d: 'M40,30 V100' }] }));
show('words on words: not clear', flowClear({ nodes: [dgBoxAt('A', 0, 0), dgBoxAt('B', 0, 100)],
  edges: [{ from: 'A', to: 'B', d: 'M30,30 V100', box: { x: 0, y: 50, w: 60, h: 18 } },
          { from: 'A', to: 'B', d: 'M40,30 V100', box: { x: 20, y: 55, w: 60, h: 18 } }] }));

section('A flow drawn');
const dgDrawn = (text, words = '') => flowSVG(flowPlace(flowRead(text).flow, 600, flowRoughWidth(12), 12), words);
show('its parts', dgDrawn('flowchart LR\n  A[One] -->|yes| B{Two}\n  B -.-> C([Three])', 'Three steps')
  .match(/<svg[^>]*>|class="[^"]+"/g).filter((x, i, all) => all.indexOf(x) === i));
show('every word escaped', dgDrawn('flowchart LR\n  A["<script>alert(1)</script>"] -->|"<img src=x>"| B["Tom & Jerry"]',
  '<script>').match(/<tspan[^>]*>[^<]*<\/tspan>|aria-label="[^"]*"/g));
show('each box\'s words sit on its middle: one line, and two', dgDrawn('flowchart TD\n  A[One] --> B["Two<br>lines"]')
  .match(/<rect class="dg-node"[^>]*>|<text class="dg-words"[^>]*>/g));
show('nothing in it runs', /<script|<img|on\w+=/i.test(dgDrawn('flowchart LR\n  A["<script>x</script>"] --> B["<img onerror=y>"]')));
show('each end at its tip: an arrow, a circle, a cross, at one end and both, an open line none',
  ['A --> B', 'A --o B', 'A --x B', 'A <--> B', 'A o--o B', 'A x--x B', 'A --- B'].map((line) =>
    `${line}: ${dgDrawn(`flowchart LR\n  ${line}`).match(/<(polygon|circle|path) class="dg-(arrow|cross)"/g)
      ?.map((m) => m.split(' ')[0].slice(1)).join(' ') ?? 'none'}`));
show('a cross\'s strokes', dgDrawn('flowchart TD\n  A --x B').match(/<path class="dg-cross"[^>]*>/)[0]);

section('The figure, wherever Markdown is drawn');
const dgFence = `Before.\n\n\`\`\`mermaid\n${dgLong}\n\`\`\`\n\nAfter.`;
show('a flow: its kind, Diagram and As written, then its text until it\'s drawn', markdownHTML(dgFence));
show('another kind: as written, saying why', markdownHTML(`\`\`\`mermaid\n${dgSequence}\n\`\`\``));
state.diagramsWritten.add(diagramKey(dgLong));
show('turned to As written, it stays that way as it\'s drawn again',
  markdownHTML(dgFence).match(/data-dg-state="\w+"|aria-pressed="\w+"/g));
state.diagramsWritten.clear();
show('a flow not drawn here: as written, saying why', markdownHTML(`\`\`\`mermaid\n${dgGrouped}\n\`\`\``)
  .match(/data-dg-state="\w+"|<p class="dg-why">[^<]*|dg-tabs/g));
show('the line saying why for each', ['flowchart LR\n  A ~~~ B', dgGrouped, 'pie title Saved\n  "Desserts" : 4']
  .map((text) => markdownHTML(`\`\`\`mermaid\n${text}\n\`\`\``).match(/<p class="dg-why">([^<]*)/)[1]));
show('on the list (a request\'s card): code, as before', markdownHTML(dgFence, 'list'));
show('a block in another language: code, as before', markdownHTML('```js\nconst x = 1;\n```'));
show('a block named for something every object has: code', markdownHTML('```constructor\nx\n```'));
show('its text escaped', markdownHTML('```mermaid\nflowchart LR\n  A["</code><script>"] --> B\n```').includes('<script>'));

section('Small, on a card');
show('a flow drawn here: its words until it\'s drawn', diagramSmallHTML(dgLong));
show('one not drawn here: its words', diagramSmallHTML(dgGrouped).match(/data-dg-state="\w+"/)[0]);
show('the first flow in Markdown, read as the panel reads its code blocks', [
  diagramFirstFlow(`\`\`\`mermaid\n${dgSequence}\n\`\`\`\n\n\`\`\`mermaid\ngraph TD\n  A --> B\n\`\`\``),
  diagramFirstFlow('```mermaid-js\ngraph TD\n  A --> B\n```'),
  diagramFirstFlow('- a step\n  ```mermaid\n  graph TD\n  ```'),
  diagramFirstFlow('> ```mermaid\n> graph LR\n>   A --> B\n> ```')]);
show('what a diagram\'s text says', diagramWords(dgLong));
show('the first flow with something to show: one read in part is passed over', [
  diagramFirstFlow(`\`\`\`mermaid\nflowchart LR\n  A[[Kept\n\`\`\`\n\n\`\`\`mermaid\n${dgSave}\n\`\`\``)?.slice(0, 12),
  diagramFirstFlow('```mermaid\nflowchart LR\n  A[[Kept\n```')]);

section('What it plugs into');
show('the core\'s', [typeof core.fences.mermaid, Object.keys(core.diagrams), core.readerDrawn.includes(diagramsDraw),
  typeof mdFences]);

section('A card\'s small drawing measured again as its room changes');
// Stand-ins for a small drawing on the page: its room is set by hand, and what's drawn in it is read from the SVG's
// own size.
globalThis.getComputedStyle = () => ({ getPropertyValue: () => '12px', paddingLeft: '0', paddingRight: '0', fontFamily: '' });
document.documentElement = {};
const dgSmall = (text, room, small = true) => {
  const draw = { html: '', firstElementChild: null,
    set innerHTML(html) {
      draw.html = html;
      const size = html.match(/data-width="([\d.]+)" data-height="([\d.]+)"/);
      draw.firstElementChild = size ? { dataset: { width: size[1], height: size[2] }, style: {} } : null;
    } };
  const el = { clientWidth: room, dataset: { dgState: flowRead(text).flow ? 'todo' : 'words' }, draw,
    classList: { contains: (c) => small && c === 'dg-small' }, matches: (sel) => sel.includes(`[data-dg-state="${el.dataset.dgState}"]`),
    querySelectorAll: () => [], querySelector: (sel) => (sel === '.dg-draw' ? draw : { textContent: text }) };
  return el;
};
const dgEight = 'flowchart LR\n  A[Recipe page] --> B[Add to List] --> C[Pick the servings] --> D[Merge with the list]'
  + ' --> E[Group by aisle] --> F[Tick as you shop] --> G[Same on your phone] --> H([Cook from it])';
const dgCard = dgSmall(dgEight, 188);
diagramsDraw(dgCard);
show('the reader still being placed: too narrow to read, so its steps in words', [dgCard.dataset.dgState, dgCard.dataset.dgRoom]);
dgCard.clientWidth = 445;
diagramsDraw(dgCard);
show('its room at its width: measured again, and drawn', [dgCard.dataset.dgState, dgCard.dataset.dgRoom,
  dgCard.draw.firstElementChild.style.width]);
// The smallest words on a card: an edge's, a size smaller than the steps', so it's shrunk to words sooner.
globalThis.getComputedStyle = () => ({ getPropertyValue: (token) => (token === '--size-small' ? '11px' : '12px'),
  paddingLeft: '0', paddingRight: '0', fontFamily: '' });
const dgWide = (text) => Number(flowSVG(flowPlace(flowRead(text).flow, 1000, flowRoughWidth(12), 12), '')
  .match(/data-width="([\d.]+)"/)[1]);
show('shrunk to 63%: drawn with only steps\' words, its steps in words when an edge has words of its own',
  ['flowchart TD\n  A[Recipe page] --> B[Cook from it]', 'flowchart TD\n  A[Recipe page] -->|later| B[Cook from it]']
    .map((text) => {
      const card = dgSmall(text, Math.round(dgWide(text) * 0.63));
      diagramsDraw(card);
      return card.dataset.dgState;
    }));
globalThis.getComputedStyle = () => ({ getPropertyValue: () => '12px', paddingLeft: '0', paddingRight: '0', fontFamily: '' });
const dgUnread = dgSmall(dgGrouped, 445);
diagramsDraw(dgUnread);
show('one not drawn here stays words, whatever its room', dgUnread.dataset.dgState);

section('A flow whose lines or words wouldn\'t keep clear at its width');
// flowPlace finding no clear way at that width, as for a flow whose bands can't keep clear there.
const dgPlace = flowPlace;
flowPlace = () => null;
const dgFigure = dgSmall(dgLong, 500, false);
diagramsDraw(dgFigure);
const dgCardUnclear = dgSmall(dgLong, 445);
diagramsDraw(dgCardUnclear);
flowPlace = dgPlace;
show('the figure: as written, saying why, without Diagram and As written (unclear); a card: its steps in words (shrunk)',
  [dgFigure.dataset.dgState, dgCardUnclear.dataset.dgState]);
dgFigure.clientWidth = 504;
diagramsDraw(dgFigure);
show('measured again only once its room changes by 8px or more', dgFigure.dataset.dgState);
dgFigure.clientWidth = 700;
dgCardUnclear.clientWidth = 1100;
diagramsDraw(dgFigure);
diagramsDraw(dgCardUnclear);
show('and drawn once it keeps clear', [dgFigure.dataset.dgState, dgCardUnclear.dataset.dgState]);
